module CtxMacro

using Mixtape
using CodeInfoTools
using MacroTools

foo(x) = x^5
bar(x) = x^10
apply(f, x1, x2::Val{T}) where {T} = f(x1, T)

function f(x)
    g = x < 5 ? foo : bar
    return g(2)
end

@ctx (false, true, false) struct MyMix end
allow(ctx::MyMix, m::Module) = m == CtxMacro

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
    b = CodeInfoTools.Pipe(src)
    for (v, st) in b
        b[v] = swap(st)
    end
    return CodeInfoTools.finish(b)
end

Mixtape.@load_call_interface()
display(call(MyMix(), f, 3))

end # module
