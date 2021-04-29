module Inlining

using Mixtape
using CodeInfoTools
using CodeInfoTools: var, get_slot, walk

invert(ret, f, args...)  = f(args...)

@ctx (false, false, false) mutable struct Mix 
    stacklevel::Int
end
Mix() = Mix(1)

# Allow the transform on our Target module.
allow(ctx::Mix, fn::typeof(invert), args...) = true

function transform(mix::Mix, b, sig)
    if !(sig[3] <: Function) || 
        sig[3] === Core.IntrinsicFunction
        return identity(b)
    end # If target is not a function, just return b.
    forward = sig[3].instance
    argtypes = sig[4 : end]
    forward = Mixtape._code_info(forward, Tuple{argtypes...})
    submap = Dict()
    for (ind, a) in enumerate(forward.slotnames[2 : end])
        push!(b, Expr(:call, Base.getindex, Core.SlotNumber(4), ind))
        setindex!(submap, var(ind), get_slot(forward, a))
    end
    for (v, st) in enumerate(forward.code)
        if st isa Expr
            ex = Expr(:call, invert, Int, walk(v -> get(submap, v, v), st).args...) # TODO: need to get return type here I think.
        else
            ex = walk(v -> get(submap, v, v), st)
        end
        setindex!(submap, push!(b, ex), var(v))
    end
    println("Resultant IR for $(sig):")
    display(b)
    return b
end

function foo(x)
    return x + 5
end

Mixtape.@load_call_interface()
ret = call(Mix(1), invert, 10, foo, 5)
display(ret)

end # module
