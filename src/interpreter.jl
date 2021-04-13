#####
##### MixtapeInterpreter
#####

struct MixtapeInterpreter{Ctx<:CompilationContext,Inner<:AbstractInterpreter} <:
       AbstractInterpreter
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
##### Optimize
#####

function run_passes(ir::Core.Compiler.IRCode, ci::CodeInfo, sv::OptimizationState)
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

function custom_pass!(interp::MixtapeInterpreter, mi, ir)
    meth = mi.def
    try
        fn = resolve(GlobalRef(mi.def.module, mi.def.name))
        as = map(resolve, mi.specTypes.parameters[2:end])
        if allow(interp.ctx, mi.def.module, fn, as...) && show_after_inference(interp.ctx)
            print("@ ($(meth.file), L$(meth.line))\n")
            print("| (inf) $(mi.def.module).$fn\n")
            display(opt.src)
        end
        if debug(interp.ctx)
            println("@ ($(meth.file), L$(meth.line))")
            println("| end (inf): $(meth.module).$(fn)")
            println("@ ($(meth.file), L$(meth.line))")
            println("| beg (opt): $(meth.module).$(fn)")
        end
        if allow(interp.ctx, mi.def.module, fn, as...)
            ir = optimize!(interp.ctx, ir)
        end
        if allow(interp.ctx, mi.def.module, fn, as...) &&
           show_after_optimization(interp.ctx)
            print("@ ($(meth.file), L$(meth.line))\n")
            print("| (opt) $(opt.linfo.def.module).$fn\n")
            display(opt.src)
        end
        if debug(interp.ctx)
            println("@ ($(meth.file), L$(meth.line))")
            println("| end (opt): $(meth.module).$(fn)")
        end
    catch e
        push!(interp, e)
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
    ir = run_passes(ir, opt.src, opt)
    ir = custom_pass!(interp, mi, ir)
    ir = run_passes(ir, opt.src, opt)
    verify_ir(ir)
    verify_linetable(ir.linetable)
    return _finish(interp, opt, params, ir, result)
end
