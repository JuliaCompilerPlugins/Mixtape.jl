module TestMixtape

using Test
using Mixtape
import Mixtape: CompilationContext, transform, allow_transform, debug
using MacroTools

include("dynamic_overlay.jl")
include("rand_swap.jl")
include("insert_state.jl")

end # module
