using Test

include("../src/Mixtape.jl")
using .Mixtape

@time @testset "Miscellaneous tests" begin include("misctests.jl") end
