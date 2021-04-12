module Tracing

using Mixtape
using MacroTools

module Factorial

f(x::Int64) = x <= 1 ? 1 : x * f(x - 1)

end

@ctx (false, false, false) struct MyMix end
allow(ctx::MyMix, m::Module) = m == Factorial
allow_tracing(ctx::MyMix) = true

swap(e) = e
function swap(e::Expr)
    new = MacroTools.postwalk(e) do s
        isexpr(s, :call) || return s
        s.args[1] == Base.:(*) || return s
        return Expr(:call, Base.:(+), e.args[2:end]...)
    end
    return new
end

function transform(::MyMix, b)
    for (v, st) in b
        replace!(b, v, swap(st))
    end
    return b
end

optimize!(::MyMix, ir) = ir
trace!(::MyMix, ir) = (display(ir); ir)

entry = Mixtape.jit(MyMix(), Factorial.f, Tuple{Int})

end # module
