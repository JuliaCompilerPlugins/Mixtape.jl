module StaticCompile

using Mixtape
using MacroTools

module Factorial

Base.@ccallable Ptr{Cvoid} function f(x::Int64)
    x <= 1 ? 1 : x * f(x - 1)
end

end

@ctx (true, false, false) struct MyMix end
allow(ctx::MyMix, m::Module) = m == Factorial

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

p = "libf"
Mixtape.aot(MyMix(), Factorial.f, Tuple{Int}; path = p)
#rm(p)

end # module
