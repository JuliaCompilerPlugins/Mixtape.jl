module StaticExample

using Mixtape
using CodeInfoTools
using MacroTools

@ctx (false, false, false) struct Mix end

module Rosenbrock

rosenbrock(x, y, a, b) = (a - x)^2 + b * (y - x^2)^2
fake() = rosenbrock(1, 1, 1, 1)

end

@time entry = Mixtape.jit(Rosenbrock.rosenbrock, 
                                 Tuple{Float64, Int, Int, Int}; 
                                 opt = true)

display(@time entry(3.1, 1, 1, 1))
display(@time entry(3.1, 1, 1, 1))

@time entry = Mixtape.jit(Rosenbrock.rosenbrock, 
                                 Tuple{Int, Int, Int, Int}; 
                                 opt = true)

display(@time entry(3, 1, 1, 1))
display(@time entry(3, 1, 1, 1))

allow(::Mix, m::Module) = m == Rosenbrock

# A few little utility functions for working with Expr instances.
swap(e) = e
function swap(e::Expr)
    new = MacroTools.postwalk(e) do s
        isexpr(s, :call) || return s
        s.args[1] == Base.:(*) || return s
        return Expr(:call, Base.:(+), e.args[2 : end]...)
    end
    return new
end

# This is pre-inference - you get to see a CodeInfoTools.Builder instance.
function transform(::Mix, src)
    b = CodeInfoTools.Builder(src)
    for (v, st) in b
        b[v] = swap(st)
    end
    return CodeInfoTools.finish(b)
end

Mixtape.@load_abi()
display(call(Rosenbrock.rosenbrock, 5, 5, 5, 5; ctx = Mix()))
display(call(Rosenbrock.fake; ctx = Mix()))

end # module
