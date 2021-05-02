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
    ccall(:jl_typeinf_begin, Cvoid, ())
    result = Core.Compiler.InferenceResult(mi)
    world = Core.Compiler.get_world_counter()
    frame = Core.Compiler.InferenceState(result, true, interp)
    frame === nothing && return nothing
    if Core.Compiler.typeinf(interp, frame)
        opt_params = Core.Compiler.OptimizationParams(interp)
        opt = Core.Compiler.OptimizationState(frame, opt_params, interp)
        Core.Compiler.optimize(interp, opt, opt_params, result)
    end
    ccall(:jl_typeinf_end, Cvoid, ())
    return mi
end

#####
##### Static interpreter
#####

# Based on: https://github.com/Keno/Compiler3.jl/blob/master/exploration/static.jl

# Holds its own cache.
struct MixtapeInterpreter{I, C} <: AbstractInterpreter
    code::Dict{MethodInstance, CodeInstance}
    inner::I
    messages::Vector{Tuple{MethodInstance, Int, String}}
    optimize::Bool
    ctx::C
    errors::Vector
end

function MixtapeInterpreter(; opt = false)
    return MixtapeInterpreter(Dict{MethodInstance, CodeInstance}(),
                              NativeInterpreter(), 
                              Tuple{MethodInstance, Int, String}[],
                              opt,
                              NoContext(),
                              Any[])
end

Base.push!(mxi::MixtapeInterpreter, e) = push!(mxi.errors, e)
InferenceParams(si::MixtapeInterpreter) = InferenceParams(si.inner)
OptimizationParams(si::MixtapeInterpreter) = OptimizationParams(si.inner)
get_world_counter(si::MixtapeInterpreter) = get_world_counter(si.inner)
get_inference_cache(si::MixtapeInterpreter) = get_inference_cache(si.inner)
lock_mi_inference(si::MixtapeInterpreter, mi::MethodInstance) = nothing
unlock_mi_inference(si::MixtapeInterpreter, mi::MethodInstance) = nothing
code_cache(si::MixtapeInterpreter) = si.code
Core.Compiler.get(a::Dict, b, c) = Base.get(a,b,c)
Core.Compiler.get(a::WorldView{<:Dict}, b, c) = Base.get(a.cache,b,c)
Core.Compiler.haskey(a::Dict, b) = Base.haskey(a, b)
Core.Compiler.haskey(a::WorldView{<:Dict}, b) =
Core.Compiler.haskey(a.cache, b)
Core.Compiler.setindex!(a::Dict, b, c) = setindex!(a, b, c)
Core.Compiler.may_optimize(si::MixtapeInterpreter) = si.optimize
Core.Compiler.may_compress(si::MixtapeInterpreter) = false
Core.Compiler.may_discard_trees(si::MixtapeInterpreter) = false
function Core.Compiler.add_remark!(si::MixtapeInterpreter, sv::InferenceState, msg)
    push!(si.messages, (sv.linfo, sv.currpc, msg))
end

#####
##### Pre-inference
#####

function _debug_prehook(interp::MixtapeInterpreter, result, mi, src)
    meth = mi.def
    try
        fn = resolve(GlobalRef(meth.module, meth.name))
        as = map(resolve, result.argtypes[2:end])
        if debug(interp.ctx)
            print("@ ($(meth.file), L$(meth.line))\n")
            print("| beg (inf): $(meth.module).$(fn)\n")
        end
    catch e
        push!(interp, e)
    end
end

function custom_pass!(interp::MixtapeInterpreter, result::InferenceResult, mi::Core.MethodInstance, src)
    src === nothing && return src
    mi.specTypes isa UnionAll && return src
    sig = Tuple(mi.specTypes.parameters)
    if sig[1] <: Function && isdefined(sig[1], :instance)
        fn = sig[1].instance
    else
        fn = sig[1]
    end
    as = map(resolve, sig[2 : end])
    debug(interp.ctx) && _debug_prehook(interp, result, mi, src)
    if allow(interp.ctx, mi.def.module, fn, as...)
        new :: CodeInfo = transform(interp.ctx, src, sig)
        b = CodeInfoTools.Builder(new)
        new = CodeInfoTools.finish(b)
        e = detect_invoke(CodeInfoTools.Builder(new), result.linfo)
        if e != nothing
            push!(interp, e)
        end
        src = new
    end
    return src
end

function InferenceState(result::InferenceResult, cached::Bool, interp::MixtapeInterpreter)
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

