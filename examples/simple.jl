module Simple

using Mixtape

f(x) = begin
    d = Dict()
    d[:k] = x + 10
    d
end

thunk = Mixtape.jit(f, Tuple{Int})
v = thunk(5)
println(v)

@time thunk = Mixtape.jit(f, Tuple{Int})
@time v = thunk(5)
println(v)
@time v = thunk(5)

end # module
