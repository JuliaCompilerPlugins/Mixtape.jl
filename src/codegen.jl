#####
##### Codegen
#####

function cpu_compile(method_instance::Core.MethodInstance, world)
    params = Base.CodegenParams(;
                track_allocations  = false,
                code_coverage      = false,
                prefer_specsig     = true,
                lookup             = @cfunction(cpu_cache_lookup, Any, (Any, UInt, UInt)))

    # generate IR
    # TODO: Instead of extern policy integrate with Orc JIT

    # populate the cache
    if cpu_cache_lookup(method_instance, world, world) === nothing
        cpu_infer(method_instance, world, world)
    end

    native_code = ccall(:jl_create_native, Ptr{Cvoid},
                    (Vector{Core.MethodInstance}, Base.CodegenParams, Cint),
                    [method_instance], params, #=extern policy=# 1)
    @assert native_code != C_NULL
    llvm_mod_ref = ccall(:jl_get_llvm_module, LLVM.API.LLVMModuleRef,
                     (Ptr{Cvoid},), native_code)
    @assert llvm_mod_ref != C_NULL
    llvm_mod = LLVM.Module(llvm_mod_ref)

    # get the top-level code
    code = cpu_cache_lookup(method_instance, world, world)

    # get the top-level function index
    llvm_func_idx = Ref{Int32}(-1)
    llvm_specfunc_idx = Ref{Int32}(-1)
    ccall(:jl_get_function_id, Nothing,
        (Ptr{Cvoid}, Any, Ptr{Int32}, Ptr{Int32}),
        native_code, code, llvm_func_idx, llvm_specfunc_idx)
    @assert llvm_func_idx[] != -1
    @assert llvm_specfunc_idx[] != -1

    # get the top-level function)
    llvm_func_ref = ccall(:jl_get_llvm_function, LLVM.API.LLVMValueRef,
                    (Ptr{Cvoid}, UInt32), native_code, llvm_func_idx[]-1)
    @assert llvm_func_ref != C_NULL
    llvm_func = LLVM.Function(llvm_func_ref)
    llvm_specfunc_ref = ccall(:jl_get_llvm_function, LLVM.API.LLVMValueRef,
                        (Ptr{Cvoid}, UInt32), native_code, llvm_specfunc_idx[]-1)
    @assert llvm_specfunc_ref != C_NULL
    llvm_specfunc = LLVM.Function(llvm_specfunc_ref)

    return llvm_specfunc, llvm_func, llvm_mod
end

function method_instance(@nospecialize(f), @nospecialize(tt), world)
    # get the method instance
    meth = which(f, tt)
    sig = Base.signature_type(f, tt)::Type
    (ti, env) = ccall(:jl_type_intersection_with_env, Any,
                      (Any, Any), sig, meth.sig)::Core.SimpleVector
    meth = Base.func_for_method_checked(meth, ti, env)
    return ccall(:jl_specializations_get_linfo, Ref{Core.MethodInstance},
                 (Any, Any, Any, UInt), meth, ti, env, world)
end

function codegen(@nospecialize(f), @nospecialize(tt), world = Base.get_world_counter())
    cpu_compile(method_instance(f, tt, world), world)
end
