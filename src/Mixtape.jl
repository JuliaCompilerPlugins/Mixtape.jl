module Mixtape

# Status: codegen to local OrcJIT instance not quite working yet.
# Also, codegen caches to the runtime cache (not our managed cache).
# So it "sort of works" but not in the right way.
# Also, nested calls aren't quite there - the wrapping works, but it doesn't do overlay like we expect.

using Core: CodeInfo, Const
using Core.Compiler
using Core.Compiler: CodeInstance, MethodInstance
using Core.Compiler: NativeInterpreter, AbstractInterpreter
using Core.Compiler: InferenceState, UseRef, UseRefIterator, OptimizationState, OptimizationParams, InferenceParams, MethodResultPure, CallMeta, WorldView, InstructionStream
using Core.Compiler: get_world_counter, widenconst, get_inference_cache, compact!

using Base.Meta: ParseError
using MacroTools
using ExprTools
using LLVM
using LLVM.Interop

#####
##### Execution engine pre-setup
#####

# We have one global JIT and TM
const orc = Ref{LLVM.OrcJIT}()
const tm  = Ref{LLVM.TargetMachine}()

function __init__()
    CACHE[NativeInterpreter] = CodeCache(cpu_invalidate)

    opt_level = Base.JLOptions().opt_level
    if opt_level < 2
        optlevel = LLVM.API.LLVMCodeGenLevelNone
    elseif opt_level == 2
        optlevel = LLVM.API.LLVMCodeGenLevelDefault
    else
        optlevel = LLVM.API.LLVMCodeGenLevelAggressive
    end

    tm[] = LLVM.JITTargetMachine(optlevel=optlevel)
    LLVM.asm_verbosity!(tm[], true)

    orc[] = LLVM.OrcJIT(tm[]) # takes ownership of tm
    atexit() do
        LLVM.dispose(orc[])
    end
end

#####
##### Cache
#####

struct CodeCache
    dict::Dict{MethodInstance,Vector{CodeInstance}}
    callback::Function
    CodeCache(callback) = new(Dict{MethodInstance,Vector{CodeInstance}}(), callback)
end

function Base.show(io::IO, ::MIME"text/plain", cc::CodeCache)
    print(io, "CodeCache: ")
    for (mi, cis) in cc.dict
        println(io)
        print(io, "- ")
        show(io, mi)

        for ci in cis
            println(io)
            print(io, "  - ")
            print(io, (ci.min_world, ci.max_world))
        end
    end
end

function Core.Compiler.setindex!(cache::CodeCache, ci::CodeInstance, mi::MethodInstance)
    if !isdefined(mi, :callbacks)
        mi.callbacks = Any[cache.callback]
    else
        # Check if callback is present
        if all(cb -> cb !== cache.callback, mi.callbacks)
            push!(mi.callbacks, cache.callback)
        end
    end

    cis = get!(cache.dict, mi, CodeInstance[])
    push!(cis, ci)
end

#####
##### Cache world view
#####

function Core.Compiler.haskey(wvc::WorldView{CodeCache}, mi::MethodInstance)
    Core.Compiler.get(wvc, mi, nothing) !== nothing
end

function Core.Compiler.get(wvc::WorldView{CodeCache}, mi::MethodInstance, default)
    cache = wvc.cache
    for ci in get!(cache.dict, mi, CodeInstance[])
        if ci.min_world <= wvc.worlds.min_world && wvc.worlds.max_world <= ci.max_world
            # TODO: if (code && (code == jl_nothing || jl_ir_flag_inferred((jl_array_t*)code)))
            return ci
        end
    end

    return default
end

function Core.Compiler.getindex(wvc::WorldView{CodeCache}, mi::MethodInstance)
    r = Core.Compiler.get(wvc, mi, nothing)
    r === nothing && throw(KeyError(mi))
    return r::CodeInstance
end

Core.Compiler.setindex!(wvc::WorldView{CodeCache}, ci::CodeInstance, mi::MethodInstance) = Core.Compiler.setindex!(wvc.cache, ci, mi)

#####
##### Cache invalidation
#####

function invalidate(cache::CodeCache, replaced::MethodInstance, max_world, depth)
    cis = get(cache.dict, replaced, nothing)
    if cis === nothing
        return
    end
    for ci in cis
        if ci.max_world == ~0 % Csize_t
            @assert ci.min_world - 1 <= max_world "attempting to set illogical constraints"
            ci.max_world = max_world
        end
        @assert ci.max_world <= max_world
    end

    # recurse to all backedges to update their valid range also
    if isdefined(replaced, :backedges)
        backedges = replaced.backedges
        # Don't touch/empty backedges `invalidate_method_instance` in C will do that later
        # replaced.backedges = Any[]

        for mi in backedges
            invalidate(cache, mi, max_world, depth + 1)
        end
    end
