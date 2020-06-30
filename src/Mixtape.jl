module Mixtape

using IRTools
using IRTools: argument!, insert!, insertafter!
using IRTools.Inner: argnames!, slots!, update!
using Core: CodeInfo

# This will be our "context" type
abstract type MixTable end

# Recursively wraps function calls with the below generated function call and inserts the context argument.
function remix!(ir)
    pr = IRTools.Pipe(ir)

    # Iterate across Pipe, inserting calls to the generated function and inserting the context argument.
    new = argument!(pr)
    for (v, st) in pr
        ex = st.expr
        ex isa Expr && ex.head == :call && begin
            
            # Ignores Base and Core.
            if !(ex.args[1] isa GlobalRef && (ex.args[1].mod == Base || ex.args[1].mod == Core))
                args = copy(ex.args)
                pr[v] = Expr(:call, GlobalRef(Mixtape, :remix!), new, ex.args...)
            end
        end
    end

    # Turn Pipe into IR.
    ir = IRTools.finish(pr)

    # Re-order arguments.
    ir_args = IRTools.arguments(ir)
    insert!(ir_args, 2, ir_args[end])
    pop!(ir_args)
    blank = argument!(ir)
    insert!(ir_args, 3, ir_args[end])
    pop!(ir_args)
    return ir
end

@generated function remix!(ctx::MixTable, fn::Function, args...) 
    T = Tuple{fn, args...}
    m = IRTools.meta(T)
    m isa Nothing && error("Error in remix!: could not derive lowered method body for $T.")
    ir = IRTools.IR(m)

    # Update IR.
    n_ir = remix!(ir)

    # Update meta.
    argnames!(m, Symbol("#self#"), :ctx, :fn, :args)
    n_ir = IRTools.renumber(IRTools.varargs!(m, n_ir, 3))
    ud = update!(m.code, n_ir)
    ud.method_for_inference_limit_heuristics = nothing
    return ud
end

# Fallback.
remix!(ctx::MixTable, fn, args...) = fn(args...)

end # module
