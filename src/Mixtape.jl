module Mixtape

using MacroTools: isexpr
using IRTools
using Core.Compiler
using Core.Compiler: MethodInstance, NativeInterpreter, CodeInfo, CodeInstance, WorldView, OptimizationState, Const, widenconst, MethodResultPure, CallMeta
import Core.Compiler.abstract_call_known
using LLVM
using LLVM.Interop

resolve(x) = x
resolve(gr::GlobalRef) = getproperty(gr.mod, gr.name)

# Cache
using Core.Compiler: WorldView

# Interpreter
import Core.Compiler: AbstractInterpreter, InferenceResult, InferenceParams, InferenceState, OptimizationParams
import Core.Compiler: get_world_counter, get_inference_cache, code_cache, lock_mi_inference, unlock_mi_inference
import Core.Compiler: retrieve_code_info, validate_code_in_debug_mode

# Optimizer
import Core.Compiler: optimize
#import Core.Compiler: CodeInfo, convert_to_ircode, copy_exprargs, slot2reg, compact!, coverage_enabled, adce_pass!
#import Core.Compiler: ssa_inlining_pass!, getfield_elim_pass!, type_lift_pass!, verify_ir, verify_linetable

# JIT
import GPUCompiler
import GPUCompiler: FunctionSpec

#####
##### Cache
#####

struct CodeCache
    dict::Dict{MethodInstance,Vector{CodeInstance}}
    callback::Function
    CodeCache(callback) = new(Dict{MethodInstance,Vector{CodeInstance}}(), callback)
end

function Base.show(io::IO, ::MIME"text/plain", cc::CodeCache)
    print(io, "CodeCache: ")
    for (mi, cis) in cc.dict
        println(io)
        print(io, "- ")
        show(io, mi)

        for ci in cis
            println(io)
            print(io, "  - ")
            print(io, (ci.min_world, ci.max_world))
        end
    end
end

function Core.Compiler.setindex!(cache::CodeCache, ci::CodeInstance, mi::MethodInstance)
    if !isdefined(mi, :callbacks)
        mi.callbacks = Any[cache.callback]
    else
        # Check if callback is present
        if all(cb -> cb !== cache.callback, mi.callbacks)
            push!(mi.callbacks, cache.callback)
        end
    end
    cis = get!(cache.dict, mi, CodeInstance[])
    push!(cis, ci)
end

const CACHE = Dict{DataType, CodeCache}()
get_cache(ai::DataType) = CACHE[ai]

#####
##### Setup execution engine
#####

# We have one global JIT and TM
const orc = Ref{LLVM.OrcJIT}()
const tm  = Ref{LLVM.TargetMachine}()

function __init__()
    CACHE[NativeInterpreter] = CodeCache(cpu_invalidate)

    opt_level = Base.JLOptions().opt_level
    if opt_level < 2
        optlevel = LLVM.API.LLVMCodeGenLevelNone
    elseif opt_level == 2
        optlevel = LLVM.API.LLVMCodeGenLevelDefault
    else
        optlevel = LLVM.API.LLVMCodeGenLevelAggressive
    end

    tm[] = LLVM.JITTargetMachine(optlevel=optlevel)
    LLVM.asm_verbosity!(tm[], true)

    orc[] = LLVM.OrcJIT(tm[]) # takes ownership of tm
    atexit() do
        LLVM.dispose(orc[])
    end
end

#####
##### Cache world view
#####

function Core.Compiler.haskey(wvc::WorldView{CodeCache}, mi::MethodInstance)
    Core.Compiler.get(wvc, mi, nothing) !== nothing
end

function Core.Compiler.get(wvc::WorldView{CodeCache}, mi::MethodInstance, default)
    cache = wvc.cache
    for ci in get!(cache.dict, mi, CodeInstance[])
        if ci.min_world <= wvc.worlds.min_world && wvc.worlds.max_world <= ci.max_world
            # TODO: if (code && (code == jl_nothing || jl_ir_flag_inferred((jl_array_t*)code)))
            return ci
        end
    end

    return default
end

