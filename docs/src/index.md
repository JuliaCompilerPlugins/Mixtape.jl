# API Documentation

Below is the API documentation for [Mixtape.jl](https://github.com/JuliaCompilerPlugins/Mixtape.jl)

```@meta
CurrentModule = Mixtape
```

## Interception interfaces

These interfaces parametrize the Mixtape pipeline and allow you to transform lowered code and insert optimizations. Similar to [Cassette.jl](https://github.com/JuliaLabs/Cassette.jl) -- to override these interfaces, users subtype `CompilationContext` and associated interfaces.

```@docs
CompilationContext
allow
transform
optimize!
```

## Call and codegen interfaces

These interfaces allow you to apply the Mixtape pipeline with a variety of targets, including:

1. Emission of inferred and (unoptimized or optimized) `Core.CodeInfo` for consumption by alternative code generation backends (like [Brutus](https://github.com/JuliaLabs/brutus/tree/master)
2. Execution of generated code with a linked in `OrcJIT` instance through [GPUCompiler.jl](https://github.com/JuliaGPU/GPUCompiler.jl).

The current `@load_abi` interface creates a special `call` function in the toplevel module scope which allows the user to access a `@generated` ABI. `call` can be used to execute code using the Mixtape pipeline without first creating a callable entry with `jit`.

!!! warning
    The `call` ABI is currently "slow" -- it costs an array allocation (for arguments which you will pass over the line in memory). In the future, this will be changed to a _fast ABI_ -- but the current _slow ABI_ is mostly stable and useful for prototyping.

```@docs
jit
emit
@load_abi
```
