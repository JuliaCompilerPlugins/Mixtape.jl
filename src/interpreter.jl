#####
##### MixtapeInterpreter
#####

struct MixtapeInterpreter{Ctx<:CompilationContext,
                          Inner<:AbstractInterpreter} <: AbstractInterpreter
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
@static if VERSION >= v"1.7.0-DEV.577"
    Core.Compiler.verbose_stmt_info(interp::MixtapeInterpreter) = false
end

#####
##### Pre-inference
#####

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

function _debug_prehook(interp::MixtapeInterpreter, result, mi, src)
    meth = mi.def
    try
        fn = resolve(GlobalRef(meth.module, meth.name))
        as = map(resolve, result.argtypes[2:end])
        if debug(interp.ctx)
            print("@ ($(meth.file), L$(meth.line))\n")
            print("| beg (inf): $(meth.module).$(fn)\n")
        end
    catch e
        push!(interp, e)
    end
end

function custom_pass!(interp::MixtapeInterpreter, result::InferenceResult, mi::Core.MethodInstance, src)
    src === nothing && return src
    mi.specTypes isa UnionAll && return src
    sig = Tuple(mi.specTypes.parameters)
    if sig[1] <: Function && isdefined(sig[1], :instance)
        fn = sig[1].instance
    else
        fn = sig[1]
    end
    as = map(resolve, sig[2 : end])
    debug(interp.ctx) && _debug_prehook(interp, result, mi, src)
    if allow(interp.ctx, mi.def.module, fn, as...)
        p = CodeInfoTools.Pipe(src)
        p = transform(interp.ctx, p)
        e = detect_invoke(p, result.linfo)
        if e != nothing
            push!(interp, e)
        end
        src = finish(p)
    end
    return src
end

function InferenceState(result::InferenceResult, cached::Bool, interp::MixtapeInterpreter)
    src = retrieve_code_info(result.linfo)
    mi = result.linfo
    src = custom_pass!(interp, result, mi, src)
    src === nothing && return nothing
    validate_code_in_debug_mode(result.linfo, src, "lowered")
    return InferenceState(result, src, cached, interp)
end

#####
##### Optimize
#####

function julia_passes(ir::Core.Compiler.IRCode, ci::CodeInfo, sv::OptimizationState)
    ir = compact!(ir)
    ir = ssa_inlining_pass!(ir, ir.linetable, sv.inlining, ci.propagate_inbounds)
    ir = compact!(ir)
    ir = getfield_elim_pass!(ir) # SROA
    ir = adce_pass!(ir)
    ir = type_lift_pass!(ir)
    ir = compact!(ir)
    return ir
end

@static if VERSION >= v"1.7.0-DEV.662"
    using Core.Compiler: finish as _finish
else
    function _finish(interp::AbstractInterpreter, opt::OptimizationState,
                     params::OptimizationParams, ir, @nospecialize(result))
        return Core.Compiler.finish(opt, params, ir, result)
    end
end

function _debug_prehook(interp::MixtapeInterpreter, mi, opt)
    meth = mi.def
    try
        fn = resolve(GlobalRef(mi.def.module, mi.def.name))
        as = map(resolve, mi.specTypes.parameters[2:end])
        if allow(interp.ctx, mi.def.module, fn, as...) && show_after_inference(interp.ctx)
            print("@ ($(meth.file), L$(meth.line))\n")
            print("| (inf) $(mi.def.module).$fn\n")
            println(opt.src)
        end
        if debug(interp.ctx)
            println("@ ($(meth.file), L$(meth.line))")
            println("| end (inf): $(meth.module).$(fn)")
            println("@ ($(meth.file), L$(meth.line))")
            println("| beg (opt): $(meth.module).$(fn)")
        end
    catch e
        push!(interp, e)
    end
end

function _debug_posthook(interp::MixtapeInterpreter, mi, opt; stage = "opt")
    meth = mi.def
    try 
        fn = resolve(GlobalRef(mi.def.module, mi.def.name))
        as = map(resolve, mi.specTypes.parameters[2:end])
        if allow(interp.ctx, mi.def.module, fn, as...) &&
           show_after_optimization(interp.ctx)
            print("@ ($(meth.file), L$(meth.line))\n")
            print("| (opt) $(opt.linfo.def.module).$fn\n")
            println(opt.src)
        end
        if debug(interp.ctx)
            println("@ ($(meth.file), L$(meth.line))")
            println("| end (opt): $(meth.module).$(fn)")
        end
    catch e
        push!(interp, e)
    end
end

function before_pass!(interp::MixtapeInterpreter, mi::Core.MethodInstance, ir::Core.Compiler.IRCode, opt::OptimizationState)
    mi.specTypes isa UnionAll && return ir
    sig = Tuple(mi.specTypes.parameters)
    if sig[1] <: Function && isdefined(sig[1], :instance)
        fn = sig[1].instance
    else
        fn = sig[1]
    end
    as = map(resolve, sig[2 : end])
    debug(interp.ctx) && _debug_prehook(interp, mi, opt)
    if allow(interp.ctx, mi.def.module, fn, as...)
        ir = preopt!(interp.ctx, ir)
    end
    return ir
end

function after_pass!(interp::MixtapeInterpreter, mi::Core.MethodInstance, ir::Core.Compiler.IRCode, opt::OptimizationState)
    mi.specTypes isa UnionAll && return ir
    sig = Tuple(mi.specTypes.parameters)
    if sig[1] <: Function && isdefined(sig[1], :instance)
        fn = sig[1].instance
    else
        fn = sig[1]
    end
    as = map(resolve, sig[2 : end])
    if allow(interp.ctx, mi.def.module, fn, as...)
        ir = postopt!(interp.ctx, ir)
    end
    return ir
end

function optimize(interp::MixtapeInterpreter, opt::OptimizationState,
                  params::OptimizationParams, @nospecialize(result))
    nargs = Int(opt.nargs) - 1
    mi = opt.linfo
    meth = mi.def
    preserve_coverage = coverage_enabled(opt.mod)
    ir = convert_to_ircode(opt.src, copy_exprargs(opt.src.code), preserve_coverage, nargs, opt)
    ir = slot2reg(ir, opt.src, nargs, opt)
    ir = before_pass!(interp, mi, ir, opt)
    ir = julia_passes(ir, opt.src, opt)
    ir = after_pass!(interp, mi, ir, opt)
    ir = julia_passes(ir, opt.src, opt)
    debug(interp.ctx) && _debug_posthook(interp, mi, opt)
    verify_ir(ir)
    verify_linetable(ir.linetable)
    return _finish(interp, opt, params, ir, result)
end
