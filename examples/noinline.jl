module NoInliningAllowed

using Mixtape
import Mixtape: CompilationContext, transform, allow, show_after_inference,
                show_after_optimization, debug, @load_call_interface
using MacroTools
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
show_after_inference(ctx::MyMix) = false
show_after_optimization(ctx::MyMix) = false
debug(ctx::MyMix) = true

swap(e) = e
function swap(e::Expr)
    new = MacroTools.postwalk(e) do s
        isexpr(s, :call) || return s
        s.args[1] == Base.literal_pow || return s
        return Expr(:call, apply, Base.:(*), s.args[3:end]...)
    end
    return new
end

function transform(::MyMix, b)
    for (v, st) in b
        replace!(b, v, swap(st))
    end
    return b
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
