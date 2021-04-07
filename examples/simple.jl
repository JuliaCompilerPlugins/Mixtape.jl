module How2Mix

# Unassuming code in an unassuming module...
module SubFoo

λ() = 10 + 20
function semantic_stub(args...)
    println("I'm having so much fun!")
    println("WHAT!")
    x = 20 + 30
    return foldr(+, args) + x + λ()
end

function h(x)
    return x * 2 + semantic_stub(x)
end

function f(x) 
    d = x + 50
    return h(d)
end

end

using Mixtape
import Mixtape: CompilationContext, transform, allow_transform, show_after_inference, show_after_optimization, debug

using IRTools

# 101: How2Mix
struct MyMix <: CompilationContext end

function transform(::MyMix, ir)
    locations = []
    for (v, st) in ir
        st.expr isa Expr || continue
        st.expr.head == :call || continue
        st.expr.args[1] == Base.:(+) || continue
        ir[v] = Expr(:call, GlobalRef(Base, :(*)), st.expr.args[2 : end]...)
    end
    display(ir)
    return ir
end

# MyMix will only transform functions which you explicitly allow.
allow_transform(ctx::MyMix, m::Module) = m == SubFoo
show_after_inference(ctx::MyMix) = false
show_after_optimization(ctx::MyMix) = false
debug(ctx::MyMix) = true

fn = Mixtape.jit(MyMix(), SubFoo.f, Tuple{Float64})
@time fn = Mixtape.jit(MyMix(), SubFoo.f, Tuple{Float64})
display(fn(5.0))

end # module