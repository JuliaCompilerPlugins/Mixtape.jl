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
    ci = SafeCodeInfo(src, method.sig isa UnionAll ? 1 : length(method.sig.types))
    ci = mix_transform!(interp, ci)
    ci = cassette_transform!(mi, ci)
    ci = finish(ci)
    ci
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

function handle_apply_iterate!(sci, stmt, v, codeloc)
    iterf = stmt.args[2]
    callf = stmt.args[3]
    callargs = stmt.args[4:end]
    k = insert_stmt!(sci, v, Expr(:call, 
                                  GlobalRef(Core, :tuple), 
                                  Core.SlotNumber(1), 
                                  callf))
    l = insert_stmt!(sci, v + 1, Expr(:call, 
                                      GlobalRef(Core, :_apply_iterate), 
                                      iterf, 
                                      GlobalRef(Mixtape, :remix), 
                                      k,
                                      callargs...))
    insert_stmt!(sci, v + 2, Expr(:return, l))
end

function handle_apply!(sci, stmt, v, codeloc) 
end

#####
##### Pass
#####

function check_recurse(enclosing)
    (enclosing isa Type && enclosing <: MixtapeIntrinsic) && return true
    return false
end

@inline mix_transform!(::Type{<:MixtapeIntrinsic}, src) = src
@inline mix_transform!(interp::MixtapeInterpreter{Intr}, src) where Intr = mix_transform!(Intr, src)

function identity_pass!(enclosing, sci, ci)
    for (v, stmt) in enumerate(ci.code)
        codeloc = ci.codelocs[v]
        push_stmt!(sci, stmt, codeloc)
    end
end

function handle_fallback!(sci, stmt, v, codeloc)
    f = stmt.args[1]
    f = ir_element(f, sci.src.code)
    insert!(stmt.args, 1, GlobalRef(Mixtape, :remix))
    insert!(stmt.args, 2, Core.SlotNumber(1))
    push_stmt!(sci, stmt, codeloc)
end

function overdub_pass!(enclosing, sci, ci)
    display(sci.src)
    for (v, stmt) in enumerate(ci.code)
        codeloc = ci.codelocs[v]
        stmt = Base.Meta.isexpr(stmt, :(=)) ? stmt.args[2] : stmt
        Base.Meta.isexpr(stmt, :call) || continue
        applycall = is_ir_element(stmt.args[1], GlobalRef(Core, :_apply), ci.code) 
        applyitercall = is_ir_element(stmt.args[1], GlobalRef(Core, :_apply_iterate), ci.code) 
        applycall ? handle_apply!(sci, stmt, v, codeloc) : applyitercall ? handle_apply_iterate!(sci, stmt, v, codeloc) : handle_fallback!(sci, stmt, v, codeloc)
    end
    display(sci.src)
    finish(sci)
end

function cassette_transform!(mi, sci)
    enclosing = static_eval(getfield(mi.def, :module), mi.def.name)
    check_recurse(enclosing) ? overdub_pass!(enclosing, sci, sci.src) : identity_pass!(enclosing, sci, sci.src)
    return sci
end
