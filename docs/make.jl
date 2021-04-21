using Mixtape
using Documenter

makedocs(; modules=[Mixtape], sitename="Mixtape", authors="McCoy R. Becker",
         pages=["API Documentation" => "index.md"])

deploydocs(; repo="github.com/JuliaCompilerPlugins/Mixtape.jl.git", push_preview=true)
