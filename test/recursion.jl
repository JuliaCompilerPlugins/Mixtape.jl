module Factorial

f(x::Int64) = x <= 1 ? 1 : x * f(x - 1)

end

@ctx (false, false, false) struct RecursionMix end
allow(ctx::RecursionMix, m::Module) = m == Factorial
debug(::RecursionMix) = false

swap(e) = e
function swap(e::Expr)
    new = MacroTools.postwalk(e) do s
        s isa Expr || return s
        s.head == :call || return s
        s.args[1] == Base.:(*) || return s
        return Expr(:call, Base.:(+), e.args[2:end]...)
    end
    return new
end

function transform(::RecursionMix, b)
    for (v, st) in b
        replace!(b, v, swap(st))
    end
    return b
end

@testset "Recursion" begin
    Mixtape.@load_call_interface()
    @test call(RecursionMix(), Factorial.f, 10) == 55
end