end

#####
##### Global cache
#####

const CACHE = Dict{DataType, CodeCache}()
get_cache(ai::DataType) = CACHE[ai]

#####
##### Interpreter
#####

struct MixtapeInterpreter{Ctx} <: AbstractInterpreter
    native_interpreter::Core.Compiler.NativeInterpreter
    MixtapeInterpreter{Ctx}() where Ctx = new{Ctx}(Core.Compiler.NativeInterpreter())
    MixtapeInterpreter{Ctx}(interp) where Ctx = new{Ctx}(interp)
end

InferenceParams(interp::MixtapeInterpreter) = InferenceParams(interp.native_interpreter)
OptimizationParams(interp::MixtapeInterpreter) = OptimizationParams(interp.native_interpreter)
Core.Compiler.get_world_counter(interp::MixtapeInterpreter) = get_world_counter(interp.native_interpreter)
Core.Compiler.get_inference_cache(interp::MixtapeInterpreter) = get_inference_cache(interp.native_interpreter)
Core.Compiler.may_optimize(interp::MixtapeInterpreter) = Core.Compiler.may_optimize(interp.native_interpreter)
Core.Compiler.may_discard_trees(interp::MixtapeInterpreter) = Core.Compiler.may_discard_trees(interp.native_interpreter)
Core.Compiler.may_compress(interp::MixtapeInterpreter) = Core.Compiler.may_compress(interp.native_interpreter)
Core.Compiler.unlock_mi_inference(interp::MixtapeInterpreter, mi::Core.MethodInstance) = nothing
Core.Compiler.lock_mi_inference(interp::MixtapeInterpreter, mi::Core.MethodInstance) = nothing
Core.Compiler.add_remark!(ni::MixtapeInterpreter, sv::InferenceState, msg) = Core.Compiler.add_remark!(ni.native_interpreter, sv, msg)

Core.Compiler.code_cache(interp::MixtapeInterpreter) = WorldView(get_cache(typeof(interp.native_interpreter)), get_world_counter(interp))

function cpu_invalidate(replaced, max_world)
    cache = get_cache(NativeInterpreter)
    invalidate(cache, replaced, max_world, 0)
    return nothing
end

function cpu_cache_lookup(mi, min_world, max_world)
    wvc = WorldView(get_cache(NativeInterpreter), min_world, max_world)
    return Core.Compiler.get(wvc, mi, nothing)
end

function cpu_infer(mi, min_world, max_world, ctx)
    wvc = WorldView(get_cache(NativeInterpreter), min_world, max_world)
    interp = MixtapeInterpreter{typeof(ctx)}(NativeInterpreter(min_world))
    return infer(wvc, mi, interp)
end

function method_overlay!(interp::MixtapeInterpreter{C}, mi::MethodInstance) where C
    ci = Core.Compiler.retrieve_code_info(mi)
    new_inst = []
    for e in ci.code
        e isa Expr || continue
        if e.head == :call
            push!(new_inst, Expr(:call, overdub, C(), e.args...))
        else
            push!(new_inst, e)
        end
    end
    copyto!(ci.code, new_inst)
    mi.def.source = ci
end

function infer(wvc, mi, interp)
    method_overlay!(interp, mi) # pre-inference: wrap calls.
    src = Core.Compiler.typeinf_ext_toplevel(interp, mi) # hooks into inference with out interpreter.
    
    # inference populates the cache, so we don't need to jl_get_method_inferred
    @assert Core.Compiler.haskey(wvc, mi)

    # if src is rettyp_const, the codeinfo won't cache ci.inferred
    # (because it is normally not supposed to be used ever again).
    # to avoid the need to re-infer, set that field here.
    # This is required for being able to use `cache_lookup` as the lookup
    # function for `CodegenParams` and `jl_create_native`.
    ci = Core.Compiler.getindex(wvc, mi)
    if ci !== nothing && ci.inferred === nothing
        ci.inferred = src
    end
    return
end

#####
##### Optimizer
#####

# Forwarding...
Base.iterate(ic::Core.Compiler.IncrementalCompact) = Core.Compiler.iterate(ic)
Base.iterate(ic::Core.Compiler.IncrementalCompact, st) = Core.Compiler.iterate(ic, st)
Base.getindex(ic::Core.Compiler.IncrementalCompact, idx) = Core.Compiler.getindex(ic, idx)
Base.setindex!(ic::Core.Compiler.IncrementalCompact, v, idx) = Core.Compiler.setindex!(ic, v, idx)

Base.getindex(ic::Core.Compiler.Instruction, idx) = Core.Compiler.getindex(ic, idx)
Base.setindex!(ic::Core.Compiler.Instruction, v, idx) = Core.Compiler.setindex!(ic, v, idx)

