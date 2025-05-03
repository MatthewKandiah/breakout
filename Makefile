OUT = breakout

build: build-shaders build-main

build-debug: build-shaders-debug build-main-debug

run: build
	./$(OUT)

build-main:
	odin build main -out:$(OUT)

build-main-debug:
	odin build main -out:$(OUT) -debug

build-shaders:
	glslc shaders/shader.vert -o vert.spv
	glslc shaders/shader.frag -o frag.spv

build-shaders-debug:
	glslc shaders/shader.vert -o vert.spv -g
	glslc shaders/shader.frag -o frag.spv -g

clean:
	rm ./*.spv
	rm $(OUT)
