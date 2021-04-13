#####
##### TracingInterpreter
#####

struct TracingInterpreter{Ctx<:CompilationContext,Inner<:AbstractInterpreter} <: AbstractInterpreter
    ctx::Ctx
    inner::Inner
    errors::Any
    function TracingInterpreter(interp::MixtapeInterpreter)
        world = interp.inner.world
        ctx = interp.ctx
        new = NativeInterpreter(Base.get_world_counter())
        new{typeof(ctx), NativeInterpreter}(ctx, new, Any[])
    end
end
Base.push!(tr::TracingInterpreter, e) = push!(tr.errors, e)

get_world_counter(tr::TracingInterpreter) = get_world_counter(tr.inner)
get_inference_cache(tr::TracingInterpreter) = get_inference_cache(tr.inner)
InferenceParams(tr::TracingInterpreter) = InferenceParams(tr.inner)
OptimizationParams(tr::TracingInterpreter) = OptimizationParams(tr.inner)
Core.Compiler.may_optimize(tr::TracingInterpreter) = true
Core.Compiler.may_compress(tr::TracingInterpreter) = true
Core.Compiler.may_discard_trees(tr::TracingInterpreter) = true
Core.Compiler.add_remark!(tr::TracingInterpreter, sv::InferenceState, msg) = Core.Compiler.add_remark!(tr.inner, sv, msg)
lock_mi_inference(tr::TracingInterpreter, mi::MethodInstance) = nothing
unlock_mi_inference(tr::TracingInterpreter, mi::MethodInstance) = nothing
@static if VERSION >= v"1.7.0-DEV.577"
    Core.Compiler.verbose_stmt_info(interp::TracingInterpreter) = false
end

#####
##### Optimize
#####

function run_passes(interp::TracingInterpreter, ci::CodeInfo, nargs::Int, sv::OptimizationState)
    preserve_coverage = coverage_enabled(sv.mod)
    ir = convert_to_ircode(ci, copy_exprargs(ci.code), preserve_coverage, nargs, sv)
    ir = slot2reg(ir, ci, nargs, sv)
    return ir
end

#function run_passes(interp::TracingInterpreter, ci::CodeInfo, nargs::Int, sv::OptimizationState)
#    preserve_coverage = coverage_enabled(sv.mod)
#    ir = convert_to_ircode(ci, copy_exprargs(ci.code), preserve_coverage, nargs, sv)
#    ir = slot2reg(ir, ci, nargs, sv)
#    ir = compact!(ir)
#    ir = ssa_inlining_pass!(ir, ir.linetable, sv.inlining, ci.propagate_inbounds)
#    ir = compact!(ir)
#    ir = getfield_elim_pass!(ir) # SROA
#    ir = adce_pass!(ir)
#    ir = type_lift_pass!(ir)
#    ir = compact!(ir)
#end

function custom_pass!(interp::TracingInterpreter, mi, ir)
    try
        ir = trace!(interp.ctx, ir)
    catch e
        push!(interp, e)
    end
    return ir
end

function optimize(interp::TracingInterpreter, opt::OptimizationState,
        params::OptimizationParams, @nospecialize(result))
    nargs = Int(opt.nargs) - 1
    mi = opt.linfo
    meth = mi.def
    ir = run_passes(interp, opt.src, nargs, opt)
    ir = custom_pass!(interp, mi, ir)
    verify_ir(ir)
    verify_linetable(ir.linetable)
    return _finish(interp, opt, params, ir, result)
end
