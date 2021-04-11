module EqualitySaturation

using Mixtape
using MacroTools
using BenchmarkTools

f(x) = (x - x) + (10 * 15)

@ctx (true, true, false) struct MyMix end
allow(ctx::MyMix, m::Module) = m == EqualitySaturation

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
    return b
end

Mixtape.@load_call_interface()
display(call(MyMix(), f, 3))

end # module
