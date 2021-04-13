module CassetteV2

using Mixtape
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
@ctx (false, false, false) mutable struct Mix 
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
    ret, inner = call(Mix(), fn, args...)
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

function insert_tuple_return!(ctx_val, b)
    nodes = Any[]
    for (v, st) in b
        st isa Core.ReturnNode || continue
        push!(nodes, v => st)
    end
    for (n, ret) in nodes
        insert!(b, n, Expr(:call, Base.tuple, ret.val, ctx_val))
        replace!(b, n + 1, Core.ReturnNode(n))
    end
end

function transform(mix::Mix, b)
    mix.stacklevel == 1 || return
    pushfirst!(b, Expr(:call, Context))
    for (v, st) in b
        e = swap(Core.SSAValue(1), st)
        v == Core.SSAValue(1) || replace!(b, v, e)
    end
    insert_tuple_return!(Core.SSAValue(1), b)
    mix.stacklevel += 1
    return b
end

# Optimize decrements the stacklevel. 
# This honestly doesn't really matter, but it is good form.
function postopt!(mix::Mix, ir)
    mix.stacklevel -= 1
    return ir
end

Mixtape.@load_call_interface()
ret, state = call(Mix(1), Target.foo, 5.0)
display(state)
@btime call(Mix(1), Target.foo, 5.0)

end # module
