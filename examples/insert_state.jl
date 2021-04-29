module InsertState

using Mixtape
import Mixtape: CompilationContext, transform, allow, show_after_inference,
                show_after_optimization, debug, @load_call_interface
using MacroTools
using CodeInfoTools
using BenchmarkTools

# This shows an example where we recursively modify method calls to record state. Very monadic, dare I say :)

module Target

function baz(y::Float64)
    return y + 40.0
end

function foo(x::Float64)
    return baz(x + 20.0)
end

end

struct MyMix <: CompilationContext end

allow(ctx::MyMix, m::Module, fn, args...) = m == Target
show_after_inference(ctx::MyMix) = true
show_after_optimization(ctx::MyMix) = true
debug(ctx::MyMix) = false

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

function transform(::MyMix, src)
    b = CodeInfoTools.Pipe(src)
    q = push!(b, Expr(:call, Recorder))
    for (v, st) in b
        b[v] = swap(q, st)
    end
    return CodeInfoTools.finish(b)
end

function (r::Recorder)(f::Function, args...)
    args = map(a -> a isa Recorder ? a.ret : a, args)
    rec = call(MyMix(), f, args...)
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

Mixtape.@load_call_interface()
display(call(MyMix(), Target.foo, 5.0))
@btime call(MyMix(), Target.foo, 5.0)

end # module
