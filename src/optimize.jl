function optimize(interp::MixtapeInterpreter, opt::OptimizationState, params::OptimizationParams, @nospecialize(result))
    nargs = Int(opt.nargs) - 1
    ir = Core.Compiler.run_passes(opt.src, nargs, opt)
    Core.Compiler.finish(opt, params, ir, result)
end

#function run_passes(ci::CodeInfo, nargs::Int, sv::OptimizationState)
#    preserve_coverage = coverage_enabled(sv.mod)
#    ir = convert_to_ircode(ci, copy_exprargs(ci.code), preserve_coverage, nargs, sv)
#    ir = slot2reg(ir, ci, nargs, sv)
#    # TODO: Domsorting can produce an updated domtree - no need to recompute here
#    ir = compact!(ir)
#    ir = ssa_inlining_pass!(ir, ir.linetable, sv.inlining, ci.propagate_inbounds)
#    ir = compact!(ir)
#    ir = getfield_elim_pass!(ir) # SROA
#    ir = adce_pass!(ir)
#    ir = type_lift_pass!(ir)
#    ir = compact!(ir)
#    verify_ir(ir)
#    verify_linetable(ir.linetable)
#    return ir
#end
