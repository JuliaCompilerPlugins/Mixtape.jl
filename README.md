# Mixtape.jl

> Note: Usage of this compiler package requires `Julia > 1.6`.

## Function

`Mixtape.jl` is a static method overlay tool which operates during Julia type inference. It allows you to (precisely) replace `CodeInfo`, pre-optimize `CodeInfo`, and create other forms of static analysis tools on uninferred `CodeInfo` as part of Julia's native type inference system.

In many respects, it is similar to [Cassette](https://github.com/JuliaLabs/Cassette.jl) -- _but it is completely static_.

## Interfaces

```julia
using Mixtape
import Mixtape: CompilationContext, 
                transform, 
                allow_transform, 
                show_after_inference,
                show_after_optimization, 
                debug,
                jit
```

`Mixtape.jl` exports a set of interfaces which allows you to customize parts of Julia type inference as part of a custom code generation pipeline. This code generation pipeline works through the [LLVM.jl](https://github.com/maleadt/LLVM.jl) and [GPUCompiler.jl](https://github.com/JuliaGPU/GPUCompiler.jl) infrastructure.

Usage typically proceeds as follows.

## Example

We may start with some unassuming code.

```julia
# Unassuming code in an unassuming module...
module SubFoo

function h(x)
    x = rand()
    y = rand()
    return x + y
end

function f(x)
    z = rand()
    return h(x)
end

end
```

Now, we define a new subtype of `CompilationContext` which we will use to parametrize the pipeline using dispatch.

```julia
# 101: How2Mix
struct MyMix <: CompilationContext end

# Operates on IRTools.IR.
# Must return IRTools.IR when finished.
function transform(::MyMix, ir)
    for (v, st) in ir
        st.expr isa Expr || continue
        st.expr.head == :call || continue
        st.expr.args[1] == Base.rand || continue
        ir[v] = 5
    end
    display(ir)
    return ir
end

# MyMix will only transform functions which you explicitly allow.
allow_transform(ctx::MyMix, fn::typeof(SubFoo.h), a...) = true

# You can greenlight whole modules, if you so desire.
allow_transform(ctx::MyMix, m::Module) = m == SubFoo

# Debug printing.
show_after_inference(ctx::MyMix) = false
show_after_optimization(ctx::MyMix) = false
debug(ctx::MyMix) = true
```

When applying `jit` with a new instance of `MyMix`, the pipeline is applied.

```julia
fn = Mixtape.jit(MyMix(), SubFoo.f, Tuple{Float64})
@time fn = Mixtape.jit(MyMix(), SubFoo.f, Tuple{Float64})

display(fn(5.0))
display(SubFoo.f(5.0))
```

We get to see our transformed `IRTools.IR` as part of the call to `transform`.

```julia
1: (%1 :: typeof(Main.How2Mix.SubFoo.f), %2 :: Float64)
  %3 = (rand)()
  %4 = (Main.How2Mix.SubFoo.h)(%2)
  return %4
1: (%1 :: typeof(Main.How2Mix.SubFoo.h), %2 :: Float64)
  %3 = (rand)()
  %4 = (rand)()
  %5 = (+)(%3, %4)
  return %5
  0.000007 seconds
10
1.1235863744100292
```

## Package contribution

1. Completely static -- does not rely on recursive pollution of the call stack.
2. Pre-type inference -- all semantic-intruding changes happen before type inference runs on the lowered method body.
3. `Mixtape.jl` manages its own code cache -- doesn't interact with the native runtime system (see above).

However, there are some downsides. `Mixtape.jl` may choke on code which also causes `Cassette.jl` to choke. However, debugging should be easier. In addition, because `Mixtape.jl` uses a custom execution engine through `GPUCompiler.jl` -- code which causes `GPUCompiler.jl` to fail will also cause `Mixtape.jl` to fail. Both of these downsides should be worked out over time.
