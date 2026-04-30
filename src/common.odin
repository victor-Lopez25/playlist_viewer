package main

import "base:runtime"
import spall "spall-wrapper"
import clay "clay-odin"
import sdl "vendor:sdl3"
import mix "vendor:sdl3/mixer"

TARGET_FPS :: 60.0
TARGET_NS :: 1000000000.0 / TARGET_FPS

SongSourceType :: enum {
  None, /* no song source */
  File, /* song is stored locally */
  Link, /* need to look for the song online */
}

SongData :: struct {
  group, name, album: string,
  filename: string,
  source: string,
  sourceType: SongSourceType,
  gotMetadata: bool,
}

ConfigHeader :: struct {
  stringTableOffset: u32,
  volume: f32,
}

ConfigFileInfo :: struct {
  header: ConfigHeader,

  defaultSongDirectory: string,
  currentSongPlaylist: string,
}

Playlist :: struct {
  songData: [dynamic]SongData, // NOTE: Should keep original order
  songs: [dynamic]^SongData,
  name: string,
  playingSongIdx: int,
  playingSongChanged: bool,
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

  defaultConfig: ConfigFileInfo,
  volume: f32,
  playlist: Playlist,
  spall_backing_buffer: []u8,
  quit: bool,

  mixer: ^mix.Mixer,
  musicAudio: ^mix.Audio,
  musicTrack: ^mix.Track,
  musicTimeLength: sdl.Sint64, /* in frames */
  musicTimeLengthMs: sdl.Sint64, /* in milliseconds */
  musicTimePlayed: sdl.Sint64, /* in frames */
  musicTimePlayedMs: sdl.Sint64, /* in milliseconds */
  musicSliderValue: f32,
  musicLooping: bool,
  musicLoaded: bool,
  musicPause: bool,

  sliderSelected: clay.ElementId,

  playlistFileAbsPath: cstring,

  eventFilterData: struct { app: ^AppData, input: ^Input, Context: runtime.Context },
}

Input :: struct {
  deltaTime: f32,
  mouseWheel: [2]f32,
  mousePos: [2]f32,
  mouseLeftDown: bool,
  mouseLeftReleased: bool,
  altDown: bool,
  ctrlDown: bool,
  shiftDown: bool,

  ignoreMissedFPS: bool,

  keyDown: #sparse[sdl.Scancode]bool,
  keyPressed: #sparse[sdl.Scancode]bool,
}
