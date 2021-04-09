module EqualitySaturation

using Mixtape
import Mixtape: CompilationContext, transform, allow, show_after_inference,
                show_after_optimization, debug, @load_call_interface
using MacroTools
using InteractiveUtils
using BenchmarkTools

f(x) = (x - x)

struct MyMix <: CompilationContext end

allow(ctx::MyMix, m::Module) = m == EqualitySaturation
show_after_inference(ctx::MyMix) = true
show_after_optimization(ctx::MyMix) = true
debug(ctx::MyMix) = false

swap(e) = e
function swap(e::Expr)
    new = MacroTools.postwalk(e) do s
        isexpr(s, :call) || return s
        s.args[1] == Base.literal_pow || return s
        return Expr(:call, apply, Base.:(*), s.args[3:end]...)
    end
    return new
end

function transform(::MyMix, b)
    #for (v, st) in b
    #    replace!(b, v, swap(st))
    #end
    return b
end

Mixtape.@load_call_interface()
display(call(MyMix(), f, 3))

end # module
