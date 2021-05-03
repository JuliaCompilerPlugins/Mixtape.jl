module Tracing

using Mixtape
import Mixtape: CompilationContext, transform, postopt!, allow

f(x::Number, y) = sin(x + 1) + (sin(3y) - 1);

foo(x) = x^5
bar(x) = x^10

function m(x, y)
    g = x < 5 ? foo : bar
    return g(y)
end

struct MyMix <: CompilationContext end
allow(ctx::MyMix, m::Module) = m == Tracing

using Core.Compiler: Const, is_pure_intrinsic_infer, intrinsic_nothrow, anymap, quoted

function postopt!(::MyMix, ir)
    for i in 1 : length(ir.stmts)
        stmt = ir.stmts[i][:inst]
        if stmt isa Expr && stmt.head === :call
            sig = Core.Compiler.call_sig(ir, stmt)
            f, ft, atypes = sig.f, sig.ft, sig.atypes
            allconst = true
            for atype in sig.atypes
                if !isa(atype, Const)
                    allconst = false
                    break
                end
            end
            if allconst &&
                isa(f, Core.IntrinsicFunction) &&
                is_pure_intrinsic_infer(f) &&
                intrinsic_nothrow(f, atypes[2:end])
                fargs = anymap(x::Const -> x.val, atypes[2:end])
                val = f(fargs...)
                Core.Compiler.setindex!(ir.stmts[i], quoted(val), :inst)
                Core.Compiler.setindex!(ir.stmts[i], Const(val), :type)
            elseif allconst && isa(f, Core.Builtin) && (f === Core.tuple || f === Core.getfield)
                fargs = anymap(x::Const -> x.val, atypes[2:end])
                val = f(fargs...)
                Core.Compiler.setindex!(ir.stmts[i], quoted(val), :inst)
                Core.Compiler.setindex!(ir.stmts[i], Const(val), :type)
            end
        end
    end
    return ir
end

λ = x -> f(x, 3.0)
entry = Mixtape.jit(λ, Tuple{Float64}; ctx = MyMix())
display(emit(λ, Tuple{Float64}; ctx = MyMix(), opt = true))
display(entry(5.0))
λ = y -> m(5.0, y)
display(emit(λ, Tuple{Float64}; ctx = MyMix(), opt = true))

end # module
