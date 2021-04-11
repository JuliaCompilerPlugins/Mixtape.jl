#####
##### Optimize
#####

function run_passes(ci::CodeInfo, nargs::Int, sv::OptimizationState)
    preserve_coverage = coverage_enabled(sv.mod)
    ir = convert_to_ircode(ci, copy_exprargs(ci.code), preserve_coverage, nargs, sv)
    ir = slot2reg(ir, ci, nargs, sv)
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

@static if VERSION >= v"1.7.0-DEV.662"
    using Core.Compiler: finish as _finish
else
    function _finish(interp::AbstractInterpreter, opt::OptimizationState,
                     params::OptimizationParams, ir, @nospecialize(result))
        return Core.Compiler.finish(opt, params, ir, result)
    end
end

function optimize(interp::MixtapeInterpreter, opt::OptimizationState,
                  params::OptimizationParams, @nospecialize(result))
    nargs = Int(opt.nargs) - 1
    mi = opt.linfo
    meth = mi.def
    ir = run_passes(opt.src, nargs, opt)
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
            verify_ir(ir)
        end
        ret = _finish(interp, opt, params, ir, result)
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
        return ret
    catch e
        push!(interp, e)
    end
    return _finish(interp, opt, params, ir, result)
end
