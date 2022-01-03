module JIT

# Roughly matches Enzyme's ORCv2 JIT.

using LLVM
import LLVM:TargetMachine
import GPUCompiler

export get_trampoline

struct CompilerInstance
    jit::LLVM.LLJIT
    lctm::Union{LLVM.LazyCallThroughManager, Nothing}
    ism::Union{LLVM.IndirectStubsManager, Nothing}
end

function LLVM.dispose(ci::CompilerInstance)
    dispose(ci.jit)
    if ci.lctm !== nothing
        dispose(ci.lctm)
    end
    if ci.ism !== nothing
        dispose(ci.ism)
    end
    return nothing
end

const jit = Ref{CompilerInstance}()
const tm = Ref{TargetMachine}() # for opt pipeline

get_tm() = tm[]

function __init__()
    opt_level = Base.JLOptions().opt_level
    if opt_level < 2
        optlevel = LLVM.API.LLVMCodeGenLevelNone
    elseif opt_level == 2
        optlevel = LLVM.API.LLVMCodeGenLevelDefault
    else
        optlevel = LLVM.API.LLVMCodeGenLevelAggressive
    end

    tempTM = LLVM.JITTargetMachine(;optlevel=optlevel)
    LLVM.asm_verbosity!(tempTM, true)
    tm[] = tempTM

    tempTM = LLVM.JITTargetMachine(;optlevel)
    LLVM.asm_verbosity!(tempTM, true)

    if haskey(ENV, "ENABLE_GDBLISTENER")
        ollc = LLVM.ObjectLinkingLayerCreator() do es, triple
            oll = ObjectLinkingLayer(es)
            register!(oll, GDBRegistrationListener())
            return oll
        end

        GC.@preserve ollc begin
            builder = LLJITBuilder()
            LLVM.linkinglayercreator!(builder, ollc)
            tmb = TargetMachineBuilder(tempTM)
            LLVM.targetmachinebuilder!(builder, tmb)
            lljit = LLJIT(builder)
        end
    else
        lljit = LLJIT(;tm=tempTM)
    end

    jd_main = JITDylib(lljit)

    prefix = LLVM.get_prefix(lljit)
    dg = LLVM.CreateDynamicLibrarySearchGeneratorForProcess(prefix)
    LLVM.add!(jd_main, dg)

    es = ExecutionSession(lljit)
    try
        lctm = LLVM.LocalLazyCallThroughManager(triple(lljit), es)
        ism = LLVM.LocalIndirectStubsManager(triple(lljit))
        jit[] = CompilerInstance(lljit, lctm, ism)
    catch err
        @warn "OrcV2 initialization failed with" err
        jit[] = CompilerInstance(lljit, nothing, nothing)
    end

    atexit() do
        ci = jit[]
        dispose(ci)
        dispose(tm[])
    end
end

function move_to_threadsafe(ir)
    LLVM.verify(ir)
    buf = convert(MemoryBuffer, ir)
    return ThreadSafeContext() do ctx
        mod = parse(LLVM.Module, buf; ctx=context(ctx))
        ThreadSafeModule(mod; ctx)
    end
end

function get_trampoline(job)
    compiler = jit[]
    lljit = compiler.jit
    lctm  = compiler.lctm
    ism   = compiler.ism

    if lctm === nothing || ism === nothing
        error("Delayed compilation not available.")
    end
    jd = JITDylib(lljit)
    entry_sym = String(gensym(:entry))
    target_sym = String(gensym(:target))
    flags = LLVM.API.LLVMJITSymbolFlags(
                LLVM.API.LLVMJITSymbolGenericFlagsCallable |
                LLVM.API.LLVMJITSymbolGenericFlagsExported, 0)
    entry = LLVM.API.LLVMOrcCSymbolAliasMapPair(
                mangle(lljit, entry_sym),
                LLVM.API.LLVMOrcCSymbolAliasMapEntry(
                    mangle(lljit, target_sym), flags))
    mu = LLVM.reexports(lctm, ism, jd, Ref(entry))
    LLVM.define(jd, mu)
    
    function materialize(mr)
        _, mod, func_name, specfunc_name = Compiler._jit(job)
        tsm = move_to_threadsafe(mod)
        il = LLVM.IRTransformLayer(lljit)
        LLVM.emit(il, mr, tsm)
        return nothing
    end

    function discard(jd, sym)
    end

    mu = LLVM.CustomMaterializationUnit(entry_sym, Ref(sym), materialize, discard)
    LLVM.define(jd, mu)
    addr = LLVM.lookup(lljit, entry_sym)
    return addr
end

const inactivefns = Set((
    "jl_gc_queue_root", "gpu_report_exception", "gpu_signal_exception",
    "julia.ptls_states", "julia.write_barrier", "julia.typeof", "jl_box_int64", "jl_box_int32",
    "jl_subtype", "julia.get_pgcstack", "jl_in_threaded_region", "jl_object_id_", "jl_object_id",
    "jl_breakpoint",
    "llvm.julia.gc_preserve_begin","llvm.julia.gc_preserve_end", "jl_get_ptls_states",
    "jl_f_fieldtype",
    "jl_symbol_n",
    "jl_gc_add_finalizer_th"
))

function annotate!(mod)
    ctx = context(mod)
    inactive = LLVM.StringAttribute("mixtape_inactive", ""; ctx)
    fns = functions(mod)

    for inactivefn in inactivefns
        if haskey(fns, inactivefn)
            fn = fns[inactivefn]
            push!(function_attributes(fn), inactive)
        end
    end

    for fname in ("julia.get_pgcstack", "julia.ptls_states", "jl_get_ptls_states")
        if haskey(fns, fname)
            fn = fns[fname]
            # TODO per discussion w keno perhaps this should change to readonly / inaccessiblememonly
            push!(function_attributes(fn), LLVM.EnumAttribute("readnone", 0; ctx))
        end
    end

    for fname in ("julia.pointer_from_objref",)
        if haskey(fns, fname)
            fn = fns[fname]
            push!(function_attributes(fn), LLVM.EnumAttribute("readnone", 0; ctx))
        end
    end

    for boxfn in ("jl_box_int64", "julia.gc_alloc_obj", "jl_alloc_array_1d", "jl_alloc_array_2d", "jl_alloc_array_3d")
        if haskey(fns, boxfn)
            fn = fns[boxfn]
            push!(return_attributes(fn), LLVM.EnumAttribute("noalias", 0; ctx))
            push!(function_attributes(fn), LLVM.EnumAttribute("inaccessiblememonly", 0; ctx))
        end
    end

    for gc in ("llvm.julia.gc_preserve_begin", "llvm.julia.gc_preserve_end")
        if haskey(fns, gc)
            fn = fns[gc]
            push!(function_attributes(fn), LLVM.EnumAttribute("inaccessiblememonly", 0; ctx))
        end
    end

    for rfn in ("jl_object_id_", "jl_object_id")
        if haskey(fns, rfn)
            fn = fns[rfn]
            push!(function_attributes(fn), LLVM.EnumAttribute("readonly", 0; ctx))
        end
    end
end

function add!(mod)
    lljit = jit[].jit
    jd = LLVM.JITDylib(lljit)
    tsm = move_to_threadsafe(mod)
    LLVM.add!(lljit, jd, tsm)
    return nothing
end

function lookup(_, name)
    LLVM.lookup(jit[].jit, name)
end

end # module
