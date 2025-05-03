package main

import "core:fmt"
import "core:time"
import "vendor:glfw"
import vk "vendor:vulkan"

VERTEX_DATA := []Vertex {
	{{0.0, -0.5}, yellow},
	{{0.5, -0.5}, yellow},
	{{0.5, 0.0}, yellow},
	{{0.0, 0.0}, yellow},
	{{-0.5, 0.0}, pink},
	{{0.0, 0.0}, pink},
	{{0.0, 0.5}, pink},
	{{-0.5, 0.5}, pink},
	{{-0.25, -0.25}, red},
	{{0.25, -0.25}, red},
	{{0.25, 0.25}, red},
	{{-0.25, 0.25}, red},
}

// TODO-Matt: make indices into a slice of glsl.vec3?
INDICES_DATA := []u32{0, 1, 2, 2, 3, 0, 4, 5, 6, 6, 7, 4, 8, 9, 10, 10, 11, 8}

vertices_global := VERTEX_DATA[0:12]
indices_global := INDICES_DATA[0:18]
frame_count := 0

main :: proc() {
	renderer := setup_renderer()

	// main loop
	for !glfw.WindowShouldClose(renderer.window) {
		glfw.PollEvents()
		draw_frame(&renderer, vertices_global, indices_global)

		frame_count += 1
		if frame_count % 2 == 0 {
			vertices_global = VERTEX_DATA[0:12]
			indices_global = INDICES_DATA[0:18]
		} else {
			vertices_global = VERTEX_DATA[0:8]
			indices_global = INDICES_DATA[0:12]
		}
		time.sleep(time.Second)
	}

	vk.DeviceWaitIdle(renderer.device)
	teardown_renderer(&renderer)
}
