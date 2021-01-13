module Swap

using Mixtape
import Mixtape.overdub

struct SwapAddition <: Context end

baz(x, y) = x + y
function overdub(ctx::SwapAddition, ::typeof(+), args...)
    foldr(*, args)
end
ci, _ = overdub(SwapAddition(), baz, 1, 1) # has a weird cache side effect
display(ci)
println(baz(3, 3))

end # module
