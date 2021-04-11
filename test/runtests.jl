module TestMixtape

using Test
using Mixtape
using CodeInfoTools
import Mixtape: CompilationContext, transform, allow, debug
using MacroTools

include("dynamic_overlay.jl")
include("rand_swap.jl")
include("insert_state.jl")
include("recursion.jl")
include("invalidation.jl")

EXAMPLES_DIR = joinpath(@__DIR__, "..", "examples")

for ex in readdir(EXAMPLES_DIR)
    @testset "$ex" begin
        # Just check the examples run, for now.
        include(joinpath(EXAMPLES_DIR, ex))
    end
end

end # module
