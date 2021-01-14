module Mixtape

using Core.Compiler
using Core.Compiler: MethodInstance, NativeInterpreter, CodeInfo, CodeInstance, WorldView, OptimizationState
using Base.Meta
using LLVM
using LLVM.Interop

# Cache
using Core.Compiler: WorldView

# Interpreter
import Core.Compiler: AbstractInterpreter, InferenceResult, InferenceParams, InferenceState, OptimizationParams
import Core.Compiler: get_world_counter, get_inference_cache, code_cache, lock_mi_inference, unlock_mi_inference
import Core.Compiler: retrieve_code_info, validate_code_in_debug_mode

# Optimizer
import Core.Compiler: optimize
#import Core.Compiler: CodeInfo, convert_to_ircode, copy_exprargs, slot2reg, compact!, coverage_enabled, adce_pass!
#import Core.Compiler: ssa_inlining_pass!, getfield_elim_pass!, type_lift_pass!, verify_ir, verify_linetable

# JIT
import GPUCompiler
import GPUCompiler: FunctionSpec

include("intrinsics.jl")
include("codecache.jl")
include("interpreter.jl")
include("codeinfo.jl")
include("transform.jl")
include("optimize.jl")
include("codegen.jl")
include("pipeline.jl")
include("jit.jl")

const CACHE = Dict{DataType, CodeCache}()
get_cache(ai::DataType) = CACHE[ai]

#####
##### Setup execution engine
#####

# We have one global JIT and TM
const orc = Ref{LLVM.OrcJIT}()
const tm  = Ref{LLVM.TargetMachine}()

function __init__()
    CACHE[NativeInterpreter] = CodeCache(cpu_invalidate)

    opt_level = Base.JLOptions().opt_level
    if opt_level < 2
        optlevel = LLVM.API.LLVMCodeGenLevelNone
    elseif opt_level == 2
        optlevel = LLVM.API.LLVMCodeGenLevelDefault
    else
        optlevel = LLVM.API.LLVMCodeGenLevelAggressive
    end

    tm[] = LLVM.JITTargetMachine(optlevel=optlevel)
    LLVM.asm_verbosity!(tm[], true)

    orc[] = LLVM.OrcJIT(tm[]) # takes ownership of tm
    atexit() do
        LLVM.dispose(orc[])
    end
end

end # module
