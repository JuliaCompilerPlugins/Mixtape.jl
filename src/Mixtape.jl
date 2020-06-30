module Mixtape

using IRTools
using IRTools: argument!, insert!, insertafter!
using IRTools.Inner: argnames!, slots!, update!
using Core: CodeInfo

# Used to indicate if the IR pass should include prehooks (scrub) and posthooks (dub).
abstract type HookIndicator end
struct NoHooks <: HookIndicator end
struct Hooks <: HookIndicator end

# This will be our "context" type
abstract type MixTable{T <: HookIndicator} end

# Recursively wraps function calls with the below generated function call and inserts the context argument.
function remix!(ir, hi::Type{NoHooks})
    pr = IRTools.Pipe(ir)

    # Iterate across Pipe, inserting calls to the generated function and inserting the context argument.
    new = argument!(pr)
    for (v, st) in pr
        ex = st.expr
        if ex isa Expr && ex.head == :call && !(ex.args[1] isa GlobalRef && (ex.args[1].mod == Base || ex.args[1].mod == Core))
            pr[v] = Expr(:call, GlobalRef(Mixtape, :remix!), new, ex.args...)
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

function remix!(ir, hi::Type{Hooks})
    pr = IRTools.Pipe(ir)

    # Iterate across Pipe, inserting calls to the generated function and inserting the context argument.
    new = argument!(pr)
    for (v, st) in pr
        ex = st.expr
        if ex isa Expr && ex.head == :call && !(ex.args[1] isa GlobalRef && (ex.args[1].mod == Base || ex.args[1].mod == Core))
            args = copy(ex.args)
            pr[v] = Expr(:call, GlobalRef(Mixtape, :remix!), new, ex.args...)
            insert!(pr, v, Expr(:call, GlobalRef(Mixtape, :scrub!), new, args...))
            insertafter!(pr, v, Expr(:call, GlobalRef(Mixtape, :dub!), new, args...))
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

@generated function remix!(ctx::MixTable{K}, fn::Function, args...) where K <: HookIndicator
    T = Tuple{fn, args...}
    m = IRTools.meta(T)
    m isa Nothing && error("Error in remix!: could not derive lowered method body for $T.")
    ir = IRTools.IR(m)

    # Update IR.
    n_ir = remix!(ir, K)

    # Update meta.
    argnames!(m, Symbol("#self#"), :ctx, :fn, :args)
    n_ir = IRTools.renumber(IRTools.varargs!(m, n_ir, 3))
    ud = update!(m.code, n_ir)
    ud.method_for_inference_limit_heuristics = nothing
    println(ud)
    return ud
end

@generated function recurse!(ctx::MixTable{K}, fn::Function, args...)  where K <: HookIndicator
    T = Tuple{fn, args...}
    m = IRTools.meta(T)
    m isa Nothing && error("Error in remix!: could not derive lowered method body for $T.")
    ir = IRTools.IR(m)

    # Update IR.
    n_ir = remix!(ir, K)

    # Update meta.
    argnames!(m, Symbol("#self#"), :ctx, :fn, :args)
    n_ir = IRTools.renumber(IRTools.varargs!(m, n_ir, 3))
    ud = update!(m.code, n_ir)
    ud.method_for_inference_limit_heuristics = nothing
    return ud
end

# Fallback.
remix!(ctx::MixTable, fn, args...) = fn(args...)
scrub!(ctx::MixTable, fn, args...) = nothing
dub!(ctx::MixTable, fn, args...) = nothing

# Convenience.
(c::MixTable)(fn::Function, args...) = remix!(c, fn, args...)

end # module
