module How2Mix

# Unassuming code in an unassuming module...
module SubFoo

g() = rand()

function h()
    return g()
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
        return 4
    end
    return new
end

# This is pre-inference - you get to see a CodeInfoTools.Pipe instance.
function transform(::MyMix, b)
    for (v, st) in b
        b[v] = swap(st)
    end
    return b
end

# MyMix will only transform functions which you explicitly allow.
# You can also greenlight modules.
allow(ctx::MyMix, m::Module) = m == SubFoo
show_after_inference(ctx::MyMix) = false
show_after_optimization(ctx::MyMix) = false
debug(ctx::MyMix) = false

# This loads up a call interface which will cache the result of the pipeline.
Mixtape.@load_call_interface()
@assert(call(MyMix(), SubFoo.f) == 12)
@assert(call(MyMix(), SubFoo.f) == 12)
@assert(SubFoo.f() != 12)

end # module
