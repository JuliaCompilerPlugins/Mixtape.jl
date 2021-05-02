module StaticExample

using Mixtape

rosenbrock(x, y, a, b) = (a - x)^2 + b * (y - x^2)^2

Mixtape.Static.analyze_static(rosenbrock, Int, Int, Int, Int)
si, ssg = Mixtape.Static.analyze(rosenbrock, Int, Int, Int, Int)

entry = Mixtape.Static.jit(rosenbrock, Int, Int, Int, Int)

end # module
