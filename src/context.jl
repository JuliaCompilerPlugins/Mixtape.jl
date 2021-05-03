#####
##### Compilation context
#####

# User-extended context allows parametrization of the pipeline through
# our subtype of AbstractInterpreter
abstract type CompilationContext end

struct NoContext <: CompilationContext end

@doc(
"""
    abstract type CompilationContext end

Parametrize the Mixtape pipeline by inheriting from `CompilationContext`. Similar to the context objects in [Cassette.jl](https://julia.mit.edu/Cassette.jl/stable/contextualdispatch.html). By using the interface methods [`transform`](@ref), [`preopt!`](@ref), and [`postopt!`](@ref) -- the user can control different parts of the compilation pipeline.
""", CompilationContext)

transform(ctx::CompilationContext, b) = b
transform(ctx::CompilationContext, b, sig) = transform(ctx, b)

@doc(
"""
    transform(ctx::CompilationContext, b::Core.CodeInfo)::Core.CodeInfo
    transform(ctx::CompilationContext, b::Core.CodeInfo, sig::Tuple)::Core.CodeInfo

User-defined transform which operates on lowered `CodeInfo` in the form of a `CodeInfoTools.Builder` object. There's two versions: (1) ignores the signature of the current method body under consideration and (2) provides the signature as `sig`.

Transforms might typically follow a simple "swap" format using `CodeInfoTools.Builder`:

```julia
function transform(::MyCtx, src)
    b = CodeInfoTools.Builder(b)
    for (k, st) in b
        b[k] = swap(st))
    end
    return CodeInfoTools.finish(b)
end
```

but more advanced formats are possible. For further utilities, please see [CodeInfoTools.jl](https://github.com/JuliaCompilerPlugins/CodeInfoTools.jl).
""", transform)

preopt!(ctx::CompilationContext, ir) = ir

@doc(
"""
    preopt!(ctx::CompilationContext, ir::Core.Compiler.IRCode)::Core.Compiler.IRCode

User-defined transform which operates on inferred `Core.Compiler.IRCode`. This transform operates **before** a set of optimizations which mimic Julia's pipeline.
""", preopt!)

postopt!(ctx::CompilationContext, ir) = ir

@doc(
"""
    postopt!(ctx::CompilationContext, ir::Core.Compiler.IRCode)::Core.Compiler.IRCode

User-defined transform which operates on inferred `Core.Compiler.IRCode`. This transform operates **after** a set of optimizations which mimic Julia's pipeline.
""", postopt!)

allow(f::C, args...) where {C <: CompilationContext} = false
function allow(ctx::CompilationContext, mod::Module, fn, args...)
    return allow(ctx, mod) || allow(ctx, fn, args...)
end

@doc(
"""
    allow(f::CompilationContext, args...)::Bool

Determines whether the user-defined [`transform`](@ref), [`preopt!`](@ref), and [`postopt!`](@ref) are allowed to look at a lowered `Core.CodeInfo` or `Core.Compiler.IRCode` instance.

The user is allowed to greenlight modules:

```julia
allow(::MyCtx, m::Module) == m == SomeModule
```

or even specific signatures

```julia
allow(::MyCtx, fn::typeof(rand), args...) = true
```
""", allow)
