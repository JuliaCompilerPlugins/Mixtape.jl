module Structs

using Mixtape
import Mixtape: CompilationContext, transform, allow, show_after_inference,
                show_after_optimization, debug, @load_call_interface
using MacroTools
using BenchmarkTools

struct Foo
    x::Float64
end

struct Bar
    x::Float64
end

function f(x::Foo, y::Float64)
    return Foo(x.x + y)
end

struct MyMix <: CompilationContext end

allow(ctx::MyMix, m::Module) = m == Structs
show_after_inference(ctx::MyMix) = false
show_after_optimization(ctx::MyMix) = false
debug(ctx::MyMix) = true

swap(e) = e
function swap(e::Expr)
    new = MacroTools.postwalk(e) do s
        isexpr(s, :call) || return s
        s.args[1] == Foo || return s
        return Expr(:call, Bar, s.args[2:end]...)
    end
    return new
end

function transform(::MyMix, b)
    for (v, st) in b
        replace!(b, v, swap(st))
    end
    display(b)
    return b
end

# Mixtape cached call.
Mixtape.@load_call_interface()
display(call(MyMix(), f, Foo(10.0), 5.0))
@btime call(MyMix(), f, Foo(10.0), 5.0)

end # module
