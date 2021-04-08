module DynamicOverlay

using Mixtape
import Mixtape: CompilationContext, transform, allow_transform, show_after_inference, show_after_optimization, debug
using MacroTools
using BenchmarkTools

foo(x) = x^5
bar(x) = x^10
apply(f, x1, x2::Val{T}) where T = f(x1, T)

function f(x)
   g = x < 5 ? foo : bar
   g(2)
end

struct MyMix <: CompilationContext end

allow_transform(ctx::MyMix, m::Module) = m == DynamicOverlay
show_after_inference(ctx::MyMix) = false
show_after_optimization(ctx::MyMix) = false
debug(ctx::MyMix) = true

swap(e) = e
function swap(e::Expr)
    new = MacroTools.postwalk(e) do s
        isexpr(s, :call) || return s
        s.args[1] == Base.literal_pow || return s
        return Expr(:call, apply, Base.:(*), s.args[3 : end]...)
    end
    return new
end

function transform(::MyMix, b)
    for (v, st) in b
        replace!(b, v, swap(st))
    end
    return b
end


fn = Mixtape.jit(MyMix(), f, Tuple{Int64})
fn(5)
Mixtape.call(MyMix(), f, 5)
f(5)

@btime fn(5)
@btime Mixtape.call(MyMix(), f, 5)
@btime f(5)

end # module
