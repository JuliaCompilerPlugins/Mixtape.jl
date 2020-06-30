module TestBench

include("../src/Mixtape.jl")
using .Mixtape

function foo(x::Float64, y::Float64)
    q = x + 20.0
    l = q + 20.0
    return l
end

mutable struct CountingMix <: Mixtape.MixTable
    count::Int
    CountingMix() = new(0)
end

function Mixtape.remix!(ctx::CountingMix, fn::typeof(+), args...)
    ctx.count += 1
    return fn(args...)
end

ctx = CountingMix()
x = Mixtape.remix!(ctx, foo, 5.0, 3.0)
println(ctx.count)

end