function julia_passes(ir::Core.Compiler.IRCode, ci::CodeInfo, sv::OptimizationState)
    ir = compact!(ir)
    ir = ssa_inlining_pass!(ir, ir.linetable, sv.inlining, ci.propagate_inbounds)
    ir = compact!(ir)
    ir = getfield_elim_pass!(ir) # SROA
    ir = adce_pass!(ir)
    ir = type_lift_pass!(ir)
    ir = compact!(ir)
    return ir
end

@static if VERSION >= v"1.7.0-DEV.662"
    using Core.Compiler: finish as _finish
else
    function _finish(interp::AbstractInterpreter, opt::OptimizationState,
            params::OptimizationParams, ir, @nospecialize(result))
        return Core.Compiler.finish(opt, params, ir, result)
    end
end

function _debug_prehook(interp::MixtapeInterpreter, mi, opt)
    meth = mi.def
    try
        fn = resolve(GlobalRef(mi.def.module, mi.def.name))
        as = map(resolve, mi.specTypes.parameters[2:end])
        if allow(interp.ctx, mi.def.module, fn, as...) && show_after_inference(interp.ctx)
            print("@ ($(meth.file), L$(meth.line))\n")
            print("| (inf) $(mi.def.module).$fn\n")
            println(opt.src)
        end
        if debug(interp.ctx)
            println("@ ($(meth.file), L$(meth.line))")
            println("| end (inf): $(meth.module).$(fn)")
            println("@ ($(meth.file), L$(meth.line))")
            println("| beg (opt): $(meth.module).$(fn)")
        end
    catch e
        push!(interp, e)
    end
end

function _debug_posthook(interp::MixtapeInterpreter, mi, opt; stage = "opt")
    meth = mi.def
    try 
        fn = resolve(GlobalRef(mi.def.module, mi.def.name))
        as = map(resolve, mi.specTypes.parameters[2:end])
        if allow(interp.ctx, mi.def.module, fn, as...) &&
            show_after_optimization(interp.ctx)
            print("@ ($(meth.file), L$(meth.line))\n")
            print("| (opt) $(opt.linfo.def.module).$fn\n")
            println(opt.src)
        end
        if debug(interp.ctx)
            println("@ ($(meth.file), L$(meth.line))")
            println("| end (opt): $(meth.module).$(fn)")
        end
    catch e
        push!(interp, e)
    end
end

function before_pass!(interp::MixtapeInterpreter, mi::Core.MethodInstance, ir::Core.Compiler.IRCode, opt::OptimizationState)
    mi.specTypes isa UnionAll && return ir
    sig = Tuple(mi.specTypes.parameters)
    if sig[1] <: Function && isdefined(sig[1], :instance)
        fn = sig[1].instance
    else
        fn = sig[1]
    end
    as = map(resolve, sig[2 : end])
    debug(interp.ctx) && _debug_prehook(interp, mi, opt)
    if allow(interp.ctx, mi.def.module, fn, as...)
        ir = preopt!(interp.ctx, ir)
    end
    return ir
end

function after_pass!(interp::MixtapeInterpreter, mi::Core.MethodInstance, ir::Core.Compiler.IRCode, opt::OptimizationState)
    mi.specTypes isa UnionAll && return ir
    sig = Tuple(mi.specTypes.parameters)
    if sig[1] <: Function && isdefined(sig[1], :instance)
        fn = sig[1].instance
    else
        fn = sig[1]
    end
    as = map(resolve, sig[2 : end])
    if allow(interp.ctx, mi.def.module, fn, as...)
        ir = postopt!(interp.ctx, ir)
    end
    return ir
end

function optimize(interp::MixtapeInterpreter, opt::OptimizationState,
        params::OptimizationParams, @nospecialize(result))
    nargs = Int(opt.nargs) - 1
    mi = opt.linfo
    meth = mi.def
    preserve_coverage = coverage_enabled(opt.mod)
    ir = convert_to_ircode(opt.src, copy_exprargs(opt.src.code), preserve_coverage, nargs, opt)
    ir = slot2reg(ir, opt.src, nargs, opt)
    ir = before_pass!(interp, mi, ir, opt)
    ir = julia_passes(ir, opt.src, opt)
    ir = after_pass!(interp, mi, ir, opt)
    ir = julia_passes(ir, opt.src, opt)
    debug(interp.ctx) && _debug_posthook(interp, mi, opt)
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

cursor_mi(mi::MethodInstance) = mi

has_codeinfo(ssg::StaticSubGraph, mi::MethodInstance) = haskey(ssg.code, mi)

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

function analyze(@nospecialize(f), tt::Type{T}; opt = false) where T <: Tuple
    si = MixtapeInterpreter(; opt = opt)
    mi = infer(si, f, tt)
    si, StaticSubGraph(si.code, collect(keys(si.code)), mi)
