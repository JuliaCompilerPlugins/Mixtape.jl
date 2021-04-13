module Tracing

f(x::Int64) = x <= 1 ? 1 : x * f(x - 1)

end

@ctx (false, false, false) struct MyMix end
allow(ctx::MyMix, m::Module) = m == Tracing

swap(e) = e
function swap(e::Expr)
    new = MacroTools.postwalk(e) do s
        isexpr(s, :call) || return s
        s.args[1] == Base.:(*) || return s
        return Expr(:call, Base.:(+), e.args[2:end]...)
    end
    return new
end

# Secondary interpreter -- gets typed CodeInfo from the first.
function transform(::MyMix, b)
    for (v, st) in b
        replace!(b, v, swap(st))
    end
    return b
end

# "Low-level" optimizer -- after the secondary interpreter.
function optimize!(::MyMix, ir)
    return ir
end

# "High-level"  optimizer -- first does type inference, then gets to see the IR before feeding it to the second interpreter.
function trace!(::MyMix, ir)
    return ir
end

# Allow the high-level interpreter into the pipeline.
@testset "Tracing" begin
    allow_tracing(ctx::MyMix) = true
    entry = Mixtape.jit(MyMix(), Tracing.f, Tuple{Int})
    @test entry(5) == 15
end
