module Mixtape

using ExportAll

using TimerOutputs
using DataStructures
using LLVM
using LLVM.Interop
using Libdl
using Core.Compiler
using Core.Compiler: MethodInstance, NativeInterpreter, CodeInfo, VarTable, AbstractInterpreter
using Base.Meta

import Core.Compiler: InferenceParams, OptimizationParams, get_world_counter, get_inference_cache, InferenceResult, _methods_by_ftype, OptimizationState, CodeInstance, Const, widenconst, isconstType, abstract_call_gf_by_type, abstract_call, code_cache, WorldView, lock_mi_inference, unlock_mi_inference, InferenceState


include("mixer.jl")

timings() = (TimerOutputs.print_timer(to); println())
enable_timings() = (TimerOutputs.enable_debug_timings(Mixtape); return)

end # module

