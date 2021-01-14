#####
##### Cassette pass transform
#####

function static_eval(mod, name)
    if Base.isbindingresolved(mod, name) && 
        Base.isdefined(mod, name)
        return getfield(mod, name)
    else
        return nothing
    end
end

function cassette_transform(interp, mi, src)
    method = mi.def
    f = static_eval(getfield(method, :module), method.name)
    ci = copy(src)
    cassette_transform!(mi, ci)
    return ci
end

function ir_element(x, code::Vector)
    while isa(x, Core.SSAValue)
        x = code[x.id]
    end
    return x
end

function is_ir_element(x, y, code::Vector)
    result = false
    while true # break by default
        if x === y #
            result = true
            break
        elseif isa(x, Core.SSAValue)
            x = code[x.id]
        else
            break
        end
    end
    return result
end

@doc(
"""
```
is_ir_element(x, y, code::Vector)
```
Return `true` if `x === y` or if `x` is an `SSAValue` such that
`is_ir_element(code[x.id], y, code)` is `true`.
See also: [`replace_match!`](@ref), [`insert_statements!`](@ref)
""", is_ir_element)

function cassette_transform!(mi, src)
    # splice `#self#` into kernel intrinsics
    for (i, x) in enumerate(src.code)
        stmt = Base.Meta.isexpr(x, :(=)) ? x.args[2] : x
        if Base.Meta.isexpr(stmt, :call)
            applycall = is_ir_element(stmt.args[1], GlobalRef(Core, :_apply), src.code) 
            applyitercall = is_ir_element(stmt.args[1], GlobalRef(Core, :_apply_iterate), src.code) 
            applycall ? fidx = 2 : applyitercall ? fidx = 3 : fidx = 1
            f = stmt.args[fidx]
            f = ir_element(f, src.code)
            insert!(stmt.args, 1, GlobalRef(Mixtape, :remix))
            insert!(stmt.args, 2, Core.SlotNumber(1))
            display(stmt)
            #if f isa GlobalRef
            #    ff = static_eval(f.mod, f.name)
            #    if ff !== nothing
            #        if ff isa MixtapeIntrinsic
            #            insert!(stmt.args, fidx+1, Core.SlotNumber(1))
            #        end
            #    end
            #end
        end
    end
end
