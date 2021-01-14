module Simple

using Mixtape
import Mixtape: MixtapeIntrinsic, remix

struct MixTable <: MixtapeIntrinsic
    fn
end
(mt::MixTable)(args...) = mt.fn(args...)
remix(mt::MixTable, ::typeof(Base.getproperty), s, f) = Base.getproperty(s, f)

f(x) = begin
    d = Dict()
    d[:k] = x + 10
    d
end

mixtray = MixTable(f)

thunk = Mixtape.jit(mixtray, Tuple{Int})
v = thunk(5)
println(v)

@time thunk = Mixtape.jit(f, Tuple{Int})
@time v = thunk(5)
println(v)
@time v = thunk(5)

end # module
