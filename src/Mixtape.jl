module Mixtape

using IRTools
using IRTools: IR
using IRTools: argument!, insert!, insertafter!
using IRTools.Inner: argnames!, slots!, update!
using MacroTools: @capture
using Core: CodeInfo

# Used to indicate if the IR pass should include prehooks (scrub) and posthooks (dub).
abstract type HookIndicator end
struct NoHooks <: HookIndicator end
struct Hooks <: HookIndicator end

# Used for custom passes.
abstract type PassIndicator end
struct NoPass <: PassIndicator end

# This will be our "context" type
abstract type MixTable{T <: HookIndicator, L <: PassIndicator} end

# Recursively wraps function calls with the below generated function call and inserts the context argument.
function pipe_transform!(pr::IRTools.Pipe, hi::Type{NoHooks})
    new = argument!(pr)
    for (v, st) in pr
        ex = st.expr
        if ex isa Expr && ex.head == :call && !(ex.args[1] isa GlobalRef && (ex.args[1].mod == Base || ex.args[1].mod == Core || ex.args[1].mod == Base.Iterators))
            if ex.args[1] isa GlobalRef && ex.args[1].name == :rand
                ref = GlobalRef(@__MODULE__, :remix!)
                pr[v] = Expr(:call, ref, new, ex.args...)
            end
        end
    end
end

function pipe_transform!(pr::IRTools.Pipe, hi::Type{Hooks})
    new = argument!(pr)
    for (v, st) in pr
        ex = st.expr
        if ex isa Expr && ex.head == :call && !(ex.args[1] isa GlobalRef && (ex.args[1].mod == Base || ex.args[1].mod == Core || ex.args[1].mod == Base.Iterators))
            insert!(pr, v, Expr(:call, GlobalRef(@__MODULE__, :scrub!), new, ex.args...))
            insertafter!(pr, v, Expr(:call, GlobalRef(@__MODULE__, :dub!), new, ex.args...))
            pr[v] = Expr(:call, GlobalRef(@__MODULE__, :remix!), new, ex.args...)
        end
    end
end

function remix_no_args!(ir, hi)
    pr = IRTools.Pipe(ir)
    pipe_transform!(pr, hi)
    ir = IRTools.finish(pr)
    blank = argument!(ir)
    return ir
end

function remix_args!(ir, hi)
    pr = IRTools.Pipe(ir)
    pipe_transform!(pr, hi)
    ir = IRTools.finish(pr)

    # Re-order.
    ir_args = IRTools.arguments(ir)
    insert!(ir_args, 2, ir_args[end])
    pop!(ir_args)
    blank = argument!(ir)
    insert!(ir_args, 3, ir_args[end])
    pop!(ir_args)
    return ir
end

# Custom passes.
custom_pass!(ir::IRTools.IR, L::Type{NoPass}) = ir

# Easy creation of custom passes.
macro build_pass(expr)
    @capture(expr, function fn_(nm_::IR)::IR body_ end) || error("Custom pass definition requires a function with signature:\nfunc(name::IR)::IR).")
    s_name = gensym(:pass)
    build = quote
        import Mixtape: custom_pass!
        struct $(esc(s_name)) <: Mixtape.PassIndicator end
        $expr
        Mixtape.custom_pass!(ir::IRTools.IR, L::Type{$(esc(s_name))}) = $fn(ir)
        $(esc(s_name))
    end
    build
end

# Core remix! generated function - inserts itself into IR. No args version.
@generated function remix!(ctx::MixTable{K, L}, fn::Function) where {K <: HookIndicator, L <: PassIndicator}
    m = IRTools.meta(Tuple{fn})
    m isa Nothing && error("Error in remix!: could not derive lowered method body for $T.")
    ir = IRTools.IR(m)

    # Update IR.
    #n_ir = custom_pass!(ir, L)
    n_ir = remix_no_args!(ir, K)

    # Update meta.
    argnames!(m, Symbol("#self#"), :ctx, :fn)
    n_ir = IRTools.renumber(n_ir)
    ud = update!(m.code, n_ir)
    ud.method_for_inference_limit_heuristics = nothing
    println(ud)
    return ud
end

# Core remix! generated function - inserts itself into IR.
@generated function remix!(ctx::MixTable{K, L}, fn::Function, args...) where {K <: HookIndicator, L <: PassIndicator}
    m = IRTools.meta(Tuple{fn, args...})
    m isa Nothing && error("Error in remix!: could not derive lowered method body for $T.")
    ir = IRTools.IR(m)

    # Update IR.
    #n_ir = custom_pass!(ir, L)
    n_ir = remix_args!(ir, K)

    # Update meta.
    argnames!(m, Symbol("#self#"), :ctx, :fn, :args)
    n_ir = IRTools.renumber(IRTools.varargs!(m, n_ir, 3))
    ud = update!(m.code, n_ir)
    ud.method_for_inference_limit_heuristics = nothing
    println(ud)
    return ud
end

# Not meant to be overloaded - no args.
@generated function recurse!(ctx::MixTable{K, L}, fn::Function)  where {K <: HookIndicator, L <: PassIndicator}
    m = IRTools.meta(Tuple{fn})
    m isa Nothing && error("Error in remix!: could not derive lowered method body for $T.")
    ir = IRTools.IR(m)

    # Update IR.
    #n_ir = custom_pass!(ir, L)
    n_ir = remix_no_args!(ir, K)

    # Update meta.
    argnames!(m, Symbol("#self#"), :ctx, :fn)
    n_ir = IRTools.renumber(n_ir)
    ud = update!(m.code, n_ir)
    ud.method_for_inference_limit_heuristics = nothing
    println(ud)
    return ud
end

# Not meant to be overloaded.
@generated function recurse!(ctx::MixTable{K, L}, fn::Function, args...)  where {K <: HookIndicator, L <: PassIndicator}
    m = IRTools.meta(Tuple{fn, args...})
    m isa Nothing && error("Error in remix!: could not derive lowered method body for $T.")
    ir = IRTools.IR(m)

    # Update IR.
    #n_ir = custom_pass!(ir, L)
    n_ir = remix_args!(ir, K)

    # Update meta.
    argnames!(m, Symbol("#self#"), :ctx, :fn, :args)
    n_ir = IRTools.renumber(IRTools.varargs!(m, n_ir, 3))
    ud = update!(m.code, n_ir)
    ud.method_for_inference_limit_heuristics = nothing
    println(ud)
    return ud
end

# Fallback for remix! and pre/post-hook calls.
remix!(ctx::MixTable, fn, args...) = fn(args...)
scrub!(ctx::MixTable, fn, args...) = nothing
dub!(ctx::MixTable, fn, args...) = nothing

# Convenience. MixTable closures call remix!
(c::MixTable)(fn::Function, args...) = remix!(c, fn, args...)

export MixTable, Hooks, NoHooks, remix!, recurse!, scrub!, dub!, NoPass

end # module
