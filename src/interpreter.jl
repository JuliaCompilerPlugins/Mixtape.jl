#####
##### Interpreter
#####

struct MixtapeInterpreter{Intrinsic, Inner<:AbstractInterpreter} <: AbstractInterpreter
    inner::Inner
    MixtapeInterpreter{Intrinsic}(interp::Inner) where {Intrinsic, Inner} = new{Intrinsic, Inner}(interp)
end

get_world_counter(mxi::MixtapeInterpreter) =  get_world_counter(mxi.inner)
get_inference_cache(mxi::MixtapeInterpreter) = get_inference_cache(mxi.inner) 
InferenceParams(mxi::MixtapeInterpreter) = InferenceParams(mxi.inner)
OptimizationParams(mxi::MixtapeInterpreter) = OptimizationParams(mxi.inner)
Core.Compiler.may_optimize(ni::MixtapeInterpreter) = true
Core.Compiler.may_compress(ni::MixtapeInterpreter) = true
Core.Compiler.may_discard_trees(ni::MixtapeInterpreter) = true
Core.Compiler.add_remark!(ni::MixtapeInterpreter, sv::InferenceState, msg) = Core.Compiler.add_remark!(ni.inner, sv, msg)
lock_mi_inference(mxi::MixtapeInterpreter, mi::MethodInstance) = nothing
unlock_mi_inference(mxi::MixtapeInterpreter, mi::MethodInstance) = nothing

#####
##### Codegen/interence integration
#####

code_cache(mxi::MixtapeInterpreter) = WorldView(get_cache(typeof(mxi.inner)), get_world_counter(mxi))

function cpu_invalidate(replaced, max_world)
    cache = get_cache(NativeInterpreter)
    invalidate(cache, replaced, max_world, 0)
    return nothing
end

function cpu_cache_lookup(mi, min_world, max_world)
    wvc = WorldView(get_cache(NativeInterpreter), min_world, max_world)
    return Core.Compiler.get(wvc, mi, nothing)
end

function cpu_infer(mi, min_world, max_world)
    intrinsic = static_eval(getfield(mi.def, :module), mi.def.name)
    wvc = WorldView(get_cache(NativeInterpreter), min_world, max_world)
    interp = MixtapeInterpreter{intrinsic}(NativeInterpreter(min_world))
    return infer(wvc, mi, interp)
end

function infer(wvc, mi, interp)
    src = Core.Compiler.typeinf_ext_toplevel(interp, mi)
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

# Replace usage sited of `retrieve_code_info`, OptimizationState is one such, but in all interesting use-cases
# it is derived from an InferenceState. There is a third one in `typeinf_ext` in case the module forbids inference.
function InferenceState(result::InferenceResult, cached::Bool, interp::MixtapeInterpreter)
    src = retrieve_code_info(result.linfo)
    src === nothing && return nothing
    validate_code_in_debug_mode(result.linfo, src, "lowered")
    src = cassette_transform(interp, result.linfo, src)
    validate_code_in_debug_mode(result.linfo, src, "transformed")
    return InferenceState(result, src, cached, interp)
end
