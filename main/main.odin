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
		{ 	// handle ball hitting paddle
			if game.ball_vel_y > 0 &&
			   ball_intersects_horizontal(
				   game,
				   game.paddle_pos_x - PADDLE_WIDTH / 2,
				   game.paddle_pos_x + PADDLE_WIDTH / 2,
				   1 - PADDLE_BOTTOM_MARGIN,
			   ) {
				game.ball_pos_y = 1 - PADDLE_BOTTOM_MARGIN - BALL_HEIGHT / 2
				game.ball_vel_y *= -1
			} else if game.ball_vel_x > 0 &&
			   ball_intersects_vertical(
				   game,
				   1 - PADDLE_BOTTOM_MARGIN,
				   1 - PADDLE_BOTTOM_MARGIN + PADDLE_HEIGHT,
				   game.paddle_pos_x - PADDLE_WIDTH / 2,
			   ) {
				game.ball_pos_x = game.paddle_pos_x - PADDLE_WIDTH / 2 - BALL_WIDTH / 2
				game.ball_vel_x *= -1
			} else if game.ball_vel_x < 0 &&
			   ball_intersects_vertical(
				   game,
				   1 - PADDLE_BOTTOM_MARGIN,
				   1 - PADDLE_BOTTOM_MARGIN + PADDLE_HEIGHT,
				   game.paddle_pos_x + PADDLE_WIDTH / 2,
			   ) {
				game.ball_pos_x = game.paddle_pos_x + PADDLE_WIDTH / 2 + BALL_WIDTH / 2
				game.ball_vel_x *= -1
			}
		}
		{ 	// handle ball hitting blocks
			for &block_line, row_index in game.block_grid {
				for &block, col_index in block_line {
					if !block.exists {continue}
					if game.ball_vel_y > 0 &&
					   ball_intersects_horizontal(
						   game,
						   -1 + cast(f32)col_index * BLOCK_WIDTH,
						   -1 + cast(f32)(col_index + 1) * BLOCK_WIDTH,
						   -1 + BLOCK_TOP_MARGIN + cast(f32)row_index * BLOCK_HEIGHT,
					   ) {
						block.exists = false
						game.ball_vel_y *= -1
					} else if game.ball_vel_y < 0 &&
					   ball_intersects_horizontal(
						   game,
						   -1 + cast(f32)col_index * BLOCK_WIDTH,
						   -1 + cast(f32)(col_index + 1) * BLOCK_WIDTH,
						   -1 + BLOCK_TOP_MARGIN + cast(f32)(row_index + 1) * BLOCK_HEIGHT,
					   ) {
						block.exists = false
						game.ball_vel_y *= -1
					} else if game.ball_vel_x > 0 &&
					   ball_intersects_vertical(
						   game,
						   -1 + BLOCK_TOP_MARGIN + cast(f32)row_index * BLOCK_HEIGHT,
						   -1 + BLOCK_TOP_MARGIN + cast(f32)(row_index + 1) * BLOCK_HEIGHT,
						   -1 + cast(f32)col_index * BLOCK_WIDTH,
					   ) {
						block.exists = false
						game.ball_vel_x *= -1
					} else if game.ball_vel_x < 0 &&
					   ball_intersects_vertical(
						   game,
						   -1 + BLOCK_TOP_MARGIN + cast(f32)row_index * BLOCK_HEIGHT,
						   -1 + BLOCK_TOP_MARGIN + cast(f32)(row_index + 1) * BLOCK_HEIGHT,
						   -1 + cast(f32)(col_index + 1) * BLOCK_WIDTH,
					   ) {
						block.exists = false
						game.ball_vel_x *= -1
					}
				}
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

ball_intersects_horizontal :: proc(game: GameState, xleft, xright, y: f32) -> bool {
	if xleft > xright {panic("left must not be greater than right")}
	if game.ball_pos_y + BALL_HEIGHT < y || game.ball_pos_y - BALL_HEIGHT > y {return false}
	if game.ball_pos_x + BALL_WIDTH < xleft || game.ball_pos_x - BALL_WIDTH > xright {return false}
	return true
}

ball_intersects_vertical :: proc(game: GameState, ytop, ybottom, x: f32) -> bool {
	if ytop > ybottom {panic("top must not be greater than bottom")}
	if game.ball_pos_x + BALL_WIDTH < x || game.ball_pos_x - BALL_WIDTH > x {return false}
	if game.ball_pos_y + BALL_HEIGHT < ytop ||
	   game.ball_pos_y - BALL_WIDTH > ybottom {return false}
	return true
}
