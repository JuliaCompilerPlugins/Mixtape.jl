function widen_invokes!(b::CodeInfoTools.Builder)
    counter = 0
    for (v, st) in b
        st isa Expr || continue
        st.head == :call || continue
        st.args[1] == invoke || continue
        insert!(b, v + counter, Expr(:tuple, st.args[2], st.args[4]...))
        insert!(b, v + 1 + counter, Expr(:call, typeof, Core.SSAValue(v)))
        replace!(b, v + 2 + counter, Expr(:call, invoke, 
                                          GlobalRef(Mixtape, :call),
                                          Core.SSAValue(v + 1),
                                          st.args[2], st.args[4]...))
        counter += 2
    end
    return b
end
