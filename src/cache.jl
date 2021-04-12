#####
##### Cache
#####

struct CodeCache
    dict::Dict{MethodInstance,Vector{CodeInstance}}
    callback::Function
    CodeCache(callback) = new(Dict{MethodInstance,Vector{CodeInstance}}(), callback)
end

function Base.show(io::IO, ::MIME"text/plain", cc::CodeCache)
    print(io, "CodeCache: ")
    for (mi, cis) in cc.dict
        println(io)
        print(io, "- ")
        show(io, mi.specTypes)
        for ci in cis
            println(io)
            print(io, "  - ")
            print(io, (ci.min_world, ci.max_world))
        end
    end
    print("\n")
end

function Core.Compiler.setindex!(cache::CodeCache, ci::CodeInstance, mi::MethodInstance)
    if !isdefined(mi, :callbacks)
        mi.callbacks = Any[cache.callback]
    else
        # Check if callback is present
        if all(cb -> cb !== cache.callback, mi.callbacks)
            push!(mi.callbacks, cache.callback)
        end
    end
    cis = get!(cache.dict, mi, CodeInstance[])
    return push!(cis, ci)
end

const CACHE = Dict{Any,CodeCache}()
get_cache(ai::DataType) = CACHE[ai]
get_cache(ai::Type{<:AbstractInterpreter}) = CACHE[ai]

function invalidate(cache::CodeCache, replaced::MethodInstance, max_world, depth)
    cis = get(cache.dict, replaced, nothing)
    if cis === nothing
        return
    end
    for ci in cis
        if ci.max_world == ~0 % Csize_t
            @assert ci.min_world - 1 <= max_world "attempting to set illogical constraints"
            ci.max_world = max_world
        end
        @assert ci.max_world <= max_world
    end

    # recurse to all backedges to update their valid range also
    if isdefined(replaced, :backedges)
        backedges = replaced.backedges
        # Don't touch/empty backedges `invalidate_method_instance` in C will do that later
        # replaced.backedges = Any[]
        for mi in backedges
            invalidate(cache, mi, max_world, depth + 1)
        end
    end
end