Base.getindex(ir::Core.Compiler.IRCode, idx) = Core.Compiler.getindex(ir, idx)
Base.setindex!(ir::Core.Compiler.IRCode, v, idx) = Core.Compiler.setindex!(ir, v, idx)

Base.getindex(ref::UseRef) = Core.Compiler.getindex(ref)
Base.iterate(uses::UseRefIterator) = Core.Compiler.iterate(uses)
Base.iterate(uses::UseRefIterator, st) = Core.Compiler.iterate(uses, st)

Base.iterate(p::Core.Compiler.Pair) = Core.Compiler.iterate(p)
Base.iterate(p::Core.Compiler.Pair, st) = Core.Compiler.iterate(p, st)

Base.getindex(m::Core.Compiler.MethodLookupResult, idx::Int) = Core.Compiler.getindex(m, idx)

#####
##### optimize
#####

# This is basically standard - just run normal passes.
function Core.Compiler.optimize(interp::MixtapeInterpreter,
        opt::OptimizationState, 
        params::OptimizationParams, 
        @nospecialize(result))
    nargs = Int(opt.nargs) - 1
    ir = Core.Compiler.run_passes(opt.src, nargs, opt)
    ir = compact!(ir)
    new = Core.Compiler.finish(opt, params, ir, result)
end

#####
##### Compile for CPU through LLVM
#####

function cpu_compile(method_instance::Core.MethodInstance, world, ctx; debug = false)
    params = Base.CodegenParams(;
        track_allocations  = false,
        code_coverage      = false,
        prefer_specsig     = true,
        lookup             = @cfunction(cpu_cache_lookup, Any, (Any, UInt, UInt)))

    # generate IR
    # TODO: Instead of extern policy integrate with Orc JIT

    # populate the cache
    if cpu_cache_lookup(method_instance, world, world) === nothing
        cpu_infer(method_instance, world, world, ctx)
    end

    native_code = ccall(:jl_create_native, Ptr{Cvoid},
        (Vector{Core.MethodInstance}, Base.CodegenParams, Cint),
        [method_instance], params, #=extern policy=# 1)
    @assert native_code != C_NULL
    llvm_mod_ref = ccall(:jl_get_llvm_module, LLVM.API.LLVMModuleRef,
        (Ptr{Cvoid},), native_code)
    @assert llvm_mod_ref != C_NULL
    llvm_mod = LLVM.Module(llvm_mod_ref)

    # get the top-level code
    code = cpu_cache_lookup(method_instance, world, world)

    # get the top-level function index
    llvm_func_idx = Ref{Int32}(-1)
    llvm_specfunc_idx = Ref{Int32}(-1)
    ccall(:jl_get_function_id, Nothing,
        (Ptr{Cvoid}, Any, Ptr{Int32}, Ptr{Int32}),
        native_code, code, llvm_func_idx, llvm_specfunc_idx)
    @assert llvm_func_idx[] != -1
    @assert llvm_specfunc_idx[] != -1

    # get the top-level function)
    llvm_func_ref = ccall(:jl_get_llvm_function, LLVM.API.LLVMValueRef,
        (Ptr{Cvoid}, UInt32), native_code, llvm_func_idx[]-1)
    @assert llvm_func_ref != C_NULL
    llvm_func = LLVM.Function(llvm_func_ref)
    llvm_specfunc_ref = ccall(:jl_get_llvm_function, LLVM.API.LLVMValueRef,
        (Ptr{Cvoid}, UInt32), native_code, llvm_specfunc_idx[]-1)
    @assert llvm_specfunc_ref != C_NULL
    llvm_specfunc = LLVM.Function(llvm_specfunc_ref)
    wvc = WorldView(get_cache(NativeInterpreter), world, world)
    ci = Core.Compiler.getindex(wvc, method_instance)
    return llvm_specfunc, llvm_func, llvm_mod
end

function method_instance(@nospecialize(f), @nospecialize(tt), world)
    meth = which(f, tt)
    sig = Base.signature_type(f, tt)::Type
    (ti, env) = ccall(:jl_type_intersection_with_env, Any,
        (Any, Any), sig, meth.sig)::Core.SimpleVector
    meth = Base.func_for_method_checked(meth, ti, env)
    return ccall(:jl_specializations_get_linfo, Ref{Core.MethodInstance},
        (Any, Any, Any, UInt), meth, ti, env, world)
end

function codegen(@nospecialize(f), @nospecialize(tt), ctx, world = Base.get_world_counter())
    cpu_compile(method_instance(f, tt, world), world, ctx)
end

#####
##### overdub
#####

abstract type Context end
struct Fallback <: Context end
function overdub(ctx::Context, fn, args...)
    codegen(fn, Base.typesof(args...), ctx)
end

export Context
export overdub

end # module
