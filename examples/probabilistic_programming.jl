module ProbabilisticProgramming

include("../src/Mixtape.jl")
using .Mixtape
using Distributions

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
    chm::Dict{Union{Symbol, Pair{Symbol, Int}}, RecordSite}
    score::Float64
    Trace() = new(Dict{Union{Symbol, Pair{Symbol, Int}}, RecordSite}(), 0.0)
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
geo(p::Float64) = rand(:flip, Bernoulli(p)) == 1 ? 0 : 1 + rand(:geo, geo, p)
tr = Trace()
tr(geo, 0.8)
test = p -> begin
    for i in 1:1e6
        tr = Trace()
        ret = tr(geo, p)
        CallSite(tr, geo, p, ret)
    end
end

@time test(0.8)

end # module
