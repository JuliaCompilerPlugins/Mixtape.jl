module DynamicOverlay

using Mixtape
using MacroTools
using InteractiveUtils
using BenchmarkTools

foo(x) = error("Right here!")
bar(x) = x^10
apply(f, x1, x2::Val{T}) where {T} = f(x1, T)

function f(x)
    g = x < 5 ? foo : bar
    return g(2)
end

f(3)

#####
##### Mixtape
#####

foo(x) = x^5
bar(x) = x^10
apply(f, x1, x2::Val{T}) where {T} = f(x1, T)

function f(x)
    g = x < 5 ? foo : bar
    return g(2)
end

@ctx (true, true, false) struct MyMix end
allow(ctx::MyMix, m::Module) = m == DynamicOverlay

swap(e) = e
function swap(e::Expr)
    new = MacroTools.postwalk(e) do s
        isexpr(s, :call) || return s
        s.args[1] == Base.literal_pow || return s
        return Expr(:call, Base.error, "Right here!")
    end
    return new
end

function transform(::MyMix, b)
    for (v, st) in b
        replace!(b, v, swap(st))
    end
    return b
end

# Mixtape cached call.
Mixtape.@load_call_interface()
display(call(MyMix(), f, 3))

end # module
