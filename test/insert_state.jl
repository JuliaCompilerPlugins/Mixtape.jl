mutable struct Recorder
    d::Dict
    ret
    Recorder() = new(Dict(), nothing)
    Recorder(d, ret) = new(d, ret)
end

function (r::Recorder)(f::Function, args...)
    args = map(a -> a isa Recorder ? a.ret : a, args)
    ret = f(args...)
    r.d[(f, args...)] = ret
    r.ret = ret
    return r
end

module Target

function baz(y::Float64)
    return y + 20.0
end

function foo(x::Float64)
    return baz(x + 20.0)
end

end

struct MyMix <: CompilationContext end

allow_transform(ctx::MyMix, m::Module, fn, args...) = m == Target

show_after_inference(ctx::MyMix) = false
show_after_optimization(ctx::MyMix) = false
debug(ctx::MyMix) = false

swap(r, e) = e
function swap(r, e::Expr)
    e.head == :call || return e
    return Expr(:call, r, e.args[1 : end]...)
end

function transform(::MyMix, b)
    circshift!(b, 1) # Shifts all SSA values by 1
    pushfirst!(b, Expr(:call, Recorder))
    for (v, st) in b
        e = swap(Core.SSAValue(1), st)
        v == 1 || replace!(b, v, e)
    end
    return b
end

# Mixtape cached call.

@testset "Insert state" begin
    Mixtape.@load_call_interface()
    rec = call(MyMix(), Target.foo, 5.0)
    @test rec.d[(Target.baz, 25.0)] == 45.0
    @test rec.d[(Base.:(+), 5.0, 20.0)] == 25.0
    @test rec.ret == 45.0
end
