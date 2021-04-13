module Tracing

using Mixtape
using MacroTools

module Factorial

f(x::Int64) = x <= 1 ? 1 : x * f(x - 1)

end

@ctx (false, false, false) struct MyMix end
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

# Secondary interpreter -- gets typed CodeInfo from the first.
function transform(::MyMix, b)
    for (v, st) in b
        replace!(b, v, swap(st))
    end
    return b
end

# "Low-level" optimizer -- after the secondary interpreter.
optimize!(::MyMix, ir) = ir

# "High-level"  optimizer -- first does type inference, then gets to see the IR before feeding it to the second interpreter.
trace!(::MyMix, ir) = (display(ir); ir)

# Allow the high-level interpreter into the pipeline.
allow_tracing(ctx::MyMix) = true

entry = Mixtape.jit(MyMix(), Factorial.f, Tuple{Int})
display(entry(5))

end # module