function Core.Compiler.getindex(wvc::WorldView{CodeCache}, mi::MethodInstance)
    r = Core.Compiler.get(wvc, mi, nothing)
    r === nothing && throw(KeyError(mi))
    return r::CodeInstance
end

Core.Compiler.setindex!(wvc::WorldView{CodeCache}, ci::CodeInstance, mi::MethodInstance) =
Core.Compiler.setindex!(wvc.cache, ci, mi)

#####
##### Cache invalidation
#####

function invalidate(cache::CodeCache, replaced::MethodInstance, max_world, depth)
    cis = get(cache.dict, replaced, nothing)
    if cis === nothing
        return
    end
    for ci in cis
        if ci.max_world == ~0 % Csize_t
            @assert ci.min_world - 1 <= max_world "attempting to set illogical constraints"
            ci.max_world = max_world
        end
        @assert ci.max_world <= max_world
    end

    # recurse to all backedges to update their valid range also
    if isdefined(replaced, :backedges)
        backedges = replaced.backedges
        # Don't touch/empty backedges `invalidate_method_instance` in C will do that later
        # replaced.backedges = Any[]
        for mi in backedges
            invalidate(cache, mi, max_world, depth + 1)
        end
    end
end

#####
##### MixtapeInterpreter
#####

abstract type CompilationContext end
struct Fallback <: CompilationContext end
allow_transform(f::CompilationContext, fn::Function) = false
allow_transform(f::CompilationContext, m::Module) = false
show_after_inference(f::CompilationContext) = false
show_after_optimization(f::CompilationContext) = false
debug(f::CompilationContext) = false
transform(ctx::CompilationContext, ir) = return ir
check(ctx::CompilationContext, m::Module, fn::Function) = allow_transform(ctx, m) || allow_transform(ctx, fn)
check(ctx::CompilationContext, m, fn) = false

export CompilationContext, transform, allow_transform, show_after_inference, show_after_optimization, debug

struct MixtapeInterpreter{Ctx <: CompilationContext, Inner<:AbstractInterpreter} <: AbstractInterpreter
    ctx::Ctx
    inner::Inner
    errors
    MixtapeInterpreter(ctx::Ctx, interp::Inner) where {Ctx <: CompilationContext, Inner} = new{Ctx, Inner}(ctx, interp, Any[])
end
Base.push!(mxi::MixtapeInterpreter, e) = push!(mxi.errors, e)

get_world_counter(mxi::MixtapeInterpreter) =  get_world_counter(mxi.inner)
get_inference_cache(mxi::MixtapeInterpreter) = get_inference_cache(mxi.inner) 
InferenceParams(mxi::MixtapeInterpreter) = InferenceParams(mxi.inner)
OptimizationParams(mxi::MixtapeInterpreter) = OptimizationParams(mxi.inner)
Core.Compiler.may_optimize(mxi::MixtapeInterpreter) = true
Core.Compiler.may_compress(mxi::MixtapeInterpreter) = true
Core.Compiler.may_discard_trees(mxi::MixtapeInterpreter) = true
Core.Compiler.add_remark!(mxi::MixtapeInterpreter, sv::InferenceState, msg) = Core.Compiler.add_remark!(mxi.inner, sv, msg)
lock_mi_inference(mxi::MixtapeInterpreter, mi::MethodInstance) = nothing
unlock_mi_inference(mxi::MixtapeInterpreter, mi::MethodInstance) = nothing

#####
##### Codegen/inference integration
#####

code_cache(mxi::MixtapeInterpreter) = WorldView(get_cache(typeof(mxi.inner)), get_world_counter(mxi))

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
        println("Encountered the following non-critical errors during interception:")
        for k in interp.errors
            display(k)
        end
        println("This may imply that your transform failed to operate on some calls.")
    end
    return ret
end

