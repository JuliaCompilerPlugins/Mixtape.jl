foo(x) = x^5
bar(x) = x^10
apply(f, x1, x2::Val{T}) where {T} = f(x1, T)

function f(x)
    g = x < 5 ? foo : bar
    return g(2)
end

@ctx (false, false, false) struct DynamicMix end
allow(ctx::DynamicMix, m::Module) = m == TestMixtape

swap(e) = e
function swap(e::Expr)
    new = MacroTools.postwalk(e) do s
        s isa Expr || return s
        s.head == :call || return s
        s.args[1] == Base.literal_pow || return s
        return Expr(:call, apply, Base.:(*), s.args[3:end]...)
    end
    return new
end

function transform(::DynamicMix, src)
    b = CodeInfoTools.Builder(src)
    for (v, st) in b
        b[v] = swap(st)
    end
    return CodeInfoTools.finish(b)
end

# JIT compile an entry and call.
@testset "Dynamic overlay" begin
    fn = Mixtape.jit(DynamicMix(), f, Tuple{Int64})
    @test fn(3) == 10
    @test fn(6) == 20

    # Mixtape cached call.
    Mixtape.@load_call_interface()
    @test call(DynamicMix(), f, 3) == 10
    @test call(DynamicMix(), f, 6) == 20

    # Native.
    @test f(3) == 2^5
    @test f(6) == 2^10
end
