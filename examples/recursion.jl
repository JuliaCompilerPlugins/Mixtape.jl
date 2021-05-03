module Recursion

using Mixtape
import Mixtape: CompilationContext, transform, allow
using CodeInfoTools
using MacroTools

module Factorial

f(x::Int64) = x <= 1 ? 1 : x * f(x - 1)

end

struct MyMix <: CompilationContext end
allow(ctx::MyMix, m::Module) = m == Factorial

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
    b = CodeInfoTools.Builder(src)
    for (v, st) in b
        b[v] = swap(st)
    end
    return CodeInfoTools.finish(b)
end

function postopt!(::MyMix, ir)
    display(ir)
    ir
end

Mixtape.@load_abi()
display(call(Factorial.f, 10; ctx = MyMix()))

end # module