uncompressed_ir(m::Method) = isdefined(m, :source) ? _uncompressed_ir(m, m.source) :
isdefined(m, :generator) ? error("Method is @generated; try `code_lowered` instead.") :
error("Code for this Method is not available.")
_uncompressed_ir(m::Method, s::CodeInfo) = copy(s)
_uncompressed_ir(m::Method, s::Array{UInt8,1}) = ccall(:jl_uncompress_ir, Any, (Any, Ptr{Cvoid}, Any), m, C_NULL, s)::CodeInfo
_uncompressed_ir(ci::Core.CodeInstance, s::Array{UInt8,1}) = ccall(:jl_uncompress_ir, Any, (Any, Any, Any), ci.def.def::Method, ci, s)::CodeInfo

function update!(ci::CodeInfo, ir::Core.Compiler.IRCode)
    Core.Compiler.replace_code_newstyle!(ci, ir, length(ir.argtypes)-1)
    ci.inferred = false
    ci.ssavaluetypes = length(ci.code)
    IRTools.slots!(ci)
    fill!(ci.slotflags, 0)
    return ci
end

function update!(ci::CodeInfo, ir::IRTools.IR)
    if ir.meta isa IRTools.Inner.Meta
        ci.method_for_inference_limit_heuristics = ir.meta.method
        if isdefined(ci, :edges)
            ci.edges = Core.MethodInstance[ir.meta.instance]
        end
    end
    update!(ci, Core.Compiler.IRCode(IRTools.slots!(ir)))
end

function prepare_ir!(ir::IRTools.IR; type = Any)
    for (v, st) in ir
        isexpr(st.expr) || continue
        ir[v] = IRTools.stmt(Expr(st.expr.head, map(resolve, st.expr.args)...); type = type)
    end
    ir
end

