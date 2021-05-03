module TestMixtape

using Test
using Mixtape
import Mixtape: CompilationContext,
                allow,
                transform,
                optimize!
using CodeInfoTools
using MacroTools

EXAMPLES_DIR = joinpath(@__DIR__, "..", "examples")

for ex in readdir(EXAMPLES_DIR)
    @testset "$ex" begin
        # Just check the examples run, for now.
        include(joinpath(EXAMPLES_DIR, ex))
    end
end

end # module
