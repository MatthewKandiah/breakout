package textiler

import "core:fmt"
import stbi "vendor:stb/image"

NUM_TEXTURES :: 3
IMAGE_NAMES := [NUM_TEXTURES]cstring{"brick.png", "metal.png", "smiley.png"}
OUTPUT_FILENAME :: "textures.png"

main :: proc() {
	widths, heights, channel_counts: [NUM_TEXTURES]i32
	inputs_data: [NUM_TEXTURES][^]u8
	for i in 0 ..< len(IMAGE_NAMES) {
		input := stbi.load(IMAGE_NAMES[i], &widths[i], &heights[i], &channel_counts[i], 0)
		if input == nil {
			fmt.println("failed for:", IMAGE_NAMES[i])
			panic("Failed to read image")
		}
		inputs_data[i] = input
	}

	output_width: i32 = 0
	for width in widths {
		output_width += width
	}
	output_height: i32 = 0
	for height in heights {
		if height > output_height {
			output_height = height
		}
	}

	output := make([]u8, 4 * output_width * output_height)
	x_displacement: i32 = 0
	fmt.println("Texture coordinates:")
	for i in 0 ..< NUM_TEXTURES {
		input_data := inputs_data[i]
		width := widths[i]
		height := heights[i]
		channel_count := channel_counts[i]
		fmt.println(IMAGE_NAMES[i])
		fmt.println("\tx =", x_displacement, "y =", 0, "width = ", width, "height =", height)

		if channel_count == 3 {
			for row_idx in 0 ..< height {
				for col_idx in 0 ..< width {
					base_output_idx := 4 * (x_displacement + col_idx + output_width * row_idx)
					base_input_idx := 3 * (col_idx + width * row_idx)
					output[base_output_idx + 0] = input_data[base_input_idx + 0]
					output[base_output_idx + 1] = input_data[base_input_idx + 1]
					output[base_output_idx + 2] = input_data[base_input_idx + 2]
					output[base_output_idx + 3] = 0xFF
				}
			}
		} else if channel_count == 4 {
			for row_idx in 0 ..< height {
				for col_idx in 0 ..< width {
					base_output_idx := 4 * (x_displacement + col_idx + output_width * row_idx)
					base_input_idx := 4 * (col_idx + width * row_idx)
					output[base_output_idx + 0] = input_data[base_input_idx + 0]
					output[base_output_idx + 1] = input_data[base_input_idx + 1]
					output[base_output_idx + 2] = input_data[base_input_idx + 2]
					output[base_output_idx + 3] = input_data[base_input_idx + 3]
				}
			}
		} else {
			panic("unsupported channel count")
		}
		x_displacement += width
	}

	if res := stbi.write_png(
		OUTPUT_FILENAME,
		output_width,
		output_height,
		4,
		raw_data(output),
		4 * output_width,
	); res == 0 {
		panic("failed to write output to file")
	}
}
