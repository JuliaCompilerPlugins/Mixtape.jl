module DynamicOverlay

using Mixtape
using MacroTools
using CodeInfoTools
using BenchmarkTools

foo(x) = x^5
bar(x) = x^10
apply(f, x1, x2::Val{T}) where {T} = f(x1, T)

function f(x)
    g = x < 5 ? foo : bar
    return g(2)
end

@ctx (false, false, true) struct MyMix end
allow(ctx::MyMix, m::Module) = m == DynamicOverlay

swap(e) = e
function swap(e::Expr)
    display(e)
    new = MacroTools.postwalk(e) do s
        isexpr(s, :call) || return s
        s.args[1] == Base.literal_pow || return s
        return Expr(:call, apply, Base.:(*), s.args[3:end]...)
    end
    display(e)
    return new
end

function transform(::MyMix, src)
    b = CodeInfoTools.Builder(src)
    for (v, st) in b
        b[v] = swap(st)
    end
    return CodeInfoTools.finish(b)
end

# JIT compile an entry and call.
fn = Mixtape.jit(MyMix(), f, Tuple{Int64})
display(fn(3))
display(fn(6))
@btime fn(6)

# Mixtape cached call.
Mixtape.@load_call_interface()
display(call(MyMix(), f, 3))
display(call(MyMix(), f, 6))
@btime call(MyMix(), f, 6)

# Native.
f(5)
@btime f(5)

end # module
