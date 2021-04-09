module Intrinsics

using Mixtape
using Mixtape: @intrinsic
import Mixtape: CompilationContext, transform, optimize!, allow, show_after_inference,
                show_after_optimization, debug, @load_call_interface
using MacroTools
using InteractiveUtils
using BenchmarkTools

@intrinsic concrete
display(concrete)

module Target
using ..Intrinsics: concrete
g(x) = x + 10
f(x) = invoke(g, Tuple{Any}, x)
end

struct MyMix <: CompilationContext end

allow(ctx::MyMix, m::Module, fn, args...) = m == Target
show_after_inference(ctx::MyMix) = true
show_after_optimization(ctx::MyMix) = true
debug(ctx::MyMix) = false

function transform(::MyMix, b)
    return b
end

Mixtape.@load_call_interface()

# Mixtape cached call.
display(call(MyMix(), Target.f, 5))

end # module
