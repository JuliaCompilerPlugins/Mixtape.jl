module Simple

using Mixtape
import Mixtape: MixtapeIntrinsic, remix, mix_transform!

# Some innocent unaware code...
f(x) = begin
    d = Dict()
    d[:k] = x + 10
    d
end

mutable struct MixTable <: MixtapeIntrinsic
    fn
    recorded::Int
end
(mt::MixTable)(args...) = mt.fn(args...)

# Mixtape automatically enables the fallback of *no interception*.
mixtray = MixTable(f, 0)
thunk = Mixtape.jit(mixtray, Tuple{Int})
v = thunk(5)
println(v)

# You must explicitly overload.
function remix(mt::MixTable, ::typeof(Base.getproperty), s, f)
    mt.recorded += 5
    Base.getproperty(s, f)
end

function remix(mt::MixTable, ::typeof(+), args...)
    foldr(*, args)
end

# You can also define your own passes quite easily - specified by the type of your extended intrinsic.
mix_transform!(::Type{MixTable}, src) = (println(src); src)

# Recompiles.
@time thunk = Mixtape.jit(mixtray, Tuple{Int})
@time v = thunk(5)
println((v, mixtray.recorded))

end # module
