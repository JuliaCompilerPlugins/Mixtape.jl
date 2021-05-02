module Static

using LLVM
using Core: MethodInstance, 
            CodeInstance
using Core.Compiler: WorldView,
                     NativeInterpreter
using GPUCompiler: AbstractCompilerTarget,
                   AbstractCompilerParams,
                   CompilerJob,
                   FunctionSpec,
                   julia_datalayout,
                   cached_compilation

import Core.Compiler: InferenceState,
                      InferenceParams,
                      OptimizationParams,
                      InferenceState,
                      OptimizationState,
                      get_world_counter,
                      get_inference_cache,
                      lock_mi_inference,
                      unlock_mi_inference,
                      code_cache,
                      may_optimize,
                      may_compress,
                      may_discard_trees,
                      add_remark!

# Experimental re-write based upon:
# https://github.com/Keno/Compiler3.jl/blob/master/src/extracting_interpreter.jl

#####
##### Utilities
#####

function get_methodinstance(@nospecialize(sig))
    ms = Base._methods_by_ftype(sig, 1, Base.get_world_counter())
    @assert length(ms) == 1
    m = ms[1]
    mi = ccall(:jl_specializations_get_linfo,
               Ref{MethodInstance}, (Any, Any, Any),
               m[3], m[1], m[2])
    return mi
end

function infer(interp, fn, t::Type...)
    mi = get_methodinstance(Tuple{typeof(fn), t...})
    ccall(:jl_typeinf_begin, Cvoid, ())
    result = Core.Compiler.InferenceResult(mi)
    world = Core.Compiler.get_world_counter()
    frame = Core.Compiler.InferenceState(result, true, interp)
    frame === nothing && return nothing
    Core.Compiler.typeinf(interp, frame)
    ccall(:jl_typeinf_end, Cvoid, ())
    return (mi, result)
end

#####
##### Static interpreter
#####

# Based on: https://github.com/Keno/Compiler3.jl/blob/master/exploration/static.jl

# Holds its own cache.
struct StaticInterpreter{I} <: Core.Compiler.AbstractInterpreter
    code::Dict{MethodInstance, CodeInstance}
    inner::I
    messages::Vector{Tuple{MethodInstance, Int, String}}
    optimize::Bool
end

function StaticInterpreter(; opt = false)
    return StaticInterpreter(Dict{MethodInstance, CodeInstance}(),
                             NativeInterpreter(), 
                             Tuple{MethodInstance, Int, String}[],
                             opt)
end

InferenceParams(si::StaticInterpreter) = InferenceParams(si.inner)
OptimizationParams(si::StaticInterpreter) = OptimizationParams(si.inner)
get_world_counter(si::StaticInterpreter) = get_world_counter(si.inner)
get_inference_cache(si::StaticInterpreter) = get_inference_cache(si.inner)
lock_mi_inference(si::StaticInterpreter, mi::MethodInstance) = nothing
unlock_mi_inference(si::StaticInterpreter, mi::MethodInstance) = nothing
code_cache(si::StaticInterpreter) = si.code
Core.Compiler.get(a::Dict, b, c) = Base.get(a,b,c)
Core.Compiler.get(a::WorldView{<:Dict}, b, c) = Base.get(a.cache,b,c)
Core.Compiler.haskey(a::Dict, b) = Base.haskey(a, b)
Core.Compiler.haskey(a::WorldView{<:Dict}, b) =
Core.Compiler.haskey(a.cache, b)
Core.Compiler.setindex!(a::Dict, b, c) = setindex!(a, b, c)
Core.Compiler.may_optimize(si::StaticInterpreter) = si.optimize
Core.Compiler.may_compress(si::StaticInterpreter) = false
Core.Compiler.may_discard_trees(si::StaticInterpreter) = false
function Core.Compiler.add_remark!(si::StaticInterpreter, sv::InferenceState, msg)
    push!(ei.msgs, (sv.linfo, sv.currpc, msg))
end

#####
##### FunctionGraph
#####

abstract type FunctionGraph end

struct StaticSubGraph <: FunctionGraph
    code::Dict{MethodInstance, Any}
    instances::Vector{MethodInstance}
    entry::MethodInstance
end

entrypoint(ssg::StaticSubGraph) = ssg.entry

cursor_mi(mi::MethodInstance) = mi

has_codsinfo(ssg::StaticSubGraph, mi::MethodInstance) = haskey(ssg.code, mi)

