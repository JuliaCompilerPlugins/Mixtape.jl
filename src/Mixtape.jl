module Mixtape

# Experimental re-write based upon:
# https://github.com/Keno/Compiler3.jl/blob/master/src/extracting_interpreter.jl

using LLVM
using LLVM.Interop
using LLVM_full_jll
using MacroTools: @capture,
                  postwalk,
                  rmlines,
                  unblock
using CodeInfoTools
using CodeInfoTools: resolve
using Core: MethodInstance,
            CodeInstance,
            CodeInfo
using Core.Compiler: WorldView,
                     NativeInterpreter,
                     InferenceResult,
                     coverage_enabled,
                     copy_exprargs,
                     convert_to_ircode,
                     slot2reg,
                     compact!,
                     ssa_inlining_pass!,
                     getfield_elim_pass!,
                     adce_pass!,
                     type_lift_pass!,
                     verify_ir,
                     verify_linetable

using GPUCompiler: cached_compilation,
                   FunctionSpec

import GPUCompiler: AbstractCompilerTarget,
                    NativeCompilerTarget,
                    AbstractCompilerParams,
                    CompilerJob,
                    julia_datalayout,
                    llvm_machine,
                    llvm_triple

import Core.Compiler: InferenceState,
                      InferenceParams,
                      AbstractInterpreter,
                      OptimizationParams,
                      InferenceState,
                      OptimizationState,
                      get_world_counter,
                      get_inference_cache,
                      lock_mi_inference,
                      unlock_mi_inference,
                      code_cache,
                      optimize,
                      may_optimize,
                      may_compress,
                      may_discard_trees,
                      add_remark!

#####
##### Exports
#####

export CompilationContext,
       NoContext,
       allow,
       transform,
       optimize!,
       OptimizationBundle,
       get_ir,
       get_state,
       julia_passes!,
       jit,
       emit,
       @ctx,
       @load_abi

include("context.jl")

#####
##### Utilities
#####

function get_methodinstance(@nospecialize(sig))
    ms = Base._methods_by_ftype(sig, 1, Base.get_world_counter())
    @assert length(ms) == 1
    m = ms[1]
    mi = ccall(:jl_specializations_get_linfo,
               Ref{MethodInstance}, (Any, Any, Any),
               m[3], m[1], m[2])
    return mi
end

function infer(interp, fn, t::Type{T}) where T <: Tuple
    mi = get_methodinstance(Tuple{typeof(fn), t.parameters...})
    src = Core.Compiler.typeinf_ext_toplevel(interp, mi)
    @assert(haskey(interp.code, mi))
    ci = getindex(interp.code, mi)
    if ci !== nothing && ci.inferred === nothing
        ci.inferred = src
    end
    return mi
end

#####
##### Interpreter
#####

# Based on: https://github.com/Keno/Compiler3.jl/blob/master/exploration/static.jl

# Holds its own cache.
struct StaticInterpreter{I, C} <: AbstractInterpreter
    code::Dict{MethodInstance, CodeInstance}
    inner::I
    messages::Vector{Tuple{MethodInstance, Int, String}}
    optimize::Bool
    ctx::C
end

function StaticInterpreter(; ctx = NoContext(), opt = false)
    return StaticInterpreter(Dict{MethodInstance, CodeInstance}(),
                             NativeInterpreter(),
                             Tuple{MethodInstance, Int, String}[],
                             opt,
                             ctx)
end

InferenceParams(si::StaticInterpreter) = InferenceParams(si.inner)
OptimizationParams(si::StaticInterpreter) = OptimizationParams(si.inner)
get_world_counter(si::StaticInterpreter) = get_world_counter(si.inner)
get_inference_cache(si::StaticInterpreter) = get_inference_cache(si.inner)
lock_mi_inference(si::StaticInterpreter, mi::MethodInstance) = nothing
unlock_mi_inference(si::StaticInterpreter, mi::MethodInstance) = nothing
code_cache(si::StaticInterpreter) = si.code
Core.Compiler.get(a::Dict, b, c) = Base.get(a, b, c)
Core.Compiler.get(a::WorldView{<:Dict}, b, c) = Base.get(a.cache,b,c)
Core.Compiler.haskey(a::Dict, b) = Base.haskey(a, b)
Core.Compiler.haskey(a::WorldView{<:Dict}, b) =
Core.Compiler.haskey(a.cache, b)
Core.Compiler.setindex!(a::Dict, b, c) = setindex!(a, b, c)
Core.Compiler.may_optimize(si::StaticInterpreter) = si.optimize
Core.Compiler.may_compress(si::StaticInterpreter) = false
Core.Compiler.may_discard_trees(si::StaticInterpreter) = false
function Core.Compiler.add_remark!(si::StaticInterpreter, sv::InferenceState, msg)
    push!(si.messages, (sv.linfo, sv.currpc, msg))
