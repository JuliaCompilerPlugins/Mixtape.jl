module ProbabilisticProgramming

include("../src/Mixtape.jl")
using .Mixtape
using Distributions
using InteractiveUtils

abstract type RecordSite end
struct ChoiceSite{T} <: RecordSite
    score::Float64
    val::T
end
struct CallSite{T, J, K} <: RecordSite
    tr::T
    fn::Function
    args::J
    ret::K
end

struct Trace <: MixTable{NoHooks, NoPass}
    chm::Dict{Symbol, RecordSite}
    score::Float64
    Trace() = new(Dict{Symbol, RecordSite}(), 0.0)
end

function Mixtape.remix!(tr::Trace, fn::typeof(rand), addr::Symbol, d::Distribution{T}) where T
    s = rand(d)
    tr.chm[addr] = ChoiceSite(logpdf(d, s), s)
    return s
end

function Mixtape.remix!(tr::Trace, fn::typeof(rand), addr::Symbol, call::Function, args...)
    new_tr = Trace()
    ret = recurse!(new_tr, call, args...)
    tr.chm[addr] = CallSite(new_tr, fn, args, ret)
    return ret
end

# Test.
function bar(q::Float64)
    return rand(:m, Normal(q, 1.0))
end

function foo(z::Float64, y::Float64)
    x = rand(:x, Normal(5.0, 1.0))
    l = rand(:l, bar, 5.0)
    return x + l
end

tr = Trace()
tr(foo, 5.0, 3.0)
test = () -> begin
    for i in 1:1e6
        tr = Trace()
        tr(foo, 5.0, 3.0)
    end
end

@time test()

end # module
