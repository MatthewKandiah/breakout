package main

import "core:fmt"
import "core:time"
import "vendor:glfw"
import vk "vendor:vulkan"

vertex_backing_array: [VERTEX_BUFFER_LEN]Vertex
index_backing_array: [INDEX_BUFFER_LEN]u32
vertices: []Vertex
indices: []u32

// TODO-Matt: a bunch of this key handling and state updating should probably move to game.odin
KeysState :: struct {
	left_held:  bool,
	right_held: bool,
}

keys_state: KeysState

main :: proc() {
	renderer := setup_renderer()
	game := setup_game()

	glfw.SetKeyCallback(renderer.window, key_callback)

	start_time: i64 = time.now()._nsec
	finish_time: i64 = time.now()._nsec
	for !glfw.WindowShouldClose(renderer.window) {
		glfw.PollEvents()
		{ 	// update state
			finish_time = time.now()._nsec
			delta_t := cast(f32)(finish_time - start_time) / 1_000_000
			start_time = finish_time
			if keys_state.left_held && !keys_state.right_held {
				game.paddle_pos_x = clamp(game.paddle_pos_x - PADDLE_SPEED * delta_t, -1, 1)
			}
			if keys_state.right_held && !keys_state.left_held {
				game.paddle_pos_x = clamp(game.paddle_pos_x + PADDLE_SPEED * delta_t, -1, 1)
			}
			// updating ball position - dumbly assume the ball won't move far enough to warp through a block in a single tick
			game.ball_pos_x += game.ball_vel_x
			if game.ball_pos_x > 1 {
				game.ball_pos_x = 1
				game.ball_vel_x *= -1
			} else if game.ball_pos_x < -1 {
				game.ball_pos_x = -1
				game.ball_vel_x *= -1
			}
			game.ball_pos_y += game.ball_vel_y
			if game.ball_pos_y > 1 {
				game.ball_pos_y = 1
				game.ball_vel_y *= -1
			} else if game.ball_pos_y < -1 {
				game.ball_pos_y = -1
				game.ball_vel_y *= -1
			}
		}
		vertices, indices = get_drawing_data(game)
		draw_frame(&renderer, vertices, indices)
	}

	vk.DeviceWaitIdle(renderer.device)
	teardown_renderer(&renderer)
}

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