function infer(wvc, mi, interp)
    src = Core.Compiler.typeinf_ext_toplevel(interp, mi)
    try
        fn = resolve(GlobalRef(mi.def.module, mi.def.name))
            if check(interp.ctx, mi.def.module, fn) && show_after_inference(interp.ctx)
                println("(Inferred) $fn in $(mi.def.module)")
                    display(src)
                end
            catch e
                push!(interp, e)
            end
            @assert Core.Compiler.haskey(wvc, mi)
            ci = Core.Compiler.getindex(wvc, mi)
            if ci !== nothing && ci.inferred === nothing
                ci.inferred = src
            end
            return
        end

        # Workaround for what appears to be a Base bug
        untvar(t::TypeVar) = t.ub
        untvar(x) = x

        function meta(T; types = T, world = Base.get_world_counter())
            T isa UnionAll && return nothing
            F = T.parameters[1]
            F == typeof(invoke) && return invoke_meta(T; world = world)
            F isa DataType && (F.name.module === Core.Compiler ||
                                   F <: Core.Builtin ||
                                   F <: Core.Builtin) && return nothing
            _methods = Base._methods_by_ftype(T, -1, world)
            length(_methods) == 0 && return nothing
            type_signature, sps, method = last(_methods)
            sps = Core.svec(map(untvar, sps)...)
            @static if VERSION >= v"1.2-"
                mi = Core.Compiler.specialize_method(method, types, sps)
                ci = Base.isgenerated(mi) ? Core.Compiler.get_staged(mi) : Base.uncompressed_ast(method)
            else
                mi = Core.Compiler.code_for_method(method, types, sps, world, false)
                ci = Base.isgenerated(mi) ? Core.Compiler.get_staged(mi) : Base.uncompressed_ast(mi)
            end
            Base.Meta.partially_inline!(ci.code, [], method.sig, Any[sps...], 0, 0, :propagate)
            IRTools.Meta(method, mi, ci, method.nargs, sps)
        end

        # Replace usage sited of `retrieve_code_info`, OptimizationState is one such, but in all interesting use-cases
        # it is derived from an InferenceState. There is a third one in `typeinf_ext` in case the module forbids inference.
        function InferenceState(result::InferenceResult, cached::Bool, interp::MixtapeInterpreter)
            src = retrieve_code_info(result.linfo)
            try
                fn = resolve(GlobalRef(result.linfo.def.module, result.linfo.def.name))
                    m = meta(result.linfo.def.sig)
                    if !=(m, nothing) && check(interp.ctx, result.linfo.def.module, fn)
                        ir = prepare_ir!(IRTools.IR(m))
                        ir = transform(interp.ctx, ir)
                        update!(src, ir)
                    end
                catch e
                    push!(interp, e)
                end
                src === nothing && return nothing
                validate_code_in_debug_mode(result.linfo, src, "lowered")
                return InferenceState(result, src, cached, interp)
            end

            function cpu_compile(ctx, mi, world)
                params = Base.CodegenParams(;
                    track_allocations  = false,
                    code_coverage      = false,
                    prefer_specsig     = true,
                    lookup             = @cfunction(cpu_cache_lookup, Any, (Any, UInt, UInt)))

                # generate IR
                # TODO: Instead of extern policy integrate with Orc JIT

                # populate the cache
                if cpu_cache_lookup(mi, world, world) === nothing
                    cpu_infer(ctx, mi, world, world)
                end

                native_code = ccall(:jl_create_native, Ptr{Cvoid},
                    (Vector{Core.MethodInstance}, Base.CodegenParams, Cint),
                    [mi], params, #=extern policy=# 1)
                @assert native_code != C_NULL
                llvm_mod_ref = ccall(:jl_get_llvm_module, LLVM.API.LLVMModuleRef,
                    (Ptr{Cvoid},), native_code)
                @assert llvm_mod_ref != C_NULL
                llvm_mod = LLVM.Module(llvm_mod_ref)

                # get the top-level code
                code = cpu_cache_lookup(mi, world, world)

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

            function codegen(ctx::CompilationContext, @nospecialize(f), @nospecialize(tt); world = Base.get_world_counter())
                return cpu_compile(ctx, method_instance(f, tt, world), world)
            end

            #####
            ##### Optimize
            #####

            import Core.Compiler: optimize

            function optimize(interp::MixtapeInterpreter, opt::OptimizationState, params::OptimizationParams, @nospecialize(result))
                nargs = Int(opt.nargs) - 1
                ir = run_passes(opt.src, nargs, opt)
                if show_after_optimization(interp.ctx)
                    fn = resolve(GlobalRef(opt.linfo.def.module, opt.linfo.def.name))
                        println("(Optimized) $fn in $(opt.linfo.def.module)")
                            display(ir)
                        end
                        Core.Compiler.finish(opt, params, ir, result)
                    end

                    import Core.Compiler: CodeInfo, convert_to_ircode, copy_exprargs, slot2reg, compact!, coverage_enabled, adce_pass!
                    import Core.Compiler: ssa_inlining_pass!, getfield_elim_pass!, type_lift_pass!, verify_ir, verify_linetable

                    function run_passes(ci::CodeInfo, nargs::Int, sv::OptimizationState)
                        preserve_coverage = coverage_enabled(sv.mod)
                        ir = convert_to_ircode(ci, copy_exprargs(ci.code), preserve_coverage, nargs, sv)
                        ir = slot2reg(ir, ci, nargs, sv)
                        # TODO: Domsorting can produce an updated domtree - no need to recompute here
                        ir = compact!(ir)
                        ir = ssa_inlining_pass!(ir, ir.linetable, sv.inlining, ci.propagate_inbounds)
                        ir = compact!(ir)
                        ir = getfield_elim_pass!(ir) # SROA
                        ir = adce_pass!(ir)
                        ir = type_lift_pass!(ir)
                        ir = compact!(ir)
                        verify_ir(ir)
                        verify_linetable(ir.linetable)
                        return ir
                    end

                    #####
                    ##### LLVM optimization pipeline
                    #####

                    # https://github.com/JuliaLang/julia/blob/2eb5da0e25756c33d1845348836a0a92984861ac/src/aotcompile.cpp#L603
                    function addTargetPasses!(pm, tm)
                        add_library_info!(pm, LLVM.triple(tm))
                        add_transform_info!(pm, tm)
                    end

                    # TODO (Missing C-API):
                    #  - https://reviews.llvm.org/D86764 adds InstSimplify
                    #  - createDivRemPairs
                    #  - createLoopLoadEliminationPass
                    #  - createVectorCombinePass
                    # TODO (Missing LLVM.jl)
                    #  - AggressiveInstCombinePass

                    # https://github.com/JuliaLang/julia/blob/2eb5da0e25756c33d1845348836a0a92984861ac/src/aotcompile.cpp#L620
                    function addOptimizationPasses!(pm, tm, opt_level, lower_intrinsics, dump_native)
                        constant_merge!(pm)
                        if opt_level < 2
                            error("opt_level less than 2 not supported")
                            return
                        end

                        propagate_julia_addrsp!(pm)
                        scoped_no_alias_aa!(pm)
                        type_based_alias_analysis!(pm)
                        if opt_level >= 3
                            basic_alias_analysis!(pm)
                        end
                        cfgsimplification!(pm)
                        dce!(pm)
                        scalar_repl_aggregates!(pm)

                        # mem_cpy_opt!(pm)

                        always_inliner!(pm) # Respect always_inline

                        # Running `memcpyopt` between this and `sroa` seems to give `sroa` a hard time
                        # merging the `alloca` for the unboxed data and the `alloca` created by the `alloc_opt`
                        # pass.

                        alloc_opt!(pm)
                        # consider AggressiveInstCombinePass at optlevel > 2

                        instruction_combining!(pm)
                        cfgsimplification!(pm)
                        if dump_native
                            error("dump_native not supported")
                            # TODO: createMultiversoningPass
                        end
                        scalar_repl_aggregates!(pm)
                        instruction_combining!(pm) # TODO: createInstSimplifyLegacy
                        jump_threading!(pm)

                        reassociate!(pm)

                        early_cse!(pm)

                        # Load forwarding above can expose allocations that aren't actually used
                        # remove those before optimizing loops.
                        alloc_opt!(pm)
                        loop_rotate!(pm)
                        # moving IndVarSimplify here prevented removing the loop in perf_sumcartesian(10:-1:1)
                        loop_idiom!(pm)

                        # TODO: Polly (Quo vadis?)

                        # LoopRotate strips metadata from terminator, so run LowerSIMD afterwards
                        lower_simdloop!(pm) # Annotate loop marked with "loopinfo" as LLVM parallel loop
                        licm!(pm)
                        julia_licm!(pm)
                        # Subsequent passes not stripping metadata from terminator
                        instruction_combining!(pm) # TODO: createInstSimplifyLegacy
                        ind_var_simplify!(pm)
                        loop_deletion!(pm)
                        loop_unroll!(pm) # TODO: in Julia createSimpleLoopUnroll

                        # Run our own SROA on heap objects before LLVM's
                        alloc_opt!(pm)
                        # Re-run SROA after loop-unrolling (useful for small loops that operate,
                        # over the structure of an aggregate)
                        scalar_repl_aggregates!(pm)
                        instruction_combining!(pm) # TODO: createInstSimplifyLegacy

                        gvn!(pm)
                        mem_cpy_opt!(pm)
                        sccp!(pm)

                        # Run instcombine after redundancy elimination to exploit opportunities
                        # opened up by them.
                        # This needs to be InstCombine instead of InstSimplify to allow
                        # loops over Union-typed arrays to vectorize.
                        instruction_combining!(pm)
                        jump_threading!(pm)
                        dead_store_elimination!(pm)

                        # More dead allocation (store) deletion before loop optimization
                        # consider removing this:
                        alloc_opt!(pm)

                        # see if all of the constant folding has exposed more loops
                        # to simplification and deletion
                        # this helps significantly with cleaning up iteration
                        cfgsimplification!(pm)
                        loop_deletion!(pm)
                        instruction_combining!(pm)
                        loop_vectorize!(pm)
                        # TODO: createLoopLoadEliminationPass
                        cfgsimplification!(pm)
                        slpvectorize!(pm)
                        # might need this after LLVM 11:
                        # TODO: createVectorCombinePass()

                        aggressive_dce!(pm)

                        if lower_intrinsics
                            # LowerPTLS removes an indirect call. As a result, it is likely to trigger
                            # LLVM's devirtualization heuristics, which would result in the entire
                            # pass pipeline being re-exectuted. Prevent this by inserting a barrier.
                            barrier_noop!(pm)
                            lower_exc_handlers!(pm)
                            gc_invariant_verifier!(pm, false)
                            # Needed **before** LateLowerGCFrame on LLVM < 12
                            # due to bug in `CreateAlignmentAssumption`.
                            remove_ni!(pm)
                            late_lower_gc_frame!(pm)
                            final_lower_gc!(pm)
                            # We need these two passes and the instcombine below
                            # after GC lowering to let LLVM do some constant propagation on the tags.
                            # and remove some unnecessary write barrier checks.
                            gvn!(pm)
                            sccp!(pm)
                            # Remove dead use of ptls
                            dce!(pm)
                            lower_ptls!(pm, dump_native)
                            instruction_combining!(pm)
                            # Clean up write barrier and ptls lowering
                            cfgsimplification!(pm)
                        else
                            remove_ni!(pm)
                        end
                        combine_mul_add!(pm)
                        # TODO: createDivRemPairs[]
                    end

                    function addMachinePasses!(pm, tm)
                        demote_float16!(pm)
                        gvn!(pm)
                    end

                    function run_pipeline!(mod::LLVM.Module)
                        LLVM.ModulePassManager() do pm
                            addTargetPasses!(pm, tm[])
                            addOptimizationPasses!(pm, tm[], 3, true, false)
                            addMachinePasses!(pm, tm[])
                            run!(pm, mod)
                        end
                    end

                    #####
                    ##### JIT
                    #####

                    import GPUCompiler
                    import GPUCompiler: FunctionSpec

                    struct Entry{F, TT}
                        f::F
                        specfunc::Ptr{Cvoid}
                        func::Ptr{Cvoid}
                    end

                    # Slow ABI
                    function __call(entry::Entry{F, TT}, args::TT) where {F, TT} 
                        args = Any[args...]
                        ccall(entry.func, Any, (Any, Ptr{Any}, Int32), entry.f, args, length(args))
                    end

                    (entry::Entry)(args...) = __call(entry, args)

                    const compiled_cache = Dict{UInt, Any}()

                    function jit(ctx, f::F,tt::TT=Tuple{}) where {F, TT<:Type}
                        fspec = FunctionSpec(f, tt, #=kernel=# false, #=name=# nothing)
                        GPUCompiler.cached_compilation(compiled_cache, fspec -> _jit(ctx, fspec), _link, fspec)::Entry{F, tt}
                    end

                    function _link(@nospecialize(fspec::FunctionSpec), (llvm_mod, func_name, specfunc_name))
                        # Now invoke the JIT
                        jitted_mod = compile!(orc[], llvm_mod)

                        specfunc_addr = addressin(orc[], jitted_mod, specfunc_name)
                        specfunc_ptr  = pointer(specfunc_addr)

                        func_addr = addressin(orc[], jitted_mod, func_name)
                        func_ptr  = pointer(func_addr)

                        if  specfunc_ptr === C_NULL || func_ptr === C_NULL
                            @error "Compilation error" fspec specfunc_ptr func_ptr
                        end

                        return Entry{typeof(fspec.f), fspec.tt}(fspec.f, specfunc_ptr, func_ptr)
                    end

                    # actual compilation
                    function _jit(ctx, @nospecialize(fspec::FunctionSpec))
                        llvm_specfunc, llvm_func, llvm_mod = codegen(ctx, fspec.f, fspec.tt)

                        specfunc_name = LLVM.name(llvm_specfunc)
                        func_name = LLVM.name(llvm_func)

                        # set linkage to extern visible
                        # otherwise `addressin` won't find them
                        linkage!(llvm_func, LLVM.API.LLVMExternalLinkage)
                        linkage!(llvm_specfunc, LLVM.API.LLVMExternalLinkage)

                        run_pipeline!(llvm_mod)

                        return (llvm_mod, func_name, specfunc_name)
                    end

                end # module
