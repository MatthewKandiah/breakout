package main

import ma "vendor:miniaudio"

SoundState :: struct {
	engine: ma.engine,
}

// TODO-Matt: why does this #force_inline fix the segfault?
setup_sound :: #force_inline proc() -> (sound: SoundState) {
	if res := ma.engine_init(nil, &sound.engine); res != .SUCCESS {
		panic("failed to init miniaudio engine")
	}
  return sound
}

play_sound :: proc(sound: ^SoundState, path: cstring) {
	if res := ma.engine_play_sound(&sound.engine, path, nil); res != .SUCCESS {
		panic("failed to play sound")
	}
}
