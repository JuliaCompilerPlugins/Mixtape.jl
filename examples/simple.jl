module Simple

using Mixtape
import Mixtape: CompilationContext, process, allowed, debug
using IRTools

struct MyCtx <: CompilationContext end

function semantic_stub(args...)
    println("I'm having so much fun!")
    return foldr(+, args)
end

function process(::MyCtx, ir)
    locations = []
    for (v, st) in ir
        st.expr isa Expr || continue
        st.expr.head == :call || continue
        if st.expr.args[1] == semantic_stub
            push!(locations, v)
        end
    end
    for v in locations
        ir = IRTools.inline(ir, v, @code_ir(semantic_stub(5)))
    end
    display(ir)
    return ir
end

module SubFoo

using ..Simple: semantic_stub
function h(x)
    return x * 2 + semantic_stub(x)
end

function f(x) 
    d = x + 50
    return h(d)
end

end 

# MyCtx will only process functions which you explicitly allow.
allowed(ctx::MyCtx, f::typeof(SubFoo.f)) = true
allowed(ctx::MyCtx, f::typeof(SubFoo.h)) = true
debug(ctx::MyCtx) = true

fn = Mixtape.jit(MyCtx(), SubFoo.f, Tuple{Float64})
@time fn = Mixtape.jit(MyCtx(), SubFoo.f, Tuple{Float64})
display(fn(5.0))

end # module