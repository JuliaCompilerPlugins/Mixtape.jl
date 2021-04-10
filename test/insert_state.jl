module Target

function baz(y::Float64)
    return y + 40.0
end

function foo(x::Float64)
    return baz(x + 20.0)
end

end

struct StateMix <: CompilationContext end

allow(ctx::StateMix, m::Module, fn, args...) = m == Target

show_after_inference(ctx::StateMix) = false
show_after_optimization(ctx::StateMix) = false
debug(ctx::StateMix) = false

mutable struct Recorder
    d::Dict
    ret::Any
    Recorder() = new(Dict(), nothing)
    Recorder(d, ret) = new(d, ret)
end

swap(r, e) = e
function swap(r, e::Expr)
    e.head == :call || return e
    return Expr(:call, r, e.args[1:end]...)
end

function transform(::StateMix, b)
    pushfirst!(b, Expr(:call, Recorder))
    for (v, st) in b
        e = swap(Core.SSAValue(1), st)
        v == 1 || replace!(b, v, e)
    end
    return b
end

@testset "Insert state" begin
    Mixtape.@load_call_interface()

    function (r::Recorder)(f::Function, args...)
        args = map(a -> a isa Recorder ? a.ret : a, args)
        rec = call(StateMix(), f, args...)
        if rec isa Recorder
            merge!(r.d, rec.d)
            r.d[(f, args...)] = rec.ret
            r.ret = rec.ret
        else
            r.d[(f, args...)] = rec
            r.ret = rec
        end
        return r
    end

    rec = call(StateMix(), Target.foo, 5.0)
    @test rec.d[(Target.baz, 25.0)] == 65.0
    @test rec.d[(Base.:(+), 5.0, 20.0)] == 25.0
    @test rec.d[(Base.:(+), 25, 40.0)] == 65.0
    @test rec.ret == 65.0
end
