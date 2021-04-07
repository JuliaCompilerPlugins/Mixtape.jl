using JuliaFormatter

function main()
    perfect = format(joinpath(@__DIR__, ".."); style=YASStyle())
    if perfect
        @info "Linting complete - no files altered"
    else
        @info "Linting complete - files altered"
        run(`git status`)
    end
    return nothing
end

main()
