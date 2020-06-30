module Mixtape

using IRTools
using IRTools: argument!, insert!, insertafter!
using IRTools.Inner: argnames!, slots!, update!
using Core: CodeInfo
using InteractiveUtils: @code_llvm, @code_lowered, @code_native

# This will be our "context" type
abstract type MixTable end

# Recursively wraps function calls with the below generated function call and inserts the context argument.
function remix!(ir, hooks = false)
    pr = IRTools.Pipe(ir)
    new = argument!(pr)
    

    for (v, st) in pr
        ex = st.expr
        ex isa Expr && ex.head == :call && begin
            if !(ex.args[1] isa GlobalRef && (ex.args[1].mod == Base || ex.args[1].mod == Core))
                args = copy(ex.args)
                ex = Expr(:call, GlobalRef(@__MODULE__, :remix!), new, ex.args...)
                pr[v] = ex
                if hooks
                    insert!(pr, v, Expr(:call, :scrub!, new, args...))
                    insertafter!(pr, v, Expr(:call, :dub!, new, args...))
                end
            end
        end
    end
    ir = IRTools.finish(pr)
    
    # Swap.
    ir_args = IRTools.arguments(ir)
    insert!(ir_args, 2, ir_args[end])
    pop!(ir_args)
    blank = argument!(ir)
    insert!(ir_args, 3, ir_args[end])
    pop!(ir_args)
    return ir
end

_remix(fn, args...) = fn(args...)

@generated function remix!(ctx::MixTable, fn::Function, args...)
    T = Tuple{fn, args...}
    m = IRTools.meta(T)
    m isa Nothing && error("Error in remix!: could not derive lowered method body for $T.")
    ir = IRTools.IR(m)

    # Update IR.
    n_ir = remix!(ir)

    # Update meta.
    original_argnames = m.code.slotnames[2:m.nargs]
    argnames!(m, Symbol("#self#"), :ctx, :fn, :args)
    n_ir = IRTools.varargs!(m, n_ir, 3)
    n_ir = IRTools.renumber(n_ir)
    ud = update!(m.code, n_ir)
    ud.method_for_inference_limit_heuristics = nothing
    return ud
end

# ---- Test ---- #

function bar(x::Float64)
    y = x + 10.0
    return y
end

function foo(x::Float64, y::Float64)
    z = x + 20.0
    q = bar(y) + z
    return q
end

mutable struct CountingMix <: MixTable
    count::Int
end

function remix!(ctx::CountingMix, fn::typeof(+), args...)
    ctx.count += 1
    return fn(args...)
end

ctx = CountingMix(0)
x = remix!(ctx, foo, 5.0, 3.0)
println(ctx.count)
println(x)

end # module
