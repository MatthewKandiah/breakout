package main

import "core:fmt"
import "core:math/linalg/glsl"

BLOCK_GRID_WIDTH :: 20
BLOCK_GRID_HEIGHT :: 8
BLOCK_TOP_MARGIN: f32 : 1.0 / 30.0
BLOCK_WIDTH: f32 : 2.0 / BLOCK_GRID_WIDTH
BLOCK_HEIGHT: f32 : BLOCK_WIDTH / 1.5

PADDLE_WIDTH: f32 : 0.35
PADDLE_HEIGHT :: 0.05
PADDLE_COLOUR :: cyan
PADDLE_BOTTOM_MARGIN :: 0.3 + PADDLE_HEIGHT
PADDLE_SPEED :: 0.0025

BALL_WIDTH :: 0.05
BALL_HEIGHT :: 0.05
BALL_COLOUR :: white
BALL_SPEED :: 0.00025

BACKGROUND_COLOUR :: grey

GameState :: struct {
	ball_pos_x:   f32,
	ball_pos_y:   f32,
	ball_vel_x:   f32,
	ball_vel_y:   f32,
	paddle_pos_x: f32,
	block_grid:   [BLOCK_GRID_HEIGHT][BLOCK_GRID_WIDTH]Block,
}

Block :: struct {
	exists: bool,
	colour: glsl.vec3,
}

setup_game :: proc() -> (game: GameState) {
	game.paddle_pos_x = 0
	game.ball_pos_x = 0
	game.ball_pos_y = 1 - PADDLE_BOTTOM_MARGIN - PADDLE_HEIGHT / 2
	game.ball_vel_x = BALL_SPEED
	game.ball_vel_y = -BALL_SPEED
	for j in 0 ..< BLOCK_GRID_HEIGHT {
		for i in 0 ..< BLOCK_GRID_WIDTH {
			game.block_grid[j][i] = {
				exists = j != 3 && j != 4,
				colour = red if (i + j) % 2 == 0 else yellow,
			}
		}
	}
	return game
}

get_drawing_data :: proc(game: GameState) -> (vertices: []Vertex, indices: []u32) {
	vertex_count: u32 = 0
	index_count: u32 = 0

	{ 	// draw blocks
		for block_line, row_index in game.block_grid {
			for block, col_index in block_line {
				if !block.exists {continue}
				base_x: f32 = -1 + cast(f32)col_index * BLOCK_WIDTH
				base_y: f32 = -1 + cast(f32)row_index * BLOCK_HEIGHT + BLOCK_TOP_MARGIN
				colour := red if (row_index + col_index) % 2 == 0 else yellow
				vertex_backing_array[vertex_count] = {
					pos = {base_x, base_y},
					col = colour,
				}
				vertex_backing_array[vertex_count + 1] = {
					pos = {base_x + BLOCK_WIDTH, base_y},
					col = colour,
				}
				vertex_backing_array[vertex_count + 2] = {
					pos = {base_x + BLOCK_WIDTH, base_y + BLOCK_HEIGHT},
					col = colour,
				}
				vertex_backing_array[vertex_count + 3] = {
					pos = {base_x, base_y + BLOCK_HEIGHT},
					col = colour,
				}

				index_backing_array[index_count] = vertex_count
				index_backing_array[index_count + 1] = vertex_count + 1
				index_backing_array[index_count + 2] = vertex_count + 2
				index_backing_array[index_count + 3] = vertex_count + 2
				index_backing_array[index_count + 4] = vertex_count + 3
				index_backing_array[index_count + 5] = vertex_count

				vertex_count += 4
				index_count += 6
			}
		}
	}

	{ 	// draw paddle
		base_x: f32 = game.paddle_pos_x - PADDLE_WIDTH / 2
		base_y: f32 = 1 - PADDLE_BOTTOM_MARGIN
		vertex_backing_array[vertex_count] = {
			pos = {base_x, base_y},
			col = PADDLE_COLOUR,
		}
		vertex_backing_array[vertex_count + 1] = {
			pos = {base_x + PADDLE_WIDTH, base_y},
			col = PADDLE_COLOUR,
		}
		vertex_backing_array[vertex_count + 2] = {
			pos = {base_x + PADDLE_WIDTH, base_y + PADDLE_HEIGHT},
			col = PADDLE_COLOUR,
		}
		vertex_backing_array[vertex_count + 3] = {
			pos = {base_x, base_y + PADDLE_HEIGHT},
			col = PADDLE_COLOUR,
		}

		index_backing_array[index_count] = vertex_count
		index_backing_array[index_count + 1] = vertex_count + 1
		index_backing_array[index_count + 2] = vertex_count + 2
		index_backing_array[index_count + 3] = vertex_count + 2
		index_backing_array[index_count + 4] = vertex_count + 3
		index_backing_array[index_count + 5] = vertex_count

		vertex_count += 4
		index_count += 6
	}

	{ 	// draw ball
		base_x: f32 = game.ball_pos_x - BALL_WIDTH / 2
		base_y: f32 = game.ball_pos_y - BALL_HEIGHT / 2
		vertex_backing_array[vertex_count] = {
			pos = {base_x, base_y},
			col = BALL_COLOUR,
		}
		vertex_backing_array[vertex_count + 1] = {
			pos = {base_x + BALL_WIDTH, base_y},
			col = BALL_COLOUR,
		}
		vertex_backing_array[vertex_count + 2] = {
			pos = {base_x + BALL_WIDTH, base_y + BALL_HEIGHT},
			col = BALL_COLOUR,
		}
		vertex_backing_array[vertex_count + 3] = {
			pos = {base_x, base_y + BALL_HEIGHT},
			col = BALL_COLOUR,
		}

		index_backing_array[index_count] = vertex_count
		index_backing_array[index_count + 1] = vertex_count + 1
		index_backing_array[index_count + 2] = vertex_count + 2
		index_backing_array[index_count + 3] = vertex_count + 2
		index_backing_array[index_count + 4] = vertex_count + 3
		index_backing_array[index_count + 5] = vertex_count

		vertex_count += 4
		index_count += 6
	}
	return vertex_backing_array[0:vertex_count], index_backing_array[0:index_count]
}