end

# Similar to Yao.
function gather_children(si, ssg, mi)
    # Run inlining to convert calls to invoke.
    haskey(ssg.code, mi) || return Any[] # TODO: When does this happen?
    ci = get_codeinfo(ssg, mi)
    params = OptimizationParams()
    sv = OptimizationState(ssg.entry, params, si)
    sv.slottypes .= ci.slottypes
    nargs = Int(sv.nargs) - 1
    ir = Core.Compiler.run_passes(ci, nargs, sv)
    ret = Any[]
    for stmt in ir.stmts
        Core.Compiler.isexpr(stmt, :invoke) || continue
        push!(ret, stmt.args[1])
    end
    unique(ret)
end

function filter_messages(si::MixtapeInterpreter, mi::MethodInstance)
    filter(x->x[1] == mi, si.messages)
end

function analyze_static(@nospecialize(f), tt::Type{T}) where T <: Tuple
    si = MixtapeInterpreter()
    mi = infer(si, f, tt)
    ssg = StaticSubGraph(si.code, collect(keys(si.code)), mi)
    worklist = Any[(ssg.entry, [])]
    visited = Set{Any}(worklist)
    while !isempty(worklist)
        mi, stack = popfirst!(worklist)
        global cur_mi
        cur_mi = mi
        for msg in filter_messages(si, mi)
            print("In function: ")
            Base.show_tuple_as_call(stdout, mi.def.name, mi.specTypes)
            println()
            printstyled("ERROR: ", color=:red)
            println(msg[3]);
            ci = get_codeinfo(ssg, mi)
            loc = ci.linetable[ci.codelocs[msg[2]]]
            fname = String(loc.file)
            if startswith(fname, "REPL[")
                hp = Base.active_repl.interface.modes[1].hist
                repl_id = parse(Int, fname[6:end-1])
                repl_contents = hp.history[repl_id+hp.start_idx]
                for (n, line) in enumerate(split(repl_contents, '\n'))
                    print(n == loc.line ? "=> " : "$n| ")
                    println(line)
                end
            else
                println("TODO: File content here")
            end
            println()
            for (i, old_mi) in enumerate(reverse(stack))
                print("[$i] In ")
                Base.show_tuple_as_call(stdout, old_mi.def.name, old_mi.specTypes)
                println()
            end
            println()
        end
        children = gather_children(si, ssg, mi)
        for child in children
            if !(child in visited)
                push!(worklist, (child, [copy(stack); mi]))
            end
            push!(visited, mi)
        end
    end
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
##### Cached compilation
#####

# Interpreter holds the cache.
function cache_lookup(si::MixtapeInterpreter, mi::MethodInstance,
        min_world, max_world)
    return getindex(si.code, mi)
end

# Mostly from GPUCompiler. 
# In future, try to upstream any requires changes.
function codegen(job::CompilerJob)
    f = job.source.f
    tt = job.source.tt
    opt = job.params.opt
    analyze_static(f, tt)
    si, ssg = analyze(f, tt; opt = opt) # Populate local cache.
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

struct StaticCompilerTarget <: AbstractCompilerTarget end

llvm_triple(::StaticCompilerTarget) = Sys.MACHINE

function llvm_machine(::StaticCompilerTarget)
    opt_level = Base.JLOptions().opt_level
    if opt_level < 2
        optlevel = LLVM.API.LLVMCodeGenLevelNone
    elseif opt_level == 2
        optlevel = LLVM.API.LLVMCodeGenLevelDefault
    else
        optlevel = LLVM.API.LLVMCodeGenLevelAggressive
    end
    tm = LLVM.JITTargetMachine(; optlevel=optlevel)
    LLVM.asm_verbosity!(tm, true)
    return tm
end

struct StaticCompilerParams <: AbstractCompilerParams
    opt::Bool
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

function jit(@nospecialize(f), tt::Type{T}; opt = false) where T <: Tuple
    fspec = FunctionSpec(f, tt, false, nothing) #=name=#
    job = CompilerJob(StaticCompilerTarget(), 
                      fspec, 
                      StaticCompilerParams(opt))
    return cached_compilation(jit_compiled_cache, job, _jit, _jitlink)
end

function _jitlink(job::CompilerJob, (rt, llvm_mod, func_name, specfunc_name))
    fspec = job.source
    tm = llvm_machine(job.target)
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
    if specfunc_ptr === C_NULL || func_ptr === C_NULL
        @error "Compilation error" fspec specfunc_ptr func_ptr
    end
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

end # module
