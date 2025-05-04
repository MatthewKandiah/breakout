package main

import ma "vendor:miniaudio"

SoundState :: struct {
	engine: ma.engine,
}

setup_sound :: proc() -> SoundState {
  sound: SoundState
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
