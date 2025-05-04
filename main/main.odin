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
		if quads_overlap(
			game.ball_pos_x,
			game.ball_pos_y,
			BALL_WIDTH,
			BALL_HEIGHT,
			game.paddle_pos_x,
			1 - PADDLE_BOTTOM_MARGIN + PADDLE_HEIGHT / 2,
			PADDLE_WIDTH,
			PADDLE_HEIGHT,
		) {
			// TODO-Matt: we're going to need to handle side and bottom collisions for blocks anyway, might as well work it out and handle it here
			// handle ball-paddle collision:
			// planning to just make the ball fast and not differentiate side hits from top hits for simplicity, hopefully it just feels like you got there just in time!
			// also no need to handle bottom hits because hitting the bottom of the screen will make you lose!
			game.ball_pos_y = 1 - PADDLE_BOTTOM_MARGIN - BALL_HEIGHT / 2
			game.ball_vel_y *= -1
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

quads_overlap :: proc(x1, y1, width1, height1, x2, y2, width2, height2: f32) -> bool {
	lt1x := x1 - width1 / 2
	lt1y := y1 - height1 / 2
	rb1x := x1 + width1 / 2
	rb1y := y1 + height1 / 2

	lt2x := x2 - width2 / 2
	lt2y := y2 - height2 / 2
	rb2x := x2 + width2 / 2
	rb2y := y2 + height2 / 2

	if rb1y < lt2y || rb2y < lt1y {return false}
	if lt1x > rb2x || lt2x > rb1x {return false}
	return true
}
