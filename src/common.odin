package main

import "core:mem"
import "core:strings"
import "core:mem/virtual"
import spall "spall-wrapper"
import clay "clay-odin"
import sdl "vendor:sdl3"
import mix "vendor:sdl3/mixer"

TARGET_FPS :: 60.0
TARGET_NS :: 1000000000.0 / TARGET_FPS

UI_Button :: enum {
  PLAY = 0,
  RANDOMIZE,
  LOOP_CURRENT,
  PAUSE,
  PLUS,
  MINUS,
  OPEN_DIR,
  OPEN_DIR_PLUS,
}

SongSourceType :: enum {
  None, /* no song source */
  File, /* song is stored locally */
  Folder, /* song is stored locally in a folder */
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
  arena: virtual.Arena,
  arena_allocator: mem.Allocator,

  window: ^sdl.Window,
  renderer: ^sdl.Renderer,
  windowWidth, windowHeight: i32,
  clay_renderData: Clay_SDL3RendererData,

  iconSpritesheet: SpritesheetData,
  imageData: List(Clay_ImageRenderData),

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

  songlist: strings.Builder,
  playlistFileAbsPath: cstring,

  eventFilterData: EventFilterData,
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

// linked list with free list
ListNode :: struct($Type: typeid) {
  next: ^ListNode(Type),
  data: Type,
}

List :: struct($Type: typeid) {
  head: ^ListNode(Type),
  tail: ^ListNode(Type),
  free: ^ListNode(Type),
}

List_Append :: proc(l: ^List($ListType), data: ListType, allocator: mem.Allocator) -> ^ListType
{
  node: ^ListNode(ListType)
  if l.free != nil {
    node = l.free
    l.free = l.free.next
  } else {
    node = new(ListNode(ListType), allocator)
  }
  node.data = data
  if l.tail != nil {
    l.tail.next = node
  } else {
    l.head = node
  }
  l.tail = node
  
  return &node.data
}

// Append to the start
List_Prepend :: proc(l: ^List($ListType), data: ListType, allocator: mem.Allocator) -> ^ListType
{
  node: ^ListNode(ListType)
  if l.free != nil {
    node = l.free
    l.free = l.free.next
  } else {
    node = new(ListNode(ListType), allocator)
  }
  node.next = l.head
  node.data = data
  if l.head == nil {
    l.tail = node
  }
  l.head = node

  return &node.data
}

List_FreeNode :: proc "contextless"(l: ^List($ListType), node: ^ListNode(ListType))
{
  prev: ^ListNode(ListType)
  found := false
  for n := l.head; n != nil; n = n.next {
    if n == node {
      found = true
      break
    }
    prev = n
  }

  if found {
    if prev != nil {
      prev.next = node.next
    } else {
      l.head = node.next
    }
    node.next = l.free
    l.free = node
  }
}

List_FreeAll :: proc "contextless"(l: ^List($ListType))
{
  if l.tail != nil {
    l.tail.next = l.free
    l.free = l.head
    l.head = nil
    l.tail = nil
  }
}

// NOTE: I won't use this since I'll be keeping the nodes in an arena
List_FreeAllMem :: proc(l: ^List($ListType), allocator: mem.Allocator)
{
  next: ^ListNode($ListType)
  for node := l.head; node != nil; node = next {
    next = node.next
    free(node, allocator)
  }
  for node := l.free; node != nil; node = next {
    next = node.next
    free(node, allocator)
  }
  l.head = nil
  l.free = nil
  l.tail = nil
}
