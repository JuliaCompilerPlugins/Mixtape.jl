_Mixtape.jl_ is currently a minimal re-implementation of contextual dispatch using `IRTools.jl`. [tokei](https://github.com/XAMPPRocky/tokei) counts 41 lines of code (not including the magic of [Mike Innes](https://github.com/MikeInnes) and the wonderful [IRTools](https://github.com/MikeInnes/IRTools.jl)).

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

## How it works

There's a core `generated` function which grabs lowered method reflection information and transforms it to IR courtesy of `IRTools`:

```julia
@generated function remix!(ctx::MixTable, fn::Function, args...) 
    T = Tuple{fn, args...}
    m = IRTools.meta(T)
    m isa Nothing && error("Error in remix!: could not derive lowered method body for $T.")
    ir = IRTools.IR(m)

    # Update IR.
    n_ir = remix!(ir)

    # Update meta.
    argnames!(m, Symbol("#self#"), :ctx, :fn, :args)
    n_ir = IRTools.renumber(IRTools.varargs!(m, n_ir, 3))
    ud = update!(m.code, n_ir)
    ud.method_for_inference_limit_heuristics = nothing
    return ud
end
```

This `generated` function returns a `CodeInfo` object which the compiler eats up and assumes is "god given" (the words of [Valentin](https://github.com/vchuravy) 🐝). Inside the body of the `generated` function, there's an IR transformation which traverses the IR and inserts calls to the `generated` function itself:

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

This has the effect of bootstrapping this sort of recursive descent into method bodies, transforming the calls, etc until you hit primitives which return directly and don't recursive.

The main IR transformation ignores calls from `Base` and `Core` - by ignoring these calls, they are defined as primitives. If you want to `remix!` these calls, you'll have to define the primitives yourself.

---

In the future, I'm hoping to modify _Mixtape.jl_ to be a small re-implementation of contextual dispatch using the new `AbstractInterpreter` infrastructure. As this infrastructure becomes available, and we can dispense with recursively calling `generated` functions, performance characteristics of this library should improve.
