module How2Mix

# Unassuming code in an unassuming module...
module SubFoo

function rosenbrock(x)
    a = 1.0
    b = 100.0
    result = 0.0
    for i in 1:length(x)-1
        result += (a - x[i])^2 + b*(x[i+1] - x[i]^2)^2
    end
    return result
end

function f()
    x = rand()
    y = rand()
    return rosenbrock([x, y])
end

g(f) = f()

end

using Mixtape
import Mixtape: CompilationContext, transform, allow_transform, show_after_inference, show_after_optimization, debug
using MacroTools

# 101: How2Mix
struct MyMix <: CompilationContext end

# A few little utility functions for working with Expr instances.
swap(e) = e
function swap(e::Expr)
    new = MacroTools.postwalk(e) do s
        isexpr(s, :call) || return s
        s.args[1] == Base.rand || return s
        return 5
    end
    return new
end

function transform(::MyMix, b)
    for (v, st) in b
        replace!(b, v, swap(st))
    end
    display(b)
    return b
end

# MyMix will only transform functions which you explicitly allow.
allow_transform(ctx::MyMix, m::Module) = m == SubFoo
show_after_inference(ctx::MyMix) = false
show_after_optimization(ctx::MyMix) = false
debug(ctx::MyMix) = true

fn = Mixtape.jit(MyMix(), SubFoo.g, Tuple{typeof(SubFoo.f)})
@time fn = Mixtape.jit(MyMix(), SubFoo.g, Tuple{typeof(SubFoo.f)})

@assert(fn(SubFoo.f) == SubFoo.rosenbrock([5, 5]))

end # module
