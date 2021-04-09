using Mixtape
using Documenter

makedocs(; modules=[Mixtape], sitename="Mixtape", authors="McCoy R. Becker",
         pages=["API Documentation" => "index.md"])

deploydocs(; repo="github.com/femtomc/Mixtape.jl.git", push_preview=true)
