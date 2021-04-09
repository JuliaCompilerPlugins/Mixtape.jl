module How2Mix

# Unassuming code in an unassuming module...
module SubFoo

function h()
    return rand()
end
function f()
    x = rand()
    y = rand()
    return x + y + h()
end

end

using Mixtape
import Mixtape: CompilationContext, transform, allow, show_after_inference,
                show_after_optimization, debug
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
    display(b)
    for (v, st) in b
        replace!(b, v, swap(st))
    end
    display(b)
    return b
end

# MyMix will only transform functions which you explicitly allow.
allow(ctx::MyMix, m::Module) = m == SubFoo
show_after_inference(ctx::MyMix) = false
show_after_optimization(ctx::MyMix) = false
debug(ctx::MyMix) = true

Mixtape.@load_call_interface()
@assert(call(MyMix(), SubFoo.f) == 15)
@assert(SubFoo.f() != 15)

end # module
