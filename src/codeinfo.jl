#####
##### A safe wrapper for CodeInfo
#####

# Provides convenient utilities to work with CodeInfo.

struct SafeCodeInfo
    src::CodeInfo
    code::Vector{Any}
    nvariables::Int
    codelocs::Vector{Int32}
    newslots::Dict{Int,Symbol}
    slotnames::Vector{Symbol}
    changemap::Vector{Int}
    slotmap::Vector{Int}

    function SafeCodeInfo(ci::CodeInfo, nargs::Int)
        code = []
        codelocs = Int32[]
        newslots = Dict{Int,Symbol}()
        slotnames = copy(ci.slotnames)
        changemap = fill(0, length(ci.code))
        slotmap = fill(0, length(ci.slotnames))
        new(ci, code, nargs + 1, codelocs, newslots, slotnames, changemap, slotmap)
    end
end

source_slot(ci::SafeCodeInfo, i::Int) = Core.SlotNumber(i + ci.slotmap[i])

function slot(ci::SafeCodeInfo, name::Symbol)
    return Core.SlotNumber(findfirst(isequal(name), ci.slotnames))
end

function unpack_closure!(ci::SafeCodeInfo, closure::Int)
    spec = Core.SlotNumber(closure)
    codeloc = ci.src.codelocs[1]
    # unpack closure
    # %1 = get variables
    push!(ci.code, Expr(:call, GlobalRef(Base, :getfield), spec, QuoteNode(:variables)))
    push!(ci.codelocs, codeloc)
    ci.changemap[1] += 1

    # %2 = get parent
    push!(
        ci.code,
        Expr(
             :(=),
             source_slot(ci, 2),
             Expr(:call, GlobalRef(Base, :getfield), spec, QuoteNode(:parent)),
            ),
       )
    push!(ci.codelocs, codeloc)
    # unpack variables
    for i in 2:ci.nvariables
        push!(
              ci.code,
              Expr(
                   :(=),
                   source_slot(ci, i + 1),
                   Expr(:call, GlobalRef(Base, :getindex), Core.Compiler.NewSSAValue(1), i - 1),
                  ),
             )
        push!(ci.codelocs, codeloc)
    end
    ci.changemap[1] += ci.nvariables
    return ci
end

function insert_slot!(ci::SafeCodeInfo, v::Int, slot::Symbol)
    ci.newslots[v] = slot
    insert!(ci.slotnames, v, slot)
    prev = length(filter(x -> x < v, keys(ci.newslots)))
    for k in v-prev:length(ci.slotmap)
        ci.slotmap[k] += 1
    end
    return ci
end

function push_stmt!(ci::SafeCodeInfo, stmt, codeloc::Int32 = Int32(1))
    push!(ci.code, stmt)
    push!(ci.codelocs, codeloc)
    return ci
end

function insert_stmt!(ci::SafeCodeInfo, v::Int, stmt)
    push_stmt!(ci, stmt, ci.src.codelocs[v])
    ci.changemap[v] += 1
    return Core.Compiler.NewSSAValue(length(ci.code))
end

function update_slots(e, slotmap)
    if e isa Core.SlotNumber
        return Core.SlotNumber(e.id + slotmap[e.id])
    elseif e isa Expr
        return Expr(e.head, map(x -> update_slots(x, slotmap), e.args)...)
    elseif e isa Core.NewvarNode
        return Core.NewvarNode(Core.SlotNumber(e.slot.id + slotmap[e.slot.id]))
    else
        return e
    end
end

function _replace_new_ssavalue(e)
    if e isa Core.Compiler.NewSSAValue
        return Core.SSAValue(e.id)
    elseif e isa Expr
        return Expr(e.head, map(_replace_new_ssavalue, e.args)...)
    elseif e isa Core.GotoIfNot
        cond = e.cond
        if cond isa Core.Compiler.NewSSAValue
            cond = Core.SSAValue(cond.id)
        end
        return Core.GotoIfNot(cond, e.dest)
    elseif e isa Core.ReturnNode && isdefined(e, :val) && isa(e.val, Core.Compiler.NewSSAValue)
        return Core.ReturnNode(Core.SSAValue(e.val.id))
    else
        return e
    end
end

function replace_new_ssavalue!(code::Vector)
    for idx in 1:length(code)
        code[idx] = _replace_new_ssavalue(code[idx])
    end
    return code
end

function finish(ci::SafeCodeInfo)
    Core.Compiler.renumber_ir_elements!(ci.code, ci.changemap)
    replace_new_ssavalue!(ci.code)
    new_ci = copy(ci.src)
    new_ci.code = ci.code
    new_ci.codelocs = ci.codelocs
    new_ci.slotnames = ci.slotnames
    new_ci.slotflags = [0x00 for _ in new_ci.slotnames]
    new_ci.inferred = false
    new_ci.inlineable = true
    new_ci.ssavaluetypes = length(ci.code)
    return new_ci
end
