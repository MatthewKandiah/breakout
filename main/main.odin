package main

import "core:fmt"
import "vendor:glfw"
import vk "vendor:vulkan"

main :: proc() {
	renderer := setup_renderer()

	// main loop
	for !glfw.WindowShouldClose(renderer.window) {
		glfw.PollEvents()
		draw_frame(&renderer)
	}
	vk.DeviceWaitIdle(renderer.device)

	teardown_renderer(&renderer)
}
