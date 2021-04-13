module Mixtape

using MacroTools: @capture, rmlines, postwalk
using CodeInfoTools
using Core.Compiler
using Core.Compiler: MethodInstance, NativeInterpreter, CodeInfo, CodeInstance, WorldView,
                     OptimizationState, Const, widenconst, MethodResultPure, CallMeta
import Core.Compiler.abstract_call_known
using LLVM
using LLVM.Interop
using LLVM_full_jll

# Cache
using Core.Compiler: WorldView

# AbstractInterpreter
import Core.Compiler: AbstractInterpreter, InferenceResult, InferenceParams, InferenceState,
                      OptimizationParams
import Core.Compiler: get_world_counter, get_inference_cache, code_cache, lock_mi_inference,
                      unlock_mi_inference
import Core.Compiler: retrieve_code_info, validate_code_in_debug_mode

# Optimizer
import Core.Compiler: optimize
import Core.Compiler: CodeInfo, convert_to_ircode, copy_exprargs, slot2reg, compact!,
                      coverage_enabled, adce_pass!
import Core.Compiler: ssa_inlining_pass!, getfield_elim_pass!, type_lift_pass!, verify_ir,
                      verify_linetable

# JIT
using GPUCompiler: GPUCompiler, CompilerJob
import GPUCompiler: FunctionSpec, AbstractCompilerTarget, AbstractCompilerParams

import Base: show, push!

resolve(x) = x
resolve(gr::GlobalRef) = getproperty(gr.mod, gr.name)
resolve(c::Core.Const) = c.val

# Exports.
export CompilationContext, allow, transform, optimize!, show_after_inference,
       show_after_optimization, debug, @ctx, @intrinsic

export widen_invokes

include("cache.jl")
include("world.jl")
include("utility_transforms.jl")
include("context.jl")
include("interpreter.jl")
include("codegen.jl")
include("llvmopt.jl")
include("interface.jl")
include("reflection.jl")
include("init.jl")

end # module
