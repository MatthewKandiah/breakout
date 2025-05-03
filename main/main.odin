package main

import "core:fmt"
import "core:time"
import "vendor:glfw"
import vk "vendor:vulkan"

vertex_backing_array: [VERTEX_BUFFER_LEN]Vertex
index_backing_array: [INDEX_BUFFER_LEN]u32
vertices: []Vertex
indices: []u32

main :: proc() {
	renderer := setup_renderer()
	game := setup_game()
	// main loop
	for !glfw.WindowShouldClose(renderer.window) {
		glfw.PollEvents()
		vertices, indices = get_drawing_data(game)
		draw_frame(&renderer, vertices, indices)
	}

	vk.DeviceWaitIdle(renderer.device)
	teardown_renderer(&renderer)
}