end

#####
##### Pre-inference
#####

function resolve_generic(a)
    if a isa Type && a <: Function && isdefined(a, :instance)
        return a.instance
    else
        return resolve(a)
    end
end

function custom_pass!(interp::StaticInterpreter, result::InferenceResult, mi::Core.MethodInstance, src)
    src === nothing && return src
    mi.specTypes isa UnionAll && return src
    sig = Tuple(mi.specTypes.parameters)
    as = map(resolve_generic, sig)
    if allow(interp.ctx, mi.def.module, as...)
        src = transform(interp.ctx, src, sig)
    end
    return src
end

function InferenceState(result::InferenceResult, cached::Bool, interp::StaticInterpreter)
    src = Core.Compiler.retrieve_code_info(result.linfo)
    mi = result.linfo
    src = custom_pass!(interp, result, mi, src)
    src === nothing && return nothing
    Core.Compiler.validate_code_in_debug_mode(result.linfo, src, "lowered")
    return InferenceState(result, src, cached, interp)
end

#####
##### Julia optimization pipeline
#####

@static if VERSION >= v"1.7.0-DEV.662"
    using Core.Compiler: finish as _finish
else
    function _finish(interp::AbstractInterpreter,
            opt::OptimizationState,
            params::OptimizationParams, ir, @nospecialize(result))
        return Core.Compiler.finish(opt, params, ir, result)
    end
end

struct OptimizationBundle
    ir::Core.Compiler.IRCode
    sv::OptimizationState
end
get_ir(b::OptimizationBundle) = b.ir
get_state(b::OptimizationBundle) = b.sv

@doc(
"""
    struct OptimizationBundle
        ir::Core.Compiler.IRCode
        sv::OptimizationState
    end
    get_ir(b::OptimizationBundle) = b.ir
    get_state(b::OptimizationBundle) = b.sv

Object which holds inferred `ir::Core.Compiler.IRCode` and a `Core.Compiler.OptimizationState`. Provided to the user through [`optimize!`](@ref), so that the user may plug in their own optimizations.
""", OptimizationBundle)

function julia_passes!(ir::Core.Compiler.IRCode, ci::CodeInfo,
        sv::OptimizationState)
    ir = compact!(ir)
    ir = ssa_inlining_pass!(ir, ir.linetable, sv.inlining, ci.propagate_inbounds)
    ir = compact!(ir)
    ir = getfield_elim_pass!(ir)
    ir = adce_pass!(ir)
    ir = type_lift_pass!(ir)
    ir = compact!(ir)
    return ir
end

julia_passes!(b::OptimizationBundle) = julia_passes!(b.ir, b.sv.src, b.sv)

function optimize(interp::StaticInterpreter, opt::OptimizationState,
        params::OptimizationParams, @nospecialize(result))
    nargs = Int(opt.nargs) - 1
    mi = opt.linfo
    meth = mi.def
    preserve_coverage = coverage_enabled(opt.mod)
    ir = convert_to_ircode(opt.src, copy_exprargs(opt.src.code), preserve_coverage, nargs, opt)
    ir = slot2reg(ir, opt.src, nargs, opt)
    b = OptimizationBundle(ir, opt)
    ir :: Core.Compiler.IRCode = optimize!(interp.ctx, b)
    verify_ir(ir)
    verify_linetable(ir.linetable)
    return _finish(interp, opt, params, ir, result)
end

#####
##### FunctionGraph
#####

abstract type FunctionGraph end

struct StaticSubGraph <: FunctionGraph
    code::Dict{MethodInstance, Any}
    instances::Vector{MethodInstance}
    entry::MethodInstance
end

entrypoint(ssg::StaticSubGraph) = ssg.entry

get_codeinstance(ssg::StaticSubGraph, mi::MethodInstance) = getindex(ssg.code, mi)

function get_codeinfo(code::Core.CodeInstance)
    ci = code.inferred
    if ci isa Vector{UInt8}
        return Core.Compiler._uncompressed_ir(code, ci)
    else
        return ci
    end
end

function get_codeinfo(graph::StaticSubGraph,
        cursor::MethodInstance)
    return get_codeinfo(get_codeinstance(graph, cursor))
