module TestBench

include("../src/Mixtape.jl")
using .Mixtape
using Core.Compiler: Const, abstract_call_gf_by_type, abstract_call

function foo(x::Float64)
    y = x + 10.0
    q = y * 10.0
    return q
end

function bar(x::Float64)
    return x
end

Mixtape.@mixer BasicTable

function Mixtape.overlay(mixer::BasicTable, fn::typeof(foo), x::Float64)
    return
end

mxi, ssg = Mixtape.mix(BasicTable(), foo, 5.0)
println(ssg)

end # module
