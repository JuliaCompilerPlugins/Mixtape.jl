#####
##### MixtapeInterpreter
#####

# User-extended context allows parametrization of the pipeline through
# our subtype of AbstractInterpreter
abstract type CompilationContext end

@doc(
"""
    abstract type CompilationContext end

Parametrize the Mixtape pipeline by inheriting from `CompilationContext`. Similar to the context objects in [Cassette.jl](https://julia.mit.edu/Cassette.jl/stable/contextualdispatch.html). By using the interface methods `show_after_inference`, `show_after_optimization`, `debug`, `transform`, and `optimize!` -- the user can control different parts of the compilation pipeline.
""", CompilationContext)

show_after_inference(ctx::CompilationContext) = false

@doc(
"""
    show_after_inference(ctx::CompilationContext)::Bool

Turns on a pipeline feature which will dump out `CodeInfo` after inference (including the user-defined `transform` transformation, if applied).
""", show_after_inference)

show_after_optimization(ctx::CompilationContext) = false

@doc(
"""
    show_after_optimization(ctx::CompilationContext)::Bool

Turns on a pipeline feature which will dump out `CodeInfo` after optimization (including the user-defined `optimize!` transformation, if applied).
""", show_after_optimization)

debug(ctx::CompilationContext) = false

@doc(
"""
    debug(ctx::CompilationContext)::Bool

Turn on debug tracing for inference and optimization. Displays an instrumentation trace as inference and optimization proceeds.
""", debug)


transform(ctx::CompilationContext, b) = b

@doc(
"""
    transform(ctx::CompilationContext, b::CodeInfoTools.Builder)::CodeInfoTools.Builder

User-defined transform which can operate on lowered `CodeInfo` in the form of a `CodeInfoTools.Builder` object.

Transforms might typically follow a simple "replace" format:

```julia
function transform(::MyCtx, b)
    for (k, st) in b
        replace!(b, k, swap(st))
    end
    return b
end
```

but more advanced formats are possible. For further utilities, please see [CodeInfoTools.jl](https://github.com/femtomc/CodeInfoTools.jl).
""", transform)

optimize!(ctx::CompilationContext, ir) = ir

@doc(
"""
    optimize!(ctx::CompilationContext, ir::Core.Compiler.IRCode)::Core.Compiler.IRCode

User-defined transform which can operate on inferred `Core.Compiler.IRCode`. This transform operates after a set of optimizations which mimic Julia's pipeline.
""", optimize!)

allow(f::C, args...) where {C <: CompilationContext} = false
function allow(ctx::CompilationContext, mod::Module, fn, args...)
    return allow(ctx, mod) || allow(ctx, fn, args...)
end

@doc(
"""
    allow(f::CompilationContext, args...)::Bool

Determines whether a user-defined `transform` or `optimize!` is allowed to look at a lowered `CodeInfoTools.Builder` object or `Core.Compiler.IRCode`.

The user is allowed to greenlight modules:

```julia
allow(::MyCtx, m::Module) == m == SomeModule
```

or even specific signatures

```julia
allow(::MyCtx, fn::typeof(rand), args...) = true
```
""", allow)

macro ctx(properties, expr)
    @assert(@capture(expr, struct Name_
                         body__
                     end))
    @assert(properties.head == :tuple)
    properties = properties.args
    ex = Expr(:block,
              quote
                  import Mixtape: allow, show_after_inference, show_after_optimization,
                                  debug, transform, optimize!
              end, quote
                  struct $Name <: Mixtape.CompilationContext
                      $(body...)
                  end
              end, quote
                  show_after_inference(::$Name) = $(properties[1])
                  show_after_optimization(::$Name) = $(properties[2])
                  debug(::$Name) = $(properties[3])
              end)
    ex = postwalk(rmlines ∘ unblock, ex)
    return esc(ex)
end

@doc(
"""
    @ctx(properties, expr)

Utility macro which expands to implement a subtype of `CompilationContext`. Also allow the user to easily configure the `debug` static tracing features and `show_after_inference`/`show_after_optimization` Boolean function flags.

Usage:
```julia
@ctx (b1::Bool, b2::Bool, b3::Bool) struct MyCtx
    fields...
end
```

Expands to:
```julia
struct MyCtx <: CompilationContext
    fields...
end
show_after_inference(::MyCtx) = b1
show_after_optimization(::MyCtx) = b2
debug(::MyCtx) = b3
```
""", :(@Mixtape.ctx))

struct MixtapeInterpreter{Ctx<:CompilationContext,Inner<:AbstractInterpreter} <:
       AbstractInterpreter
    ctx::Ctx
    inner::Inner
    errors::Any
    function MixtapeInterpreter(ctx::Ctx,
                                interp::Inner) where {Ctx<:CompilationContext,Inner}
        return new{Ctx,Inner}(ctx, interp, Any[])
    end
end
Base.push!(mxi::MixtapeInterpreter, e) = push!(mxi.errors, e)

get_world_counter(mxi::MixtapeInterpreter) = get_world_counter(mxi.inner)
get_inference_cache(mxi::MixtapeInterpreter) = get_inference_cache(mxi.inner)
InferenceParams(mxi::MixtapeInterpreter) = InferenceParams(mxi.inner)
OptimizationParams(mxi::MixtapeInterpreter) = OptimizationParams(mxi.inner)
Core.Compiler.may_optimize(mxi::MixtapeInterpreter) = true
Core.Compiler.may_compress(mxi::MixtapeInterpreter) = true
Core.Compiler.may_discard_trees(mxi::MixtapeInterpreter) = true
function Core.Compiler.add_remark!(mxi::MixtapeInterpreter, sv::InferenceState, msg)
    return Core.Compiler.add_remark!(mxi.inner, sv, msg)
end
lock_mi_inference(mxi::MixtapeInterpreter, mi::MethodInstance) = nothing
unlock_mi_inference(mxi::MixtapeInterpreter, mi::MethodInstance) = nothing
