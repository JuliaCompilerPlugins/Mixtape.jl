# API Documentation

Below is the API documentation for [Mixtape.jl](https://github.com/JuliaCompilerPlugins/Mixtape.jl)

```@meta
CurrentModule = Mixtape
```

## Interception interfaces

These interfaces parametrize the Mixtape pipeline and allow you to transform lowered code, optimize `Core.Compiler.IRCode`, and turn on debug printing. Similar to [Cassette.jl](https://github.com/JuliaLabs/Cassette.jl) -- to override these interfaces, users subtype `CompilationContext`.

```@docs
CompilationContext
allow
transform
preopt!
postopt!
show_after_inference
show_after_optimization
debug
@ctx
```

## Call interfaces

These interfaces allow you to apply the Mixtape pipeline and execute code with a linked in `OrcJIT` instance through [GPUCompiler.jl](https://github.com/JuliaGPU/GPUCompiler.jl).

```@docs
jit
@load_call_interface
```
