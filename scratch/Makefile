.PHONY: run
run:
	julia --project=. -e "using Pkg; Pkg.add(url=\"https://github.com/femtomc/CodeInfoTools.jl\"); Pkg.add(path=\"..\"); Pkg.instantiate()"
	julia --project=. static_compile.jl
	clang -Xclang -load -Xclang ${JULIA_DYLIB_PATH}/libjulia.dylib -lstdc++ libf.o main.cpp -o main

.PHONY: clean
clean:
	rm libf.o libf.s