get_codeinstance(ssg::StaticSubGraph, mi::MethodInstance) = getindex(ssg.code, mi)

function get_codeinfo(code::Core.CodeInstance)
    ci = code.inferred
    if ci isa Vector{UInt8}
        return Core.Compiler._uncompressed_ir(code, ci)
    else
        return ci
    end
end

function get_codeinfo(graph::StaticSubGraph, 
        cursor::MethodInstance)
    return get_codeinfo(get_codeinstance(graph, cursor))
end

function analyze(@nospecialize(f), t::Type...; opt = false)
    si = StaticInterpreter(; opt = opt)
    mi, res = infer(si, f, t...)
    si, StaticSubGraph(si.code, collect(keys(si.code)), mi)
end

# Similar to Yao.
function gather_children(si, ssg, mi)
    # Run inlining to convert calls to invoke.
    haskey(ssg.code, mi) || return Any[] # TODO: When does this happen?
    ci = get_codeinfo(ssg, mi)
    params = OptimizationParams()
    sv = OptimizationState(ssg.entry, params, si)
    sv.slottypes .= ci.slottypes
    nargs = Int(sv.nargs) - 1
    ir = Core.Compiler.run_passes(ci, nargs, sv)
    ret = Any[]
    for stmt in ir.stmts
        Core.Compiler.isexpr(stmt, :invoke) || continue
        push!(ret, stmt.args[1])
    end
    unique(ret)
end

function filter_messages(si::StaticInterpreter, mi::MethodInstance)
    filter(x->x[1] == mi, si.messages)
end

function analyze_static(@nospecialize(f), t::Type...)
    si = StaticInterpreter()
    mi, result = infer(si, f, t...)
    ssg = StaticSubGraph(si.code, collect(keys(si.code)), mi)
    worklist = Any[(ssg.entry, [])]
    visited = Set{Any}(worklist)
    while !isempty(worklist)
        mi, stack = popfirst!(worklist)
        global cur_mi
        cur_mi = mi
        for msg in filter_messages(si, mi)
            print("In function: ")
            Base.show_tuple_as_call(stdout, mi.def.name, mi.specTypes)
            println()
            printstyled("ERROR: ", color=:red)
            println(msg[3]);
            ci = get_codeinfo(ssg, mi)
            loc = ci.linetable[ci.codelocs[msg[2]]]
            fname = String(loc.file)
            if startswith(fname, "REPL[")
                hp = Base.active_repl.interface.modes[1].hist
                repl_id = parse(Int, fname[6:end-1])
                repl_contents = hp.history[repl_id+hp.start_idx]
                for (n, line) in enumerate(split(repl_contents, '\n'))
                    print(n == loc.line ? "=> " : "$n| ")
                    println(line)
                end
            else
                println("TODO: File content here")
            end
            println()
            for (i, old_mi) in enumerate(reverse(stack))
                print("[$i] In ")
                Base.show_tuple_as_call(stdout, old_mi.def.name, old_mi.specTypes)
                println()
            end
            println()
        end
        children = gather_children(si, ssg, mi)
        for child in children
            if !(child in visited)
                push!(worklist, (child, [copy(stack); mi]))
            end
            push!(visited, mi)
        end
    end
end

#####
##### Cached compilation
#####

# Interpreter holds the cache.
function cache_lookup(si::StaticInterpreter, mi::MethodInstance,
        min_world, max_world)
    return getindex(si.code, mi)
end

