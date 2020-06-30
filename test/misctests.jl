function rosenbrock(x::Vector{Float64})
    a = 1.0
    b = 100.0
    result = 0.0
    for i in 1:length(x)-1
        result += (a - x[i])^2 + b*(x[i+1] - x[i]^2)^2
    end
    return result
end

comprehension(x) = [i for i in x]
fib(x) = x < 3 ? 1 : fib(x - 2) + fib(x - 1)
fibtest(n) = fib(2 * n) + n

#function Mixtape.remix!(mx::MemoizeMix, fn::typeof(fib), args...)
#    result = get(mx.stored, x, 0)
#    result === 0 && return recurse!(mx, fib, x)
#    return result
#end

function loop73(x, n)
    r = x / x
    while n > 0
        r *= sin(x)
        n -= 1
    end
    return r
end

struct NoOpMix <: MixTable{NoHooks, NoPass}
end

f73(x, n) = remix!(NoOpMix(), loop73, x, n)
ff73(x, n) = remix!(NoOpMix(), f73, x, n)
fff73(x, n) = remix!(NoOpMix(), ff73, x, n)

f73(2, 50) # warm up
ff73(2, 50) # warm up
fff73(2, 50) # warm up

