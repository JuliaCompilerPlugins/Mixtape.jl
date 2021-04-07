module TestMixtape

using Mixtape
import Mixtape: CompilationContext, transform, allow_transform, debug
using MacroTools

struct TestCtx <: CompilationContext end
debug(::TestCtx) = true
ctx = TestCtx()
function transform(::TestCtx, ir)
    #display(ir)
    #for (v, st) in ir
    #    st.expr isa Expr || continue
    #    st.expr.head == :call || continue
    #    st.expr.args[1] == Base.:(+) || continue
    #    ir[v] = Expr(:call, Base.:(*), st.expr.args[2 : end]...)
    #end
    #display(ir)
    return ir
end

function rosenbrock_mul(x::Vector{Float64})
    a = 1.0
    b = 100.0
    result = 0.0
    for i in 1:length(x)-1
        result += (a - x[i])^2 * b*(x[i+1] - x[i]^2)^2
    end
    return result
end

function rosenbrock(x::Vector{Float64})
    a = 1.0
    b = 100.0
    result = 0.0
    for i in 1:length(x)-1
        result += (a - x[i])^2 + b*(x[i+1] - x[i]^2)^2
    end
    return result
end

allow_transform(::TestCtx, r::typeof(rosenbrock), args...) = true
fn = Mixtape.jit(ctx, rosenbrock, Tuple{Vector{Float64}})
display(fn([0.0, 1.0]))

end # module
