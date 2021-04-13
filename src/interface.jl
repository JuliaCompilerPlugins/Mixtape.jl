#####
##### jit/call interface with GPUCompiler
#####

struct MixtapeCompilerTarget <: AbstractCompilerTarget end
struct MixtapeCompilerParams <: AbstractCompilerParams
    ctx::Any
end

struct Entry{F,RT,TT}
    f::F
    specfunc::Ptr{Cvoid}
    func::Ptr{Cvoid}
end

const jit_compiled_cache = Dict{UInt,Any}()

function jit(ctx::CompilationContext, f::F, tt::TT=Tuple{}) where {F,TT<:Type}
    fspec = FunctionSpec(f, tt, false, nothing) #=name=#
    job = CompilerJob(MixtapeCompilerTarget(), fspec, MixtapeCompilerParams(ctx))
    return GPUCompiler.cached_compilation(jit_compiled_cache, job, _jit, _jitlink)
end

@doc(
"""
    jit(ctx::CompilationContext, f::F, tt::TT = Tuple{}) where {F, TT <: Type}

Compile and specialize a method instance for signature `Tuple{f, tt.parameters...}` with pipeline parametrized by `ctx`.

Returns a callable "thunk" `Entry{F, RT, TT}` where `RT` is the return type of the instance after inference.
""", jit)

function _jitlink(job::CompilerJob, (rt, llvm_mod, func_name, specfunc_name))
    fspec = job.source
    jitted_mod = compile!(orc[], llvm_mod)
    specfunc_addr = addressin(orc[], jitted_mod, specfunc_name)
    specfunc_ptr = pointer(specfunc_addr)
    func_addr = addressin(orc[], jitted_mod, func_name)
    func_ptr = pointer(func_addr)
    if specfunc_ptr === C_NULL || func_ptr === C_NULL
        @error "Compilation error" fspec specfunc_ptr func_ptr
    end
    return Entry{typeof(fspec.f),rt,fspec.tt}(fspec.f, specfunc_ptr, func_ptr)
end

function _jit(job::CompilerJob)
    rt, llvm_specfunc, llvm_func, llvm_mod = codegen(job.params.ctx, job.source.f, job.source.tt)
    specfunc_name = LLVM.name(llvm_specfunc)
    func_name = LLVM.name(llvm_func)
    linkage!(llvm_func, LLVM.API.LLVMExternalLinkage)
    linkage!(llvm_specfunc, LLVM.API.LLVMExternalLinkage)
    run_pipeline!(llvm_mod)
    return (rt, llvm_mod, func_name, specfunc_name)
end

#####
##### Call interface
#####

@generated function (entry::Entry{F,RT,TT})(args...) where {F,RT,TT}
    expr = quote
        args = Any[args...]
        ccall(entry.func, Any, (Any, Ptr{Any}, Int32), entry.f, args, length(args))
    end
    return expr
end

macro load_call_interface()
    expr = quote
        function cached_call(entry::Mixtape.Entry{F,RT,TT}, args...) where {F,RT,TT}

            # TODO: Fast ABI.
            #ccall(entry.func, Any, (Any, $(nargs...), ), entry.f, $(_args...))

            # Slow ABI. Requires an array allocation.
            expr = quote
                vargs = Any[args...]
                ccall($(entry.func), Any, (Any, Ptr{Any}, Int32), $(entry.f), vargs,
                      $(length(args)))
            end
            return expr
        end

        @generated function call(ctx::Mixtape.CompilationContext, f::F, args...) where {F}
            TT = Tuple{args...}
            entry = Mixtape.jit(ctx(), F.instance, TT)
            return cached_call(entry, args...)
        end
    end
    return esc(expr)
end

@doc(
"""
    @load_call_interface()

A macro which expands to load a generated function `call` into the scope of the calling module. This generated function can be applied to signature argument types `Tuple{ctx<:CompilationContext, f<:Function, args...}`. `call` then creates a new instance of `ctx` and calls `Mixtape.jit` -- it then caches a `ccall` which calls a function pointer to the GPUCompiler-compiled LLVM module.

The `call` interface currently uses a slow ABI `ccall` -- which costs an array allocation for each toplevel `call`. This allocation is required to construct a `Vector{Any}` for the arguments and pass a pointer to it over the line, where the call unboxes each argument.
""", :(@Mixtape.load_call_interface))
