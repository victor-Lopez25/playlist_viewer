package main

import "base:runtime"
import "core:prof/spall"
import clay "clay-odin"
import sdl "vendor:sdl3"

SongSourceType :: enum {
  None, /* no song source */
  File, /* song is stored locally */
  Link, /* need to look for the song online */
}

SongData :: struct {
  group, name, album: string,
  source: string,
  sourceType: SongSourceType,
}

Playlist :: struct {
  songData: [dynamic]SongData, // NOTE: Should keep original order
  songs: [dynamic]^SongData,
  name: string,
  activeSongIdx: int,
  activeSongChanged: bool,
}

AppData :: struct {
  spall_ctx: spall.Context,
  spall_buffer: spall.Buffer, // NOTE: This must be one per thread

  window: ^sdl.Window,
  renderer: ^sdl.Renderer,
  windowWidth, windowHeight: i32,
  clay_renderData: Clay_SDL3RendererData,

  volume: f32,
  playlist: Playlist,
  spall_backing_buffer: []u8,
  quit: bool,

  //music: ray.Music,
  musicTimeLength: f32,
  musicTimePlayed: f32,
  musicSliderValue: f32,
  musicLoaded: bool,
  musicPause: bool,

  sliderSelected: clay.ElementId,

  playlistFileAbsPath: string,

  eventFilterData: struct { app: ^AppData, input: ^Input, Context: runtime.Context },
}

Input :: struct {
  deltaTime: f32,
  mouseWheel: [2]f32,
  mousePos: [2]f32,
  mouseLeftDown: bool,
  mouseLeftReleased: bool,
}
