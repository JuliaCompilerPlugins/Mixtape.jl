module TestBench

include("../src/Mixtape.jl")
using .Mixtape
using Core.Compiler: Const, abstract_call_gf_by_type, abstract_call

function foo(x::Float64)
    y = x + 10.0
    q = y * 10.0
    return q
end

ei, ssg, frame = analyze(Tuple{typeof(foo), Float64})
println(abstract_call_gf_by_type(ei, foo, Any[Const(foo), Float64], Tuple{typeof(foo), Float64}, frame))


end # module
