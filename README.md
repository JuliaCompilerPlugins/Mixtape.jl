# Mixtape.jl

> Note: Usage of this compiler package requires `Julia > 1.6`.

```julia
add https://github.com/femtomc/CodeInfoTools.jl
add https://github.com/femtomc/Mixtape.jl
```

## Function

`Mixtape.jl` is a static method overlay tool which operates during Julia type inference. It allows you to (precisely) replace `CodeInfo`, pre-optimize `CodeInfo`, and create other forms of static analysis tools on uninferred `CodeInfo` as part of Julia's native type inference system.

In many respects, it is similar to [Cassette.jl](https://github.com/JuliaLabs/Cassette.jl) -- _but it is completely static_.

> Note: the architecture for this package can be found in many other places. The interested reader might look at [KernelCompiler.jl](https://github.com/vchuravy/KernelCompiler.jl), [Enzyme.jl](https://github.com/wsmoses/Enzyme.jl), the Julia frontend to [brutus](https://github.com/JuliaLabs/brutus/tree/master), and the [compiler interface in GPUCompiler.jl](https://github.com/JuliaGPU/GPUCompiler.jl/blob/master/src/interface.jl) to understand this a bit better.
>
> When it doubt, don't be afraid of [typeinfer.jl](https://github.com/JuliaLang/julia/blob/master/base/compiler/typeinfer.jl)!

## Interfaces

```julia
using Mixtape
using Mixtape: jit, @load_call_interface
import Mixtape: CompilationContext, 
                transform, 
                allow_transform, 
                show_after_inference,
                show_after_optimization, 
                debug
```

`Mixtape.jl` exports a set of interfaces which allows you to customize parts of Julia type inference as part of a custom code generation pipeline. This code generation pipeline works through the [LLVM.jl](https://github.com/maleadt/LLVM.jl) and [GPUCompiler.jl](https://github.com/JuliaGPU/GPUCompiler.jl) infrastructure.

Usage typically proceeds as follows.

## Example

We may start with some unassuming code.

```julia
# Unassuming code in an unassuming module...
module SubFoo

function h(x)
    return rand()
end

function f(x)
    x = rand()
    y = rand()
    return x + y + h()
end

end
```

Now, we define a new subtype of `CompilationContext` which we will use to parametrize the pipeline using dispatch.

```julia
# 101: How2Mix
struct MyMix <: CompilationContext end

# Operates on `CodeInfoTools` `Builder` instances
function transform(::MyMix, b)
    for (v, st) in b
        st isa Expr || continue
        st.head == :call || continue
        st.args[1] == Base.rand || continue
        replace!(b, v, 5)
    end
    display(b)
    return b
end

# MyMix will only transform functions which you explicitly allow.
allow_transform(ctx::MyMix, fn::typeof(SubFoo.h), a...) = true

# You can greenlight whole modules, if you so desire.
allow_transform(ctx::MyMix, m::Module) = m == SubFoo

# Debug printing.
show_after_inference(ctx::MyMix) = false
show_after_optimization(ctx::MyMix) = false
debug(ctx::MyMix) = false
```

When applying `jit` with a new instance of `MyMix`, the pipeline is applied.

```julia
fn = Mixtape.jit(MyMix(), SubFoo.f, Tuple{Float64})

@assert(fn() == 15)
@assert(SubFoo.f() != 15)
```

We get to see our transformed `CodeInfo` as part of the call to `transform`.

```
CodeInfo(
    @ /Users/mccoybecker/dev/Mixtape.jl/examples/simple.jl:10 within `f'
1 ─      x = 5
│        y = 5
│   %3 = x
│   %4 = y
│   %5 = (Main.How2Mix.SubFoo.h)()
│   %6 = (+)(%3, %4, %5)
└──      return %6
)
CodeInfo(
    @ /Users/mccoybecker/dev/Mixtape.jl/examples/simple.jl:7 within `h'
1 ─ %1 = 5
└──      return %1
)
```

## Package contribution

A few upsides!

1. Completely static -- does not rely on recursive pollution of the call stack (see: [the overdub issue](https://julia.mit.edu/Cassette.jl/stable/overdub.html)).
2. Transforms operate pre-type inference -- all semantic-intruding changes happen before type inference runs on the lowered method body.
3. `Mixtape.jl` manages its own code cache -- and doesn't interact with the native runtime system (see above).

A few downsides...

1. `Mixtape.jl` uses a custom execution engine through `GPUCompiler.jl` -- code which causes `GPUCompiler.jl` to fail will also cause `Mixtape.jl` to fail. In practice, this means you can't use the pipeline on dispatch tuples with `Union{As...}` or `Any` -- you must specify a non-dynamic type.