end

function analyze(@nospecialize(f), tt::Type{T};
        ctx = NoContext(), opt = false) where T <: Tuple
    si = StaticInterpreter(; ctx = ctx, opt = opt)
    mi = infer(si, f, tt)
    si, StaticSubGraph(si.code, collect(keys(si.code)), mi)
end

#####
##### LLVM optimization pipeline
#####

function optimize!(tm, mod::LLVM.Module)
    ModulePassManager() do pm
        add_library_info!(pm, triple(mod))
        add_transform_info!(pm, tm)
        propagate_julia_addrsp!(pm)
        scoped_no_alias_aa!(pm)
        type_based_alias_analysis!(pm)
        basic_alias_analysis!(pm)
        cfgsimplification!(pm)
        scalar_repl_aggregates!(pm) # SSA variant?
        mem_cpy_opt!(pm)
        always_inliner!(pm)
        alloc_opt!(pm)
        instruction_combining!(pm)
        cfgsimplification!(pm)
        scalar_repl_aggregates!(pm) # SSA variant?
        instruction_combining!(pm)
        jump_threading!(pm)
        instruction_combining!(pm)
        reassociate!(pm)
        early_cse!(pm)
        alloc_opt!(pm)
        loop_idiom!(pm)
        loop_rotate!(pm)
        lower_simdloop!(pm)
        licm!(pm)
        loop_unswitch!(pm)
        instruction_combining!(pm)
        ind_var_simplify!(pm)
        loop_deletion!(pm)
        alloc_opt!(pm)
        scalar_repl_aggregates!(pm) # SSA variant?
        instruction_combining!(pm)
        gvn!(pm)
        mem_cpy_opt!(pm)
        sccp!(pm)
        instruction_combining!(pm)
        jump_threading!(pm)
        dead_store_elimination!(pm)
        alloc_opt!(pm)
        cfgsimplification!(pm)
        loop_idiom!(pm)
        loop_deletion!(pm)
        jump_threading!(pm)
        aggressive_dce!(pm)
        instruction_combining!(pm)
        barrier_noop!(pm)
        lower_exc_handlers!(pm)
        gc_invariant_verifier!(pm, false)
        late_lower_gc_frame!(pm)
        final_lower_gc!(pm)
        lower_ptls!(pm, #=dump_native=# false)
        cfgsimplification!(pm)
        instruction_combining!(pm) # Extra for Enzyme
        run!(pm, mod)
    end
end

#####
##### Entry codegen with cached compilation
#####

# Interpreter holds the cache.
function cache_lookup(si::StaticInterpreter, mi::MethodInstance,
        min_world, max_world)
    Base.get(si.code, mi, nothing)
end

# Mostly from GPUCompiler.
# In future, try to upstream any requires changes.
function codegen(job::CompilerJob)
    f = job.source.f
    tt = job.source.tt
    opt = job.params.opt
    si, ssg = analyze(f, tt;
                      ctx = job.params.ctx, opt = opt) # Populate local cache.
    world = get_world_counter(si)
    λ_lookup = (mi, min, max) -> cache_lookup(si, mi, min, max)
    lookup_cb = @cfunction($λ_lookup, Any, (Any, UInt, UInt))
    params = Base.CodegenParams(;
                                track_allocations = false,
                                code_coverage     = false,
                                prefer_specsig    = true,
                                gnu_pubnames      = false,
                                lookup            = Base.unsafe_convert(Ptr{Nothing}, lookup_cb))

    GC.@preserve lookup_cb begin
        native_code = ccall(:jl_create_native,
                            Ptr{Cvoid},
                            (Vector{MethodInstance},
                             Base.CodegenParams, Cint),
                            [ssg.entry],
                            params, 1) # = extern policy = #
        @assert native_code != C_NULL
        llvm_mod_ref = ccall(:jl_get_llvm_module,
                             LLVM.API.LLVMModuleRef,
                             (Ptr{Cvoid},),
                             native_code)
        @assert llvm_mod_ref != C_NULL
        llvm_mod = LLVM.Module(llvm_mod_ref)
    end
    code = cache_lookup(si, ssg.entry, world, world)
    llvm_func_idx = Ref{Int32}(-1)
    llvm_specfunc_idx = Ref{Int32}(-1)
    ccall(:jl_get_function_id,
          Nothing,
          (Ptr{Cvoid}, Any, Ptr{Int32}, Ptr{Int32}),
          native_code, code, llvm_func_idx, llvm_specfunc_idx)
    @assert llvm_specfunc_idx[] != -1
    @assert llvm_func_idx[] != -1
    llvm_func_ref = ccall(:jl_get_llvm_function,
                          LLVM.API.LLVMValueRef,
                          (Ptr{Cvoid}, UInt32),
                          native_code,
                          llvm_func_idx[] - 1)
    @assert llvm_func_ref != C_NULL
    llvm_func = LLVM.Function(llvm_func_ref)
    llvm_specfunc_ref = ccall(:jl_get_llvm_function,
                              LLVM.API.LLVMValueRef,
                              (Ptr{Cvoid}, UInt32),
                              native_code,
                              llvm_specfunc_idx[] - 1)
    @assert llvm_specfunc_ref != C_NULL
    llvm_specfunc = LLVM.Function(llvm_specfunc_ref)
    triple!(llvm_mod, llvm_triple(job.target))
    if julia_datalayout(job.target) !== nothing
        datalayout!(llvm_mod, julia_datalayout(job.target))
    end
    return (Any, llvm_specfunc, llvm_func, llvm_mod)
end

struct MixtapeCompilerTarget <: AbstractCompilerTarget end

llvm_triple(::MixtapeCompilerTarget) = Sys.MACHINE

function get_llvm_optlevel(opt_level::Int)
    if opt_level < 2
        optlevel = LLVM.API.LLVMCodeGenLevelNone
    elseif opt_level == 2
        optlevel = LLVM.API.LLVMCodeGenLevelDefault
    else
        optlevel = LLVM.API.LLVMCodeGenLevelAggressive
    end
    return optlevel
end

struct MixtapeCompilerParams <: AbstractCompilerParams
    opt::Bool
    optlevel::Int
    ctx::CompilationContext
end

function MixtapeCompilerParams(; opt = false,
        optlevel = Base.JLOptions().opt_level,
        ctx = NoContext())
    return MixtapeCompilerParams(opt, optlevel, ctx)
end

function llvm_machine(::MixtapeCompilerTarget,
        params::MixtapeCompilerParams)
    optlevel = get_llvm_optlevel(params.optlevel)
    tm = LLVM.JITTargetMachine(; optlevel=optlevel)
    LLVM.asm_verbosity!(tm, true)
    return tm
end


struct Entry{F, RT, TT}
    f::F
    specfunc::Ptr{Cvoid}
    func::Ptr{Cvoid}
end

@generated function (entry::Entry{F, RT, TT})(args...) where {F, RT, TT}
    # Slow ABI -- requires array allocation and unpacking. But stable.
    expr = quote
        args = Any[args...]
        ccall(entry.func,
              Any,
              (Any, Ptr{Any}, Int32),
              entry.f, args, length(args))
    end
    return expr
end

const jit_compiled_cache = Dict{UInt, Any}()

function jit(@nospecialize(f), tt::Type{T};
        ctx = NoContext(), opt = true,
        optlevel = Base.JLOptions().opt_level) where T <: Tuple
    fspec = FunctionSpec(f, tt, false, nothing) #=name=#
    job = CompilerJob(MixtapeCompilerTarget(),
                      fspec,
                      MixtapeCompilerParams(;
                                            opt = opt,
                                            ctx = ctx,
                                            optlevel = optlevel))
    return cached_compilation(jit_compiled_cache, job, _jit, _jitlink)
end

@doc(
"""
    jit(f::F, tt::Type{T}; ctx = NoContext(),
        opt = true,
        optlevel = Base.JLOptions().opt_level) where {F, T <: Type}

Compile and specialize a method instance for signature `Tuple{f, tt.parameters...}` with pipeline parametrized by `ctx::CompilationContext`.

Returns a callable instance of `Entry{F, RT, TT}` where `RT` is the return type of the instance after inference.

The user can configure the pipeline with optional arguments:

- `ctx::CompilationContext` -- configure [`transform`](@ref) and [`optimize!`](@ref).
- `opt::Bool` -- configure whether or not the Julia optimizer is run (including [`optimize!`](@ref)).
- `optlevel::Int > 0` -- configure the LLVM optimization level.
""", jit)

function _jitlink(job::CompilerJob, (rt, llvm_mod, func_name, specfunc_name))
    fspec = job.source
    tm = llvm_machine(job.target, job.params)
    orc = LLVM.OrcJIT(tm)
    atexit() do
        return LLVM.dispose(orc)
    end
    optimize!(tm, llvm_mod)
    jitted_mod = compile!(orc, llvm_mod)
    specfunc_addr = addressin(orc, jitted_mod, specfunc_name)
    specfunc_ptr = pointer(specfunc_addr)
    func_addr = addressin(orc, jitted_mod, func_name)
    func_ptr = pointer(func_addr)
    @assert(!(specfunc_ptr === C_NULL || func_ptr === C_NULL))
    return Entry{typeof(fspec.f), rt, fspec.tt}(fspec.f, specfunc_ptr, func_ptr)
end

function _jit(job::CompilerJob)
    rt, llvm_specfunc, llvm_func, llvm_mod = codegen(job)
    specfunc_name = LLVM.name(llvm_specfunc)
    func_name = LLVM.name(llvm_func)
    linkage!(llvm_func, LLVM.API.LLVMExternalLinkage)
    linkage!(llvm_specfunc, LLVM.API.LLVMExternalLinkage)
    return (rt, llvm_mod, func_name, specfunc_name)
end

#####
##### Emission and call interface
#####

function _emit(job::CompilerJob)
    f = job.source.f
    tt = job.source.tt
    opt = job.params.opt
    si, ssg = analyze(f, tt;
                      ctx = job.params.ctx, opt = opt) # Populate local cache.
    return get_codeinfo(ssg, entrypoint(ssg))
end

identity(job::CompilerJob, src) = src

const emit_compiled_cache = Dict{UInt, Any}()

function emit(@nospecialize(f), tt::Type{T};
        ctx = NoContext(), opt = false) where {F <: Function, T <: Tuple}
    fspec = FunctionSpec(f, tt, false, nothing) #=name=#
    optlevel = Base.JLOptions().opt_level
    job = CompilerJob(MixtapeCompilerTarget(),
                      fspec,
                      MixtapeCompilerParams(;
                                            ctx = ctx,
                                            opt = opt,
                                            optlevel = optlevel))
    return cached_compilation(emit_compiled_cache, job, _emit, identity)
end

@doc(
"""
    emit(@nospecialize(f), tt::Type{T};
        ctx = NoContext(), opt = false) where {F <: Function, T <: Tuple}

Emit typed (and optimized if `opt = true`) `CodeInfo` using the Mixtape pipeline. The user can configure the pipeline with optional arguments:

- `ctx::CompilationContext` -- configure [`transform`](@ref) and [`optimize!`](@ref).
- `opt::Bool` -- configure whether or not the Julia optimizer is run (including [`optimize!`](@ref)).
""", emit)

macro load_abi()
    expr = quote
        function cached_call(entry::Mixtape.Entry{F, RT, TT},
                args...) where {F, RT, TT}

            # TODO: Fast ABI.
            #ccall(entry.func, Any, (Any, $(nargs...), ), entry.f, $(_args...))

            # Slow ABI. Requires an array allocation.
            expr = quote
                vargs = Any[args...]
                ccall($(entry.func), Any, (Any, Ptr{Any}, Int32), $(entry.f), vargs,
                      $(length(args)))
            end
            return expr
        end

        @generated function _call(ctx::CompilationContext,
                optlevel::Val{T}, f::Function, args...) where T
            TT = Tuple{args...}
            entry = jit(f.instance, TT;
                        ctx = ctx(), opt = true, optlevel = T)
            return cached_call(entry, args...)
        end

        function call(f::T, args...;
                ctx = NoContext(),
                optlevel = Base.JLOptions().opt_level) where T <: Function
            _call(ctx, Val(optlevel), f, args...)
        end
    end
    return esc(expr)
end

@doc(
"""
    @load_abi()
    ...expands...
    call(f::T, args...; ctx = NoContext(),
        optlevel = Base.JLOptions().opt_level) where T <: Function


A macro which expands to define an ABI function `call` into the scope of the calling module. `call` wraps an `@generated` function which is called with signature argument types `Tuple{f <: Function, args...}`. The underlying `@generated` function creates a new instance of `ctx` (thus, a nullary constructor is an implicit requirement of your own subtypes of [`CompilationContext`](@ref) for usage with `call`) and calls [`jit`](@ref) -- it then caches a `ccall` which calls a function pointer to the [GPUCompiler](https://github.com/JuliaGPU/GPUCompiler.jl)-compiled LLVM module.

The `call` interface currently uses a slow ABI `ccall` -- which costs an array allocation for each toplevel `call`. This allocation is required to construct a `Vector{Any}` for the arguments and pass a pointer to it over the line, where the call unboxes each argument.
""", :(@Mixtape.load_abi))

end # module
