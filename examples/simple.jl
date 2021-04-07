module How2Mix

# Unassuming code in an unassuming module...
module SubFoo

function h(x)
    x = rand()
    y = rand()
    return x + y
end

function f(x)
    z = rand()
    return h(x)
end

end

using Mixtape
import Mixtape: CompilationContext, transform, allow_transform, show_after_inference,
                show_after_optimization, debug

using IRTools

# 101: How2Mix
struct MyMix <: CompilationContext end

function transform(::MyMix, ir)
    for (v, st) in ir
        st.expr isa Expr || continue
        st.expr.head == :call || continue
        st.expr.args[1] == Base.rand || continue
        ir[v] = 5
    end
    return ir
end

# MyMix will only transform functions which you explicitly allow.
#allow_transform(ctx::MyMix, fn::typeof(SubFoo.h), a...) = true
allow_transform(ctx::MyMix, m::Module) = m == SubFoo
show_after_inference(ctx::MyMix) = false
show_after_optimization(ctx::MyMix) = false
debug(ctx::MyMix) = true

fn = Mixtape.jit(MyMix(), SubFoo.f, Tuple{Float64})
@time fn = Mixtape.jit(MyMix(), SubFoo.f, Tuple{Float64})

display(fn(5.0))
display(SubFoo.f(5.0))

end # module
