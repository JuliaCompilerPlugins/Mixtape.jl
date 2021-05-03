module CassetteV2

using Mixtape
import Mixtape: CompilationContext, allow, transform 
using CodeInfoTools
using BenchmarkTools

# I had to do it.

module Target

function baz(y::Float64)
    return y + 40.0
end

function foo(x::Float64)
    return baz(x + 20.0)
end

end

# Controls when the transform on lowered code applies. 
# I don't want to apply the recursive transform in type inference.
# So when stacklevel > 1, don't apply.
# I'll just dispatch to `Mixtape.call` at runtime.
mutable struct Mix <: CompilationContext
    stacklevel::Int
end
Mix() = Mix(1)

# Allow the transform on our Target module.
allow(ctx::Mix, m::Module, fn, args...) = m == Target

# Basically == a Cassette context.
struct Context
    d::Dict
    Context() = new(Dict())
end

# Our version of overdub.
overdub(::Context, f, args...) = f(args...)
function overdub(ctx::Context, ::typeof(+), args...)
    ret = (+)(args...)
    ctx.d[(Base.:(+), args...)] = ret
    return ret
end

function overdub(ctx::Context, fn::Function, args...)
    ret, inner = call(fn, args...; ctx = Mix())
    Base.merge!(ctx.d, inner.d)
    return ret
end

# The transform inserts state, then wraps calls in (overdub).
# Then, anytime there's a return value --
# create a tuple of (ret, state)
# and returns that. 
# Consider monadic lifting f: R -> R => trans => R -> (R, state).
swap(r, e) = e
function swap(r, e::Expr)
    e.head == :call || return e
    return Expr(:call, overdub, r, e.args[1:end]...)
end

function transform(mix::Mix, src, sig)
    b = CodeInfoTools.Builder(src)
    mix.stacklevel == 1 || return src
    q = push!(b, Expr(:call, Context))
    rets = Any[]
    for (v, st) in b
        b[v] = swap(q, st)
        st isa Core.ReturnNode && push!(rets, v => st)
    end
    for (n, ret) in rets
        v = insert!(b, n, Expr(:call, Base.tuple, ret.val, q))
        b[n] = Core.ReturnNode(v)
    end
    mix.stacklevel += 1
    return CodeInfoTools.finish(b)
end

Mixtape.@load_abi()
ret = call(Target.foo, 5.0; ctx = Mix(1))
ret = call(Target.foo, 5.0; ctx = Mix(1), optlevel = 1)
ret = call(Target.foo, 5.0; ctx = Mix(1), optlevel = 2)
ret = call(Target.foo, 5.0; ctx = Mix(1), optlevel = 3)
display(ret)
@btime call(Target.foo, 5.0; ctx = Mix(1))

src = emit(Target.foo, Tuple{Float64}; 
           ctx = Mix(1), opt = true)
display(src)
display(src.ssavaluetypes)

end # module
