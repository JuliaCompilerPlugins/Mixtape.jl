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
    ci = mix_transform!(interp, ci)
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

#####
##### Handle apply and _apply_iterate
#####

function f_push!(arr::Array, t::Tuple{}) end
f_push!(arr::Array, t::Array) = append!(arr, t)
f_push!(arr::Array, t::Tuple) = append!(arr, t)
f_push!(arr, t) = push!(arr, t)
function flatten(t::Tuple)
    arr = Any[]
    for sub in t
        f_push!(arr, sub)
    end
    return arr
end

function remix(mt::MixtapeIntrinsic, ::typeof(Core._apply_iterate), f, fn, args...)
    acc = flatten(args)
    return descend(mt, fn, acc...)
end

function handle_apply_iterate!(stmt)
    stmt.args = [GlobalRef(Mixtape, :remix),
                 Core.SlotNumber(1),
                 GlobalRef(Core, :_apply_iterate),
                 GlobalRef(Base, :iterate),
                 stmt.args[3 : end]...]
end
function handle_apply!(stmt) end

#####
##### Pass
#####

function check_recurse(enclosing)
    (enclosing isa Type && enclosing <: MixtapeIntrinsic) && return true
    return false
end

@inline mix_transform!(::Type{<:MixtapeIntrinsic}, src) = src
@inline mix_transform!(interp::MixtapeInterpreter{Intr}, src) where Intr = mix_transform!(Intr, src)

function cassette_transform!(mi, src)
    enclosing = static_eval(getfield(mi.def, :module), mi.def.name)
    check_recurse(enclosing) || return src
    for (i, x) in enumerate(src.code)
        stmt = Base.Meta.isexpr(x, :(=)) ? x.args[2] : x
        if Base.Meta.isexpr(stmt, :call)
            applycall = is_ir_element(stmt.args[1], GlobalRef(Core, :_apply), src.code) 
            applyitercall = is_ir_element(stmt.args[1], GlobalRef(Core, :_apply_iterate), src.code) 
            if applycall
                handle_apply!(stmt)
            elseif applyitercall
                handle_apply_iterate!(stmt)
            else
                f = stmt.args[1]
                f = ir_element(f, src.code)
                insert!(stmt.args, 1, GlobalRef(Mixtape, :remix))
                insert!(stmt.args, 2, enclosing == Mixtape.remix ? Core.SlotNumber(2) : Core.SlotNumber(1))
            end
        end
    end
end