# Mostly from GPUCompiler. 
# In future, try to upstream any requires changes.
function codegen(@nospecialize(f), t::Type...; opt = false)
    analyze_static(f, t...)
    si, ssg = analyze(f, t...; opt = opt) # Populate local cache.
    world = get_world_counter(si)
    λ_lookup = (mi, min, max) -> cache_lookup(si, mi, min, max)
    lookup_cb = @cfunction($λ_lookup, Any, (Any, UInt, UInt))
    params = Base.CodegenParams(; 
                                track_allocations = false, 
                                code_coverage     = false,
                                prefer_specsig    = true,
                                gnu_pubnames      = false,
                                lookup            = Base.unsafe_convert(Ptr{Nothing}, lookup_cb))

    GC.@preserve lookup_cb begin
        native_code = ccall(:jl_create_native, 
                            Ptr{Cvoid},
                            (Vector{MethodInstance}, 
                             Base.CodegenParams, Cint), 
                            [ssg.entry],
                            params, 1) # = extern policy = #
        @assert native_code != C_NULL
        llvm_mod_ref = ccall(:jl_get_llvm_module, 
                             LLVM.API.LLVMModuleRef, 
                             (Ptr{Cvoid},),
                             native_code)
        @assert llvm_mod_ref != C_NULL
        llvm_mod = LLVM.Module(llvm_mod_ref)
    end
    code = cache_lookup(si, ssg.entry, world, world)
    llvm_func_idx = Ref{Int32}(-1)
    llvm_specfunc_idx = Ref{Int32}(-1)
    ccall(:jl_get_function_id, 
          Nothing, 
          (Ptr{Cvoid}, Any, Ptr{Int32}, Ptr{Int32}),
          native_code, code, llvm_func_idx, llvm_specfunc_idx)
    @assert llvm_specfunc_idx[] != -1
    @assert llvm_func_idx[] != -1
    llvm_func_ref = ccall(:jl_get_llvm_function, 
                          LLVM.API.LLVMValueRef,
                          (Ptr{Cvoid}, UInt32), 
                          native_code, 
                          llvm_func_idx[] - 1)
    @assert llvm_func_ref != C_NULL
    llvm_func = LLVM.Function(llvm_func_ref)
    llvm_specfunc_ref = ccall(:jl_get_llvm_function, 
                              LLVM.API.LLVMValueRef,
                              (Ptr{Cvoid}, UInt32), 
                              native_code, 
                              llvm_specfunc_idx[] - 1)
    @assert llvm_specfunc_ref != C_NULL
    llvm_specfunc = LLVM.Function(llvm_specfunc_ref)
    triple!(llvm_mod, llvm_triple(job.target))
    if julia_datalayout(job.target) !== nothing
        datalayout!(llvm_mod, julia_datalayout(job.target))
    end
    return (Any, llvm_specfunc, llvm_func, llvm_mod)
end

struct StaticCompilerTarget <: AbstractCompilerTarget end
struct StaticCompilerParams <: AbstractCompilerParams
    optimize::Bool
end

struct Entry{F, RT, TT}
    f::F
    specfunc::Ptr{Cvoid}
    func::Ptr{Cvoid}
end

@generated function (entry::Entry{F, RT, TT})(args...) where {F, RT, TT}
    # Slow ABI -- requires array allocation and unpacking. But stable.
    expr = quote
        args = Any[args...]
        ccall(entry.func, 
              Any, 
              (Any, Ptr{Any}, Int32), 
              entry.f, args, length(args))
    end
    return expr
end

const jit_compiled_cache = Dict{UInt, Any}()

function jit(@nospecialize(f), t::Type...; opt = false)
    fspec = FunctionSpec(f, Tuple{t...}, false, nothing) #=name=#
    job = CompilerJob(StaticCompilerTarget(), 
                      fspec, 
                      StaticCompilerParams(opt))
    return cached_compilation(jit_compiled_cache, job, _jit, _jitlink)
end

function _jitlink(job::CompilerJob, (rt, llvm_mod, func_name, specfunc_name))
    fspec = job.source
    jitted_mod = compile!(orc[], llvm_mod)
    specfunc_addr = addressin(orc[], jitted_mod, specfunc_name)
    specfunc_ptr = pointer(specfunc_addr)
    func_addr = addressin(orc[], jitted_mod, func_name)
    func_ptr = pointer(func_addr)
    if specfunc_ptr === C_NULL || func_ptr === C_NULL
        @error "Compilation error" fspec specfunc_ptr func_ptr
    end
    return Entry{typeof(fspec.f), rt, fspec.tt}(fspec.f, specfunc_ptr, func_ptr)
end

function _jit(job::CompilerJob)
    rt, llvm_specfunc, llvm_func, llvm_mod = codegen(job.source.f, 
                                                     job.source.tt.parameters...; opt = job.params.optimize)
    specfunc_name = LLVM.name(llvm_specfunc)
    func_name = LLVM.name(llvm_func)
    linkage!(llvm_func, LLVM.API.LLVMExternalLinkage)
    linkage!(llvm_specfunc, LLVM.API.LLVMExternalLinkage)
    run_pipeline!(llvm_mod)
    return (rt, llvm_mod, func_name, specfunc_name)
end

end # module
