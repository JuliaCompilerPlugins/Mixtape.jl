function overlay_infer(interp, tt)::MethodInstance

    # Check overlay table.
    if haskey(interp.mtable, tt)
        mi = interp.mtable[tt]

    else
        # Find all methods that are applicable to these types
        mthds = _methods_by_ftype(tt, -1, typemax(UInt))
        if mthds === false || length(mthds) != 1
            error("Unable to find single applicable method for $tt")
        end

        mtypes, msp, m = mthds[1]

        # Grab the appropriate method instance for these types
        mi = Core.Compiler.specialize_method(m, mtypes, msp)
    end

    # Construct InferenceResult to hold the result,
    result = Core.Compiler.InferenceResult(mi)

    # Create an InferenceState to begin inference, give it a world that is always newest
    world = Core.Compiler.get_world_counter()
    frame = Core.Compiler.InferenceState(result, #=cached=# true, interp)

    # Run type inference on this frame.  Because the interpreter is embedded
    # within this InferenceResult, we don't need to pass the interpreter in.
    Core.Compiler.typeinf(interp, frame)

    # Give the result back
    return (mi, result)
end

abstract type MixingTable end

macro mixer(expr)
    quote
        struct $expr <: MixingTable end
    end
end

struct MixtapeInterpreter <: Core.Compiler.AbstractInterpreter
    mtable::MixingTable
    code::Dict{MethodInstance, CodeInstance}
    native_interpreter::NativeInterpreter
    msgs::Vector{Tuple{MethodInstance, Int, String}}
end

MixtapeInterpreter(mtable::MixingTable) = MixtapeInterpreter(mtable, Dict{MethodInstance, Any}(), NativeInterpreter(), Vector{Tuple{MethodInstance, Int, String}}())

InferenceParams(mxi::MixtapeInterpreter) = InferenceParams(mxi.native_interpreter)
OptimizationParams(mxi::MixtapeInterpreter) = OptimizationParams(mxi.native_interpreter)
get_world_counter(mxi::MixtapeInterpreter) = get_world_counter(mxi.native_interpreter)
get_inference_cache(mxi::MixtapeInterpreter) = get_inference_cache(mxi.native_interpreter)

# No need to do any locking since we're not putting our results into the runtime cache
lock_mi_inference(mxi::MixtapeInterpreter, mi::MethodInstance) = nothing
unlock_mi_inference(mxi::MixtapeInterpreter, mi::MethodInstance) = nothing

code_cache(mxi::MixtapeInterpreter) = mxi.code

Core.Compiler.get(a::Dict, b, c) = Base.get(a,b,c)
Core.Compiler.get(a::WorldView{<:Dict}, b, c) = Base.get(a.cache,b,c)
Core.Compiler.haskey(a::Dict, b) = Base.haskey(a, b)
Core.Compiler.haskey(a::WorldView{<:Dict}, b) =
Core.Compiler.haskey(a.cache, b)
Core.Compiler.setindex!(a::Dict, b, c) = setindex!(a, b, c)
Core.Compiler.get_world_counter(ni::MixtapeInterpreter) = ni.world
Core.Compiler.get_inference_cache(ni::MixtapeInterpreter) = ni.cache
Core.Compiler.InferenceParams(ni::MixtapeInterpreter) = ni.inf_params
Core.Compiler.OptimizationParams(ni::MixtapeInterpreter) = ni.opt_params

function mix(mixer::MixingTable, fn::Function, args...)
    tt = typeof((fn, args...))
    mxi = MixTapeInterpreter(mixer)
    mi, result = overlay_infer(mxi, tt)
    mi
end
