module How2Mix

# Unassuming code in an unassuming module...
module SubFoo

function f()
    x = rand()
    y = rand()
    return x + y
end

end

using Mixtape
import Mixtape: CompilationContext, transform, allow
using CodeInfoTools
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

# This is pre-inference - you get to see a CodeInfoTools.Builder instance.
function transform(::MyMix, src)
    b = CodeInfoTools.Builder(src)
    for (v, st) in b
        b[v] = swap(st)
    end
    return CodeInfoTools.finish(b)
end

# MyMix will only transform functions which you explicitly allow.
# You can also greenlight modules.
allow(ctx::MyMix, m::Module) = m == SubFoo

# This loads up a call interface which will cache the result of the pipeline.
Mixtape.@load_abi()
@assert(call(SubFoo.f; ctx = MyMix()) == 8)
@assert(SubFoo.f() != 8)

end # module
