#####
##### Intrinsics
#####

abstract type MixtapeIntrinsic end
remix(::MixtapeIntrinsic, fn, args...) = fn(args...)
descend(::MixtapeIntrinsic, fn, args...) = fn(args...)
