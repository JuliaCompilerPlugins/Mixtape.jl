#####
##### Codegen/inference integration
#####

function code_cache(mxi::MixtapeInterpreter)
    return WorldView(get_cache(typeof(mxi.inner)), get_world_counter(mxi))
end

function cpu_invalidate(replaced, max_world)
    cache = get_cache(NativeInterpreter)
    invalidate(cache, replaced, max_world, 0)
    return nothing
end

function cpu_cache_lookup(mi, min_world, max_world)
    wvc = WorldView(get_cache(NativeInterpreter), min_world, max_world)
    return Core.Compiler.get(wvc, mi, nothing)
end

function cpu_infer(ctx, mi, min_world, max_world)
    wvc = WorldView(get_cache(NativeInterpreter), min_world, max_world)
    interp = MixtapeInterpreter(ctx, NativeInterpreter(min_world))
    ret = infer(wvc, mi, interp)
    if debug(ctx) && !isempty(interp.errors)
        println("\nEncountered the following non-critical errors during interception:")
        for k in interp.errors
            println(k)
        end
        println("\nThis may imply that your transform failed to operate on some calls.")
        println("\t\t\t  ______________\t\t\n")
    end
    return ret
end

function infer(wvc, mi, interp::MixtapeInterpreter)
    src = Core.Compiler.typeinf_ext_toplevel(interp, mi)
    ret = Any
    meth = mi.def
    try
        fn = resolve(GlobalRef(mi.def.module, mi.def.name))
        as = map(resolve, mi.specTypes.parameters[2:end])
        ret = Core.Compiler.return_type(interp, fn, as)
    catch e
        push!(interp, e)
    end
    @assert Core.Compiler.haskey(wvc, mi)
    ci = Core.Compiler.getindex(wvc, mi)
    if ci !== nothing && ci.inferred === nothing
        ci.inferred = src
    end
    return ret
end

struct InvokeException <: Exception
    name::Any
    mod::Any
    file::Any
    line::Any
end
function Base.show(io::IO, ie::InvokeException)
    print("@ ($(ie.file), L$(ie.line))\n")
    return print("| (Found call to invoke): $(ie.mod).$(ie.name)\n")
end

function detect_invoke(b, linfo)
    meth = linfo.def
    for (v, st) in b
        st isa Expr || continue
        st.head == :call || continue
        st.args[1] == invoke || continue
        return InvokeException(meth.name, meth.module, meth.file, meth.line)
    end
    return nothing
end

function mixtape_hook!(interp, result, mi, src)
    meth = mi.def
    try
        fn = resolve(GlobalRef(meth.module, meth.name))
        as = map(resolve, result.argtypes[2:end])
        if debug(interp.ctx)
            print("@ ($(meth.file), L$(meth.line))\n")
            print("| beg (inf): $(meth.module).$(fn)\n")
        end
        if allow(interp.ctx, meth.module, fn, as...)
            b = CodeInfoTools.Builder(src, length(result.argtypes[2:end]))
            b = transform(interp.ctx, b)
            e = detect_invoke(b, result.linfo)
            if e != nothing
                push!(interp, e)
            end
            src = finish(b)
            src = CodeInfoTools.clean!(src)
        end
    catch e
        push!(interp, e)
    end
    return src
end

# Replace usage sited of `retrieve_code_info`, OptimizationState is one such, but in all interesting use-cases
# it is derived from an InferenceState. There is a third one in `typeinf_ext` in case the module forbids inference.
function InferenceState(result::InferenceResult, cached::Bool, interp::MixtapeInterpreter)
    src = retrieve_code_info(result.linfo)
    mi = result.linfo
    src = mixtape_hook!(interp, result, mi, src)
    src === nothing && return nothing
    validate_code_in_debug_mode(result.linfo, src, "lowered")
    return InferenceState(result, src, cached, interp)
end

function cpu_compile(ctx, mi, world)
    params = Base.CodegenParams(; track_allocations=false, code_coverage=false,
        prefer_specsig=true,
        lookup=@cfunction(cpu_cache_lookup, Any, (Any, UInt, UInt)))

    # populate the cache
    if cpu_cache_lookup(mi, world, world) === nothing
        cpu_infer(ctx, mi, world, world)
    end

    # TODO: actual return type.
    rt = Any

    native_code = ccall(:jl_create_native, Ptr{Cvoid},
        (Vector{Core.MethodInstance}, Base.CodegenParams, Cint), [mi],
        params, 1) #=extern policy=#
    @assert native_code != C_NULL
    llvm_mod_ref = ccall(:jl_get_llvm_module, LLVM.API.LLVMModuleRef, (Ptr{Cvoid},),
        native_code)
    @assert llvm_mod_ref != C_NULL
    llvm_mod = LLVM.Module(llvm_mod_ref)

    # get the top-level code
    code = cpu_cache_lookup(mi, world, world)

    # get the top-level function index
    llvm_func_idx = Ref{Int32}(-1)
    llvm_specfunc_idx = Ref{Int32}(-1)
    ccall(:jl_get_function_id, Nothing, (Ptr{Cvoid}, Any, Ptr{Int32}, Ptr{Int32}),
        native_code, code, llvm_func_idx, llvm_specfunc_idx)
    @assert llvm_func_idx[] != -1
    @assert llvm_specfunc_idx[] != -1

    # get the top-level function
    llvm_func_ref = ccall(:jl_get_llvm_function, LLVM.API.LLVMValueRef,
        (Ptr{Cvoid}, UInt32), native_code, llvm_func_idx[] - 1)
    @assert llvm_func_ref != C_NULL
    llvm_func = LLVM.Function(llvm_func_ref)
    llvm_specfunc_ref = ccall(:jl_get_llvm_function, LLVM.API.LLVMValueRef,
        (Ptr{Cvoid}, UInt32), native_code, llvm_specfunc_idx[] - 1)
    @assert llvm_specfunc_ref != C_NULL
    llvm_specfunc = LLVM.Function(llvm_specfunc_ref)

    return (rt, llvm_specfunc, llvm_func, llvm_mod)
end

function method_instance(@nospecialize(f), @nospecialize(tt), world)
    # get the method instance
    meth = which(f, tt)
    sig = Base.signature_type(f, tt)::Type
    (ti, env) = ccall(:jl_type_intersection_with_env, Any, (Any, Any), sig,
        meth.sig)::Core.SimpleVector
    meth = Base.func_for_method_checked(meth, ti, env)
    return ccall(:jl_specializations_get_linfo, Ref{Core.MethodInstance},
        (Any, Any, Any, UInt), meth, ti, env, world)
end

function codegen(ctx::CompilationContext, @nospecialize(f), @nospecialize(tt);
        world=Base.get_world_counter())
    return cpu_compile(ctx, method_instance(f, tt, world), world)
end
