module HandleInvoke

using Mixtape
using MacroTools
using BenchmarkTools

@noinline foo(x) = x^5
@noinline bar(x) = x^10
apply(f, x1, x2::Val{T}) where {T} = f(x1, T)

@noinline function f(x)
    g = x < 5 ? foo : bar
    return invoke(g, Tuple{Int}, 2)
end

@ctx (false, false, false) struct MyMix end

allow(ctx::MyMix, m::Module) = m == HandleInvoke
show_after_inference(ctx::MyMix) = false
show_after_optimization(ctx::MyMix) = false
debug(ctx::MyMix) = false

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
    display(b)
    b = Mixtape.widen_invokes!(b)
    for (v, st) in b
        replace!(b, v, swap(st))
    end
    return b
end

Mixtape.@load_call_interface()
display(@time call(MyMix(), f, 3))

end # module
