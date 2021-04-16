f(x::Int64) = x <= 1 ? 1 : x * f(x - 1)

@ctx (true, true, true) struct InvalidationMix end
allow(ctx::InvalidationMix, m::Module) = m == Factorial
debug(::InvalidationMix) = false

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

function transform(::InvalidationMix, b)
    for (v, st) in b
        b[v] = swap(st)
    end
    return b
end

@testset "Invalidation" begin
    Mixtape.@load_call_interface()
    @test call(InvalidationMix(), Factorial.f, 10) == 55
end

f(x::Int64) = x <= 1 ? 1 : x * f(x - 1)

@testset "Invalidation" begin
    Mixtape.@load_call_interface()
    @test call(InvalidationMix(), Factorial.f, 10) == 55
end
