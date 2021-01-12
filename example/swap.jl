module Swap

using Mixtape
import Mixtape.overdub

struct Mix <: Context end

foo(x, y) = x + y
overdub(ctx::Mix, ::typeof(+), a, b) = a * b
#ci = code_mix(Mix(), foo, 5, 10)

ci, _, _, _ = overdub(Mix(), foo, 5, 10)
display(ci)

end # module
