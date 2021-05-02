module StaticExample

using Mixtape

rosenbrock(x, y, a, b) = (a - x)^2 + b * (y - x^2)^2

@time entry = Mixtape.jit(rosenbrock, 
                                 Tuple{Float64, Int, Int, Int}; 
                                 opt = true)

display(@time entry(3.1, 1, 1, 1))
display(@time entry(3.1, 1, 1, 1))

@time entry = Mixtape.jit(rosenbrock, 
                                 Tuple{Int, Int, Int, Int}; 
                                 opt = true)

display(@time entry(3, 1, 1, 1))
display(@time entry(3, 1, 1, 1))

end # module
