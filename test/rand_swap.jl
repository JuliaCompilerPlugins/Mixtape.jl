function rosenbrock(x)
    a = 1.0
    b = 100.0
    result = 0.0
    for i in 1:(length(x) - 1)
        result += (a - x[i])^2 + b * (x[i + 1] - x[i]^2)^2
    end
    return result
end

function f()
    x = rand()
    y = rand()
    return rosenbrock([x, y])
end

g(f) = f()

struct RandMix <: CompilationContext end
allow(ctx::RandMix, m::Module) = m == TestMixtape

swap(e) = e
function swap(e::Expr)
    new = MacroTools.postwalk(e) do s
        isexpr(s, :call) || return s
        s.args[1] == Base.rand || return s
        return 5
    end
    return new
end

function transform(::RandMix, src)
    b = CodeInfoTools.Pipe(src)
    for (v, st) in b
        b[v] = swap(st)
    end
    return CodeInfoTools.finish(b)
end

@testset "Rand swap" begin
    fn = Mixtape.jit(RandMix(), f, Tuple{})
    @test fn() == rosenbrock([5, 5])
    Mixtape.@load_call_interface()
    @test call(RandMix(), f) == rosenbrock([5, 5])
    @test f() != rosenbrock([5, 5])
    fn = Mixtape.jit(RandMix(), g, Tuple{typeof(f)})
    @test fn() == rosenbrock([5, 5])
    @test call(RandMix(), g, f) == rosenbrock([5, 5])
end
