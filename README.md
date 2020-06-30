_Mixtape.jl_ is currently a minimal re-implementation of contextual dispatch using `IRTools.jl`.

Usage is very simple - you use `remix!` just like you use `overdub`.

In this library, context objects type inherit from the `MixTable` abstract type.

```julia
module TestBench

include("../src/Mixtape.jl")
using .Mixtape

function foo(x::Float64, y::Float64)
    q = x + 20.0
    l = q + 20.0
    return l
end

mutable struct CountingMix <: Mixtape.MixTable
    count::Int
    CountingMix() = new(0)
end

function Mixtape.remix!(ctx::CountingMix, fn::typeof(+), args...)
    ctx.count += 1
    return fn(args...)
end

ctx = CountingMix()
x = Mixtape.remix!(ctx, foo, 5.0, 3.0)
println(ctx.count)

end
```

This library ignores calls from `Base` and `Core`, as can be seen in the main IR transformation:

```julia
function remix!(ir)
    pr = IRTools.Pipe(ir)
   
    # Iterate across Pipe, inserting calls to the generated function and inserting the context argument.
    new = argument!(pr)
    for (v, st) in pr
        ex = st.expr
        ex isa Expr && ex.head == :call && begin

            # Ignores Base and Core.
            if !(ex.args[1] isa GlobalRef && (ex.args[1].mod == Base || ex.args[1].mod == Core))
                args = copy(ex.args)
                pr[v] = Expr(:call, GlobalRef(Mixtape, :remix!), new, ex.args...)
            end
        end
    end

    # Turn Pipe into IR.
    ir = IRTools.finish(pr)
    
    # Re-order arguments.
    ir_args = IRTools.arguments(ir)
    insert!(ir_args, 2, ir_args[end])
    pop!(ir_args)
    blank = argument!(ir)
    insert!(ir_args, 3, ir_args[end])
    pop!(ir_args)
    return ir
end
```
by ignoring these calls, they are defined as primitives. If you want to `remix!` these calls, you'll have to define the primitives yourself.

---

In the future, _Mixtape.jl_ will be a minimal re-implementation of contextual dispatch using the new `AbstractInterpreter` infrastructure in Julia 1.6. As this infrastructure becomes available, and we can dispense with recursively calling `generated` functions, performance characteristics of this library should improve.
