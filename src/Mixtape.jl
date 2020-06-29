module Mixtape

using IRTools
using IRTools: argument!, insert!, insertafter!
using IRTools.Inner: argnames!, update!

# This will be our "context" type
abstract type MixTable end

# Recursively wraps function calls with the below generated function call and inserts the context argument.
function remix!(ir, hooks = false)
    pr = IRTools.Pipe(ir)
    new = argument!(pr)
    for (v, st) in pr
        ex = st.expr
        ex isa Expr && ex.head == :call && begin
            args = copy(ex.args)
            ex = Expr(:call, :remix!, new, ex.args...)
            pr[v] = ex
            if hooks
                insert!(pr, v, Expr(:call, :scrub!, new, args...))
                insertafter!(pr, v, Expr(:call, :dub!, new, args...))
            end
        end
    end
    ir = IRTools.finish(pr)
    
    # Swap.
    ir_args = IRTools.arguments(ir)
    swap = deepcopy(ir_args[2])
    ir_args[2] = ir_args[end]
    ir_args[end] = swap
    
    # Re-order.
    ir = IRTools.renumber(ir)
    ir
end

@generated function remix!(ctx::MixTable, fn::Function, args...)
    T = Tuple{fn, args...}
    m = IRTools.meta(T)
    m isa Nothing && error("Error in remix!: could not derive lowered method body for $T.")
    ir = IRTools.IR(m)
    n_ir = remix!(ir)
    original_argnames = m.code.slotnames[2:m.nargs]
    argnames!(m, Symbol("#self#"), :ctx, :f, :args)
    n_ir = IRTools.varargs!(m, n_ir, 3)
    updated = update!(m.code, n_ir)
    println(updated)
    return updated
end

# ---- Test ---- #

function bar(x::Float64)
    y = x + 10
    return y
end

function foo(x::Float64, y::Float64)
    z = x + 20
    bar(y)
    q = bar(y) + z
    return q
end

mutable struct CountingMix <: MixTable
    count::Int
end

# This defines foo as a primitive - it won't use the infrastructure.
function remix!(ctx::CountingMix, fn::typeof(foo), args...)
    ctx.count += 1
    return fn(args...)
end

x = remix!(CountingMix(0), foo, 5.0, 3.0)
println(x)

end # module
