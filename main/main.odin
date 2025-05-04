package main

import "core:fmt"
import "core:time"
import "vendor:glfw"
import ma "vendor:miniaudio"
import vk "vendor:vulkan"

vertex_backing_array: [VERTEX_BUFFER_LEN]Vertex
index_backing_array: [INDEX_BUFFER_LEN]u32
vertices: []Vertex
indices: []u32

KeysState :: struct {
	left_held:  bool,
	right_held: bool,
}
keys_state: KeysState
key_callback :: proc "c" (
	window: glfw.WindowHandle,
	key: i32,
	scancode: i32,
	action: i32,
	mods: i32,
) {
	if key == glfw.KEY_LEFT {
		if action == glfw.PRESS {
			keys_state.left_held = true
		} else if action == glfw.RELEASE {
			keys_state.left_held = false
		}
	}
	if key == glfw.KEY_RIGHT {
		if action == glfw.PRESS {
			keys_state.right_held = true
		} else if action == glfw.RELEASE {
			keys_state.right_held = false
		}
	}
}

beep_file_path :: "beep.wav"

main :: proc() {
	renderer := setup_renderer()
	game := setup_game()
	sound := setup_sound()

	glfw.SetKeyCallback(renderer.window, key_callback)

	start_time: i64 = time.now()._nsec
	finish_time: i64 = time.now()._nsec
	for !glfw.WindowShouldClose(renderer.window) && game.running {
		glfw.PollEvents()
		finish_time = time.now()._nsec
		delta_t := cast(f32)(finish_time - start_time) / 1_000_000
		start_time = finish_time
		update_state(&game, keys_state, delta_t, &sound)
		vertices, indices = get_drawing_data(game)
		draw_frame(&renderer, vertices, indices)
	}

	vk.DeviceWaitIdle(renderer.device)
	teardown_renderer(&renderer)
}
