module TestBench

include("../src/Mixtape.jl")
using .Mixtape

function foo(x::Float64)
    y = x + 10.0
    q = y * 10.0
    return q
end

ei, ssg = analyze(Tuple{typeof(foo), Float64})
println(ei.code)

end # module
