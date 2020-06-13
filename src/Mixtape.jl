module Mixtape

using TimerOutputs
using DataStructures
using LLVM
using LLVM.Interop
using Libdl

include("abstract.jl")
include("driver.jl")

timings() = (TimerOutputs.print_timer(to); println())
enable_timings() = (TimerOutputs.enable_debug_timings(Mixtape); return)

end # module

