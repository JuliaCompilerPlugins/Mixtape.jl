function _code_info(@nospecialize(f), @nospecialize(tt))
    return CodeInfoTools.code_info(f, tt)
end

macro code_info(call)
    @assert(@capture(call, f_(args__)))
    esc(quote 
        ir, b = Mixtape._code_info($f, Tuple{$(args...)})
        ir
    end)
end

function _code_inferred(ctx::CompilationContext, @nospecialize(f), @nospecialize(tt); world = Base.get_world_counter())
    mi = method_instance(f, tt, world)
    if cpu_cache_lookup(mi, world, world) === nothing
        cpu_infer(ctx, mi, world, world)
    end
    code = cpu_cache_lookup(mi, world, world)
    return Base._uncompressed_ir(code, code.inferred)
end

macro code_inferred(ctx, call)
    @assert(@capture(call, f_(args__)))
    esc(quote 
        Mixtape._code_inferred($ctx, $f, Tuple{$(args...)})
    end)
end

function _code_llvm(ctx::CompilationContext, @nospecialize(f), @nospecialize(tt); world = Base.get_world_counter())
    rt, _, _, mod = cpu_compile(ctx, method_instance(f, tt, world), world)
    return mod
end

macro code_llvm(ctx, call)
    @assert(@capture(call, f_(args__)))
    esc(quote 
        Mixtape._code_llvm($ctx, $f, Tuple{$(args...)})
    end)
end
