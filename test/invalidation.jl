f(x::Int64) = x <= 1 ? 1 : x * f(x - 1)

@ctx (true, true, true) struct InvalidationMixMix end
allow(ctx::InvalidationMixMix, m::Module) = m == Factorial
debug(::InvalidationMixMix) = false

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

function transform(::InvalidationMixMix, b)
    for (v, st) in b
        replace!(b, v, swap(st))
    end
    return b
end

@testset "InvalidationMix" begin
    Mixtape.@load_call_interface()
    @test call(InvalidationMixMix(), Factorial.f, 10) == 55
end

f(x::Int64) = x <= 1 ? 1 : x * f(x - 1)

@testset "InvalidationMix" begin
    Mixtape.@load_call_interface()
    @test call(InvalidationMixMix(), Factorial.f, 10) == 55
end
