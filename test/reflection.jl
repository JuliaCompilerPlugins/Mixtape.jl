module Reflection

f(x::Int64) = x <= 1 ? 1 : x * f(x - 1)

end

@ctx (false, false, false) struct MyMix end
allow(ctx::MyMix, m::Module) = m == Reflection

swap(e) = e
function swap(e::Expr)
    new = MacroTools.postwalk(e) do s
        isexpr(s, :call) || return s
        s.args[1] == Base.:(*) || return s
        return Expr(:call, Base.:(+), e.args[2:end]...)
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

ir = Mixtape.@code_info Reflection.f(Int)
ir = Mixtape.@code_inferred MyMix() Reflection.f(Int)
ir = Mixtape.@code_llvm MyMix() Reflection.f(Int)
