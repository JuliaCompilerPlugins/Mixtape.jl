module ProbabilisticProgramming

include("../src/Mixtape.jl")
using .Mixtape
using Distributions
using Profile

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
geo(p::Float64) = rand(:flip, Bernoulli(p)) == 1 ? 0 : 1 + rand(:geo, geo, p)
tr = Trace()
tr(geo, 0.8)
Profile.clear_malloc_data()
test = () -> begin
    for i in 1:1e6
        tr = Trace()
        ret = tr(geo, 0.5)
        CallSite(tr, geo, 0.5, ret)
    end
end

@profile test()

end # module
