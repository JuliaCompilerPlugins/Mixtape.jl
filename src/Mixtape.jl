module Mixtape

using Core.Compiler
import Core.Compiler: InferenceParams, OptimizationParams, get_world_counter, get_inference_cache

"""
@infer_function interp foo(1, 2) [show_steps=true] [show_ir=false]

Infer a function call using the given interpreter object, return
the inference object.  Set keyword arguments to modify verbosity:

* Set `show_steps` to `true` to see the `InferenceResult` step by step.
* Set `show_ir` to `true` to see the final type-inferred Julia IR.
"""
macro infer_function(interp, func_call, kwarg_exs...)
    if !isa(func_call, Expr) || func_call.head != :call
        error("@infer_function requires a function call")
    end

    local func = func_call.args[1]
    local args = func_call.args[2:end]
    kwargs = []
    for ex in kwarg_exs
        if ex isa Expr && ex.head === :(=) && ex.args[1] isa Symbol
            push!(kwargs, first(ex.args) => last(ex.args))
        else
            error("Invalid @infer_function kwarg $(ex)")
        end
    end
    return quote
        infer_function($(esc(interp)), $(esc(func)), typeof.(($(args)...,)); $(esc(kwargs))...)
    end
end

function infer_function(interp, f, tt; show_steps::Bool=false, show_ir::Bool=false)
    # Find all methods that are applicable to these types
    fms = methods(f, tt)
    if length(fms) != 1
        error("Unable to find single applicable method for $f with types $tt")
    end

    # Take the first applicable method
    method = first(fms)

    # Build argument tuple
    method_args = Tuple{typeof(f), tt...}

    # Grab the appropriate method instance for these types
    mi = Core.Compiler.specialize_method(method, method_args, Core.svec())

    # Construct InferenceResult to hold the result,
    result = Core.Compiler.InferenceResult(mi)
    if show_steps
        @info("Initial result, before inference: ", result)
    end

    # Create an InferenceState to begin inference, give it a world that is always newest
    world = Core.Compiler.get_world_counter()
    frame = Core.Compiler.InferenceState(result, #=cached=# true, interp)

    # Run type inference on this frame.  Because the interpreter is embedded
    # within this InferenceResult, we don't need to pass the interpreter in.
    Core.Compiler.typeinf_local(interp, frame)
    if show_steps
        @info("Ending result, post-inference: ", result)
    end
    if show_ir
        @info("Inferred source: ", result.result.src)
    end

    # Give the result back
    return result
end

function foo(x, y)
    return x + y * x
end

native_interpreter = Core.Compiler.NativeInterpreter()
inferred = @infer_function native_interpreter foo(1.0, 2.0) show_steps=true show_ir=true

mutable struct CountingInterpreter <: Compiler.AbstractInterpreter
    visited_methods::Set{Core.Compiler.MethodInstance}
    methods_inferred::Ref{UInt64}

    # Keep around a native interpreter so that we can sub off to "super" functions
    native_interpreter::Core.Compiler.NativeInterpreter
end
CountingInterpreter() = CountingInterpreter(
    Set{Core.Compiler.MethodInstance}(),
    Ref(UInt64(0)),
    Core.Compiler.NativeInterpreter(),
)

InferenceParams(ci::CountingInterpreter) = InferenceParams(ci.native_interpreter)
OptimizationParams(ci::CountingInterpreter) = OptimizationParams(ci.native_interpreter)
get_world_counter(ci::CountingInterpreter) = get_world_counter(ci.native_interpreter)
get_inference_cache(ci::CountingInterpreter) = get_inference_cache(ci.native_interpreter)

function Core.Compiler.inf_for_methodinstance(interp::CountingInterpreter, mi::Core.Compiler.MethodInstance, min_world::UInt, max_world::UInt=min_world)
    # Hit our own cache; if it exists, pass on to the main runtime
    if mi in interp.visited_methods
        return Core.Compiler.inf_for_methodinstance(interp.native_interpreter, mi, min_world, max_world)
    end

    # Otherwise, we return `nothing`, forcing a cache miss
    return nothing
end

function Core.Compiler.cache_result(interp::CountingInterpreter, result::Core.Compiler.InferenceResult, min_valid::UInt, max_valid::UInt)
    push!(interp.visited_methods, result.linfo)
    interp.methods_inferred[] += 1
    return Core.Compiler.cache_result(interp.native_interpreter, result, min_valid, max_valid)
end

function reset!(interp::CountingInterpreter)
    empty!(interp.visited_methods)
    interp.methods_inferred[] = 0
    return nothing
end

counting_interpreter = CountingInterpreter()
inferred = @infer_function counting_interpreter foo(1.0, 2.0)
@info("Cumulative number of methods inferred: $(counting_interpreter.methods_inferred[])")
inferred = @infer_function counting_interpreter foo(1, 2) show_ir=true
@info("Cumulative number of methods inferred: $(counting_interpreter.methods_inferred[])")

inferred = @infer_function counting_interpreter foo(1.0, 2.0)
@info("Cumulative number of methods inferred: $(counting_interpreter.methods_inferred[])")
reset!(counting_interpreter)

@info("Cumulative number of methods inferred: $(counting_interpreter.methods_inferred[])")
inferred = @infer_function counting_interpreter foo(1.0, 2.0)
@info("Cumulative number of methods inferred: $(counting_interpreter.methods_inferred[])")

end # module
