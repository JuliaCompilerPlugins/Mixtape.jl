#####
##### TracingInterpreter
#####

struct TracingInterpreter{Ctx<:CompilationContext,Inner<:AbstractInterpreter} <:
       AbstractInterpreter
    ctx::Ctx
    inner::Inner
    errors::Any
    function TracingInterpreter(interp::MixtapeInterpreter)
        world = interp.inner.world
        ctx = interp.ctx
        new{typeof(ctx), typeof(interp)}(ctx, interp, Any[])
    end
end
Base.push!(mxi::TracingInterpreter, e) = push!(mxi.errors, e)

get_world_counter(mxi::TracingInterpreter) = get_world_counter(mxi.inner)
get_inference_cache(mxi::TracingInterpreter) = get_inference_cache(mxi.inner)
InferenceParams(mxi::TracingInterpreter) = InferenceParams(mxi.inner)
OptimizationParams(mxi::TracingInterpreter) = OptimizationParams(mxi.inner)
Core.Compiler.may_optimize(mxi::TracingInterpreter) = true
Core.Compiler.may_compress(mxi::TracingInterpreter) = true
Core.Compiler.may_discard_trees(mxi::TracingInterpreter) = true
function Core.Compiler.add_remark!(mxi::TracingInterpreter, sv::InferenceState, msg)
    return Core.Compiler.add_remark!(mxi.inner, sv, msg)
end
lock_mi_inference(mxi::TracingInterpreter, mi::MethodInstance) = nothing
unlock_mi_inference(mxi::TracingInterpreter, mi::MethodInstance) = nothing
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
