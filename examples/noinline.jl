module NoInliningAllowed

using Mixtape
import Mixtape: CompilationContext, transform, allow
using MacroTools
using CodeInfoTools
using BenchmarkTools

@noinline foo(x) = x^5
@noinline bar(x) = x^10
apply(f, x1, x2::Val{T}) where {T} = f(x1, T)

@noinline function f(x)
    g = x < 5 ? foo : bar
    return g(2)
end

struct MyMix <: CompilationContext end

allow(ctx::MyMix, m::Module) = m == NoInliningAllowed

swap(e) = e
function swap(e::Expr)
    new = MacroTools.postwalk(e) do s
        isexpr(s, :call) || return s
        s.args[1] == Base.literal_pow || return s
        return Expr(:call, apply, Base.:(*), s.args[3:end]...)
    end
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
fn = Mixtape.jit(f, Tuple{Int64}; ctx = MyMix())
display(fn(3))
display(fn(6))
@btime fn(6)

# Mixtape cached call.
Mixtape.@load_abi()
display(call(f, 3; ctx = MyMix()))
display(call(f, 6; ctx = MyMix()))
@btime call(f, 6; ctx = MyMix())

# Native.
f(5)
@btime f(5)

end # module
