package main

import ma "vendor:miniaudio"

SoundState :: struct {
	engine: ^ma.engine,
}

setup_sound :: proc() -> (sound: SoundState) {
	sound.engine = new(ma.engine)
	if res := ma.engine_init(nil, sound.engine); res != .SUCCESS {
		panic("failed to init miniaudio engine")
	}
	return sound
}

teardown_sound :: proc(sound: SoundState) {
	free(sound.engine)
}

play_sound :: proc(sound: SoundState, path: cstring) {
	if res := ma.engine_play_sound(sound.engine, path, nil); res != .SUCCESS {
		panic("failed to play sound")
	}
}
