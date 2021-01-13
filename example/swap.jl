module Swap

using Mixtape
import Mixtape.overdub

struct SwapAddition <: Context end

baz(x, y) = x + y
function overdub(ctx::SwapAddition, ::typeof(+), args...)
    foldr(*, args)
end

# TODO: this is not finished.
overdub(SwapAddition(), baz, 1, 1) # has a weird cache side effect
println(baz(3, 3)) # The cache stores the overdubbed definition - not really what we want. But sort of on the right path.

end # module
