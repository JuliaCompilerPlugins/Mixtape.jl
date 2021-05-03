module Structs

using Mixtape
import Mixtape: CompilationContext, transform, allow
using MacroTools
using CodeInfoTools
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

swap(e) = e
function swap(e::Expr)
    new = MacroTools.postwalk(e) do s
        isexpr(s, :call) || return s
        s.args[1] == Foo || return s
        return Expr(:call, Bar, s.args[2:end]...)
    end
    return new
end

function transform(::MyMix, src)
    b = CodeInfoTools.Builder(src)
    for (v, st) in b
        b[v] = swap(st)
    end
    display(b)
    return CodeInfoTools.finish(b)
end

# Mixtape cached call.
Mixtape.@load_abi()
display(call(f, Foo(10.0), 5.0; ctx = MyMix()))
@btime call(f, Foo(10.0), 5.0; ctx = MyMix())

end # module
