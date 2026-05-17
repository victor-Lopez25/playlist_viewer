package main

import "base:runtime"

import "core:c"
import "core:os"
import "core:fmt"
import "core:mem"
import "core:sync"
import "core:slice"
import "core:strings"
import "core:math/rand"
import "core:mem/virtual"
import "core:path/slashpath"

import spall "spall-wrapper"

import sdl "vendor:sdl3"
import "vendor:sdl3/ttf"
import mix "vendor:sdl3/mixer"

CONFIG_FILE_NAME :: "pv.cfg"

SortSongData :: proc(songs: []SongData)
{
  groupLess :: proc(i, j: SongData) -> bool { return i.group < j.group }
  albumLess :: proc(i, j: SongData) -> bool { return i.album < j.album }
  nameLess  :: proc(i, j: SongData) -> bool { return i.name < j.name   }

  slice.sort_by(songs, groupLess)

  prev := songs[0]
  prevIdx := 0
  counter := 0
  for i := 0; i < len(songs); i += 1
  {
    if songs[i].group != prev.group {
      if i - prevIdx > 1 {
        slice.sort_by(songs[prevIdx:i], albumLess)
        counter += 1
      }
      prev = songs[i]
      prevIdx = i
    }
  }

  prev = songs[0]
  prevIdx = 0
  counter = 0
  for i := 0; i < len(songs); i += 1
  {
    if songs[i].group != prev.group || songs[i].album != prev.album {
      if i - prevIdx > 1 {
        slice.sort_by(songs[prevIdx:i], nameLess)
        counter += 1
      }
      prev = songs[i]
      prevIdx = i
    }
  }
}

CheckMusicFileExt :: proc(ext: string, include_dot: bool) -> bool
{
  if(include_dot) {
    return (ext == ".mp3" || ext == ".ogg" || ext == ".qoa" || ext == ".xm" || ext == ".mod" || ext == ".wav")
  } else {
    return (ext == "mp3" || ext == "ogg" || ext == "qoa" || ext == "xm" || ext == "mod" || ext == "wav")
  }
}

CountSongs :: proc(songs: []SongData)
{
  prevGroup := songs[0].group
  prevIdx := 0
  for i := 0; i < len(songs); i += 1
  {
    if songs[i].group != prevGroup {
      fmt.printfln("%s: %d songs", prevGroup, i - prevIdx)
      prevGroup = songs[i].group
      prevIdx = i
    }
  }
  fmt.printfln("%s: %d songs", songs[len(songs)-1].group, len(songs) - prevIdx)
}

PrintSongs :: proc(songs: []SongData)
{
  for i := 0; i < len(songs); i += 1
  {
    s := songs[i]
    if s.album == "" {
      fmt.printfln("%s - %s", s.group, s.name)
    }
    else {
      fmt.printfln("%s - %s - %s", s.group, s.album, s.name)
    }
  }
}

ParseSongs :: proc(app: ^AppData, data: []u8)
{
  spall.SCOPED_EVENT(&app.spall_ctx, &app.spall_buffer, #procedure)

  source := string(data)
  lineIdx := 0
  for line in strings.split_lines_iterator(&source) {
    lineIdx += 1
    // NOTE: Ignore empty lines which might be inserted for whatever reason
    if line == "" do continue

    if !os.exists(line) {
      sdl.Log("Error in line %d: Could not find music file '%s', ignoring this file...", lineIdx, line)
      continue
    }

    if !CheckMusicFileExt(os.ext(line), include_dot = true) {
      sdl.Log("Error in line %d: '%s' is not a music file, ignoring this file...", lineIdx, line)
      continue
    }

    song := SongData {
      // NOTE: Metadata will be read when the song gets loaded
      name = "",
      group = "",
      album = "",
      filename = os.short_stem(line),
      source = line,
      sourceType = .File,
    }
    append(&app.playlist.songData, song)
  }
}

LoadMusicFromFile :: proc(app: ^AppData, file: cstring)
{
  prevAudio := app.musicAudio
  app.musicAudio = mix.LoadAudio_IO(app.mixer, sdl.IOFromFile(file, "rb"), 
                               predecode = false, closeio = true)
  if app.musicAudio == nil {
    sdl.Log("Could not load music audio: %s", sdl.GetError())
  } else {
    if !mix.SetTrackAudio(app.musicTrack, app.musicAudio) {
      sdl.Log("Could not set track audio: %s", sdl.GetError())
    } else {
      if mix.PlayTrack(app.musicTrack, 0) {
        app.musicLoaded = true
        app.musicPause = false
        if prevAudio != nil {
          mix.DestroyAudio(prevAudio)
        }
      } else {
        sdl.Log("Could not play music: %s", sdl.GetError())
      }
    }
  }
}

GetAudioMetadataForSong :: proc(song: ^SongData, audio: ^mix.Audio, allocator: mem.Allocator)
{
  if song.gotMetadata {
    return
  }
  song.gotMetadata = true
  propId := mix.GetAudioProperties(audio)
  if propId != 0 {
    prop := sdl.GetStringProperty(propId, mix.PROP_METADATA_TITLE_STRING, nil)
    if prop != nil {
      song.name = strings.clone_from_cstring(prop, allocator)
    } else {
      song.name = song.filename
    }
    prop = sdl.GetStringProperty(propId, mix.PROP_METADATA_ARTIST_STRING, nil)
    if prop != nil {
      song.group = strings.clone_from_cstring(prop, allocator)
    } else {
      song.group = ""
    }
    prop = sdl.GetStringProperty(propId, mix.PROP_METADATA_ALBUM_STRING, nil)
    if prop != nil {
      song.album = strings.clone_from_cstring(prop, allocator)
    } else {
      song.album = ""
    }
  } else {
    song.name = song.filename
    song.group = ""
    song.album = ""
  }
}

ChangeLoadedMusicStream :: proc(app: ^AppData, newIdx: int)
{
  spall.SCOPED_EVENT(&app.spall_ctx, &app.spall_buffer, #procedure)

  playlist := &app.playlist
  if playlist.songs[playlist.playingSongIdx].source != "" {
    if app.musicLoaded {
      app.musicLoaded = false
    }

    activeSong := playlist.songs[newIdx]
    switch activeSong.sourceType {
      case .None: assert(false, "unreachable")
      case .Link: {
        assert(false, "unimplemented")
      }
      case .File: {
        if os.exists(activeSong.source) {
          filename := strings.clone_to_cstring(activeSong.source, context.temp_allocator)
          LoadMusicFromFile(app, filename)
        } else {
          b: strings.Builder = strings.builder_make_len_cap(0, 40, context.temp_allocator)
          filepath := fmt.sbprintf(&b, "../songs/%s", activeSong.source)
          if os.exists(filepath) {
            file, _ := strings.to_cstring(&b)
            LoadMusicFromFile(app, file)
          } else {
            fmt.println("Could not find song")
          }
        }
      }
    }

    // NOTE: Gather 'static' data from app.music here
    app.musicTimeLength = mix.GetAudioDuration(app.musicAudio)
    app.musicTimePlayed = 0.0
    app.musicTimeLengthMs = mix.TrackFramesToMS(app.musicTrack, app.musicTimeLength)

    // NOTE: If not found, song name will be the name of the file with the extension removed
    song: ^SongData = app.playlist.songs[app.playlist.playingSongIdx]
    GetAudioMetadataForSong(song, app.musicAudio, app.arena_allocator)
  }
}

AddSongsToList :: proc(app: ^AppData, listFile: cstring) -> bool
{
  if listFile == nil || listFile == "" do return false

  pathinfo: sdl.PathInfo
  ok := sdl.GetPathInfo(listFile, &pathinfo)
  if !ok do return false

  ReadDirectoryData :: struct {
    ctx: runtime.Context,
    songData: ^[dynamic]SongData,
    allocator: ^mem.Allocator,
  }
  ReadDirectoryFile :: proc "c"(rawdata: rawptr, dirname, fname: cstring) -> sdl.EnumerationResult
  {
    data := cast(^ReadDirectoryData)rawdata
    context = data.ctx

    name := string(fname)
    fullpath := slashpath.join({string(dirname), name}, data.allocator^)
    ext := os.ext(name)
    isfile := os.is_file(fullpath)

    if isfile && CheckMusicFileExt(ext, include_dot = true) {
      song := SongData{
        // NOTE: Metadata will be read when the song gets loaded
        group = "",
        name = "",
        album = "",
        filename = os.short_stem(fullpath),
        source = fullpath,
        sourceType = .File,
      }
      append(data.songData, song)
    }

    return .CONTINUE
  }

  if pathinfo.type == .DIRECTORY {
    data := ReadDirectoryData{
      ctx = context,
      songData = &app.playlist.songData,
      allocator = &app.arena_allocator,
    }
    ok = sdl.EnumerateDirectory(listFile, ReadDirectoryFile, &data)
  } else {
    size: uint
    rawdata := sdl.LoadFile(listFile, &size)
    data := slice.from_ptr(cast(^u8)rawdata, int(size))
    if ok {
      ParseSongs(app, data)
      app.playlistFileAbsPath = listFile
    }
  }

  if ok {
    resize(&app.playlist.songs, len(app.playlist.songData))
    for i := 0; i < len(app.playlist.songData); i += 1 {
      app.playlist.songs[i] = &app.playlist.songData[i]
    }
  }
  return ok
}

EventFilterData :: struct { app: ^AppData, input: ^Input, Context: runtime.Context }
InputEventFilter :: proc "c"(userdata: rawptr, event: ^sdl.Event) -> bool
{
  prog := cast(^EventFilterData)userdata
  context = prog.Context

  UpdateAndRender :: proc(prog: ^EventFilterData, name: string) {
    // TODO: Figure out what causes the tearing when resizing
    spall.SCOPED_EVENT(&prog.app.spall_ctx, &prog.app.spall_buffer, name)

    Update(prog.app, prog.input)

    // Generate the auto layout for rendering
    UIRenderCommands := UI_Calculate(prog.app, prog.input)

    SDL_RenderClayCommands(&prog.app.clay_renderData, &UIRenderCommands)

    sdl.RenderPresent(prog.app.renderer)
  }

  #partial switch(event.type) {
    case .WINDOW_RESIZED: {
      prog.app.windowWidth = event.window.data1
      prog.app.windowHeight = event.window.data2
      prog.input.ignoreMissedFPS = true
      UpdateAndRender(prog, "Window_Resize Event")
    } break;
    case .WINDOW_MOVED: {
      prog.input.ignoreMissedFPS = true
      UpdateAndRender(prog, "Window_Moved Event")
    } break;
  }
  return true
}

InitSDL3 :: proc(app: ^AppData, input: ^Input) -> bool
{
  spall.SCOPED_EVENT(&app.spall_ctx, &app.spall_buffer, #procedure)
  // NOTE: Any subsystem that isn't video can be initialized in a different thread
  if !sdl.Init({.AUDIO, .VIDEO}) {
    sdl.Log("Could not init sdl: %s", sdl.GetError())
    return false
  }

  when ODIN_DEBUG {
    sdl.SetLogPriorities(.VERBOSE)
  }

  app.windowWidth = 1000
  app.windowHeight = 800
  app.window = sdl.CreateWindow("playlist viewer", app.windowWidth, app.windowHeight, {.RESIZABLE})
  if app.window == nil {
    sdl.Log("Could not create sdl window: %s", sdl.GetError())
    return false
  }
  app.renderer = sdl.CreateRenderer(app.window, nil)
  if app.renderer == nil {
    sdl.Log("Could not create sdl renderer: %s", sdl.GetError())
    return false
  }

  if !ttf.Init() {
    sdl.Log("Could not init sdl_ttf: %s", sdl.GetError())
    return false
  }

  app.clay_renderData.renderer = app.renderer;
  app.clay_renderData.textEngine = ttf.CreateRendererTextEngine(app.clay_renderData.renderer);
  if app.clay_renderData.textEngine == nil {
    sdl.Log("Could not create text engine from renderer: %s", sdl.GetError())
    return false
  }
  app.clay_renderData.fonts = make([]^ttf.Font, 2)
  if app.clay_renderData.fonts == nil {
    sdl.Log("Could not allocate memory for font data")
    return false
  }

  font := ttf.OpenFont("resources/fonts/Inconsolata-Regular.ttf", 16);
  if font == nil {
    sdl.Log("Could not load font: %s", sdl.GetError())
    return false
  }
  app.clay_renderData.fonts[Font_Inconsolata] = font
  font = ttf.OpenFont("resources/fonts/liberation-mono.ttf", 16);
  if font == nil {
    sdl.Log("Could not load font: %s", sdl.GetError())
    return false
  }
  app.clay_renderData.fonts[Font_LiberationMono] = font

  app.eventFilterData.app = app
  app.eventFilterData.input = input
  app.eventFilterData.Context = context
  if !sdl.AddEventWatch(InputEventFilter, &app.eventFilterData) {
    sdl.Log("Could not add sdl event watch: InputEventFilter: %s", sdl.GetError())
    return false
  }

  // Audio
  //sdl.Log("Audio driver: %s", sdl.GetCurrentAudioDriver())
  //sdl.Log("SDL_mixer version: %d", mix.Version())

  if !mix.Init() {
    sdl.Log("Could not init SDL_mixer: %s", sdl.GetError())
    return false
  }

  app.mixer = mix.CreateMixerDevice(sdl.AUDIO_DEVICE_DEFAULT_PLAYBACK, nil)
  if app.mixer == nil {
    sdl.Log("Could not create mixer device: %s", sdl.GetError())
    return false
  }

  app.musicTrack = mix.CreateTrack(app.mixer)
  if app.musicTrack == nil {
    sdl.Log("Could not create music track: %s", sdl.GetError())
    return false
  }
  return true
}

ParseConfigFile :: proc(rawData: []u8) -> (ConfigFileInfo, bool)
{
  data := (cast(^ConfigFileInfo)(&rawData[0]))^

  // 4096 = path max I'm using, could be more?
  data.defaultSongDirectory = 
    strings.string_from_null_terminated_ptr(&rawData[data.header.stringTableOffset], 4096)

  currPlaylistOffset := data.header.stringTableOffset + u32(len(data.defaultSongDirectory)) + 1

  data.currentSongPlaylist = strings.string_from_null_terminated_ptr(&rawData[currPlaylistOffset], 4096)

  return data, true
}

SerializeConfigFile :: proc(app: ^AppData, f: ^os.File)
{
  app.defaultConfig.header.stringTableOffset = size_of(app.defaultConfig.header)
  app.defaultConfig.header.volume = app.volume

  header := slice.bytes_from_ptr(&app.defaultConfig, size_of(app.defaultConfig.header))
  bytesWritten, err := os.write(f, header)
  if err != nil || bytesWritten != size_of(app.defaultConfig.header) {
    fmt.eprintfln("Could not write header into config file: %v", err)
    return
  }

  cstringEnd := [1]u8{0}
  fmt.fprint(f, app.defaultConfig.defaultSongDirectory)
  bytesWritten, err = os.write(f, cstringEnd[:])
  if err != nil || bytesWritten != 1 {
    fmt.eprintfln("Could not write string end into config file: %v", err)
    return
  }

  fmt.fprint(f, app.defaultConfig.currentSongPlaylist)
  bytesWritten, err = os.write(f, cstringEnd[:])
  if err != nil || bytesWritten != 1 {
    fmt.eprintfln("Could not write string end into config file: %v", err)
    return
  }
}

@export
AppInit :: proc(rawApp: rawptr, rawInput: rawptr) -> bool
{
  app := cast(^AppData)rawApp
  input := cast(^Input)rawInput

  ok: bool
  app.spall_ctx, ok = spall.context_create("trace.spall")
  if !ok {
    fmt.eprintln("Could not create Spall context")
    return false
  }
  app.spall_backing_buffer = make([]u8, spall.BUFFER_DEFAULT_SIZE)
  if app.spall_backing_buffer == nil {
    fmt.eprintln("Could not allocate spall backing buffer")
    return false
  }
  app.spall_buffer = spall.buffer_create(app.spall_backing_buffer, u32(sync.current_thread_id()))
  spall.SCOPED_EVENT(&app.spall_ctx, &app.spall_buffer, #procedure)

  alloc_err := virtual.arena_init_growing(&app.arena)
  if alloc_err != nil {
    fmt.eprintfln("Could not init growing arena: %v", alloc_err)
    return false
  }
  app.arena_allocator = virtual.arena_allocator(&app.arena)

  err: os.Error
  data: []u8
  spall._buffer_begin(&app.spall_ctx, &app.spall_buffer, "config file parsing")
  if os.exists(CONFIG_FILE_NAME) {
    data, err = os.read_entire_file(CONFIG_FILE_NAME, context.allocator)
    if err != nil {
      fmt.eprintfln("Could not read " + CONFIG_FILE_NAME + " file: %v", err)
      return false
    }

    app.defaultConfig, _ = ParseConfigFile(data)
  } else {
    app.defaultConfig.header.volume = 0.15
    app.defaultConfig.defaultSongDirectory = "songs"
    app.defaultConfig.currentSongPlaylist = "lists/NCS.list"
  }
  app.volume = clamp(app.defaultConfig.header.volume, 0.0, 0.4)
  spall._buffer_end(&app.spall_ctx, &app.spall_buffer) // config file parsing

  listFile := app.defaultConfig.currentSongPlaylist

  spall._buffer_begin(&app.spall_ctx, &app.spall_buffer, "playlist building")
  data, err = os.read_entire_file(listFile, context.allocator)
  if err != nil {
    fmt.eprintfln("Could not read %s file: %v", listFile, err)
    return false
  }
  ParseSongs(app, data)
  resize(&app.playlist.songs, len(app.playlist.songData))
  for i := 0; i < len(app.playlist.songData); i += 1 {
    app.playlist.songs[i] = &app.playlist.songData[i]
  }
  app.playlist.activeSongIdx = -1
  app.playlist.playingSongIdx = -1
  app.playlist.name = os.short_stem(listFile)

  if !slashpath.is_abs(listFile) {
    abspath, _ := os.get_absolute_path(listFile, context.temp_allocator)
    app.playlistFileAbsPath = strings.clone_to_cstring(abspath)
  }
  spall._buffer_end(&app.spall_ctx, &app.spall_buffer) // playlist building

  if !InitSDL3(app, input) {
    return false
  }
  if !AppInitPartial(rawApp, rawInput) {
    return false
  }

  if !mix.SetMixerGain(app.mixer, app.volume) {
    sdl.Log("Could not set volume: %s", sdl.GetError())
  }

  if !LoadAsepriteSpritesheetData(&app.iconSpritesheet, "resources/pixel/music-player-pixel-icons.json", app.arena_allocator) {
    fmt.eprintfln("Could not load aseprite spritesheet data")
    return false
  }

  {
    //primary := sdl.Color{10, 250, 180, 255}
    //secondary := sdl.Color{10, 220, 250, 255}
    //terniary := sdl.Color{80, 10, 250, 255}

    primary := sdl.Color{255, 0, 0, 255}
    secondary := sdl.Color{0, 0, 255, 255}
    terniary := sdl.Color{0, 255, 0, 255}
    if !MapSpritesheetColors(app.renderer, &app.iconSpritesheet, primary, secondary, terniary) {
      fmt.eprintfln("Could not map spritesheet colors")
      return false
    }
  }

  when ODIN_DEBUG {
    // have seed always be the same number for debug
    rand.reset(0)
  }

  return true
}

@export
AppInitPartial :: proc(rawApp: rawptr, rawInput: rawptr) -> bool
{
  // Here, startup anything that needs to be restarted each time a new dll is loaded
  app := cast(^AppData)rawApp
  //input := cast(^Input)rawInput

  if !InitClay(app) {
    sdl.Log("Could not init clay")
    return false
  }
  return true
}

@export
AppDeInitPartial :: proc(rawApp: rawptr, rawInput: rawptr)
{
  // Here, close anything that needs to be restarted each time a new dll is loaded
  //app := cast(^AppData)rawApp
  //input := cast(^Input)rawInput

  //Clay_Close()
}

@export
AppDeInit :: proc(rawApp: rawptr, rawInput: rawptr)
{
  app := cast(^AppData)rawApp
  input := cast(^Input)rawInput
  AppDeInitPartial(rawApp, rawInput)

  ttf.CloseFont(app.clay_renderData.fonts[0])
  ttf.CloseFont(app.clay_renderData.fonts[1])
  delete(app.clay_renderData.fonts)
  ttf.DestroyRendererTextEngine(app.clay_renderData.textEngine)
  ttf.Quit()

  DestroySDL_SpritesheetData(&app.iconSpritesheet)

  if app.musicAudio != nil {
    mix.DestroyAudio(app.musicAudio)
  }
  if app.musicTrack != nil {
    mix.DestroyTrack(app.musicTrack)
  }
  mix.DestroyMixer(app.mixer)
  mix.Quit()

  sdl.DestroyRenderer(app.renderer)
  sdl.DestroyWindow(app.window)
  sdl.Quit()

  {
    dF, err := os.open(CONFIG_FILE_NAME, os.O_TRUNC | os.O_CREATE)
    fmt.assertf(err == nil, "Could not open file: %s: %v", CONFIG_FILE_NAME, err)

    SerializeConfigFile(app, dF)

    os.close(dF)
  }

  // NOTE: Spall deInit
  spall.buffer_destroy(&app.spall_ctx, &app.spall_buffer)
  delete(app.spall_backing_buffer)
  spall.context_destroy(&app.spall_ctx)

  delete(app.playlist.songs)
  delete(app.playlist.songData)
  free(app)
  free(input)
  virtual.arena_destroy(&app.arena)
}

@export MemorySize :: proc() -> (int, int) { return size_of(AppData), size_of(Input) }

////////////////////////////////////////////
// Utilities

NextSong :: proc(app: ^AppData) {
  newIdx := (app.playlist.playingSongIdx + 1) % len(app.playlist.songs)
  if app.playlist.activeSongIdx == app.playlist.playingSongIdx {
    app.playlist.activeSongIdx = newIdx
  }
  app.playlist.playingSongIdx = newIdx
  ChangeLoadedMusicStream(app, newIdx)

  if app.musicLooping {
    HandleMusicLooping(app)
  }
}

PrevSong :: proc(app: ^AppData) {
  newIdx := (app.playlist.playingSongIdx - 1) %% len(app.playlist.songs)
  if app.playlist.activeSongIdx == app.playlist.playingSongIdx {
    app.playlist.activeSongIdx = newIdx
  }
  app.playlist.playingSongIdx = newIdx
  ChangeLoadedMusicStream(app, newIdx)

  if app.musicLooping {
    HandleMusicLooping(app)
  }
}

ForwardTime :: #force_inline proc(app: ^AppData, seconds: f32)
{
  // TODO: Use TrackMSToFrames or AudioMSToFrames?
  app.musicTimePlayed = min(app.musicTimePlayed + mix.TrackMSToFrames(app.musicTrack, i64(seconds*1000.0)), app.musicTimeLength)
  if app.musicTimePlayed == app.musicTimeLength {
    if app.musicLooping {
      if !mix.SetTrackPlaybackPosition(app.musicTrack, 0) {
        sdl.Log("Could not set track playback position: %s", sdl.GetError())
      }
    } else {
      NextSong(app)
    }
  } else {
    if !mix.SetTrackPlaybackPosition(app.musicTrack, app.musicTimePlayed) {
      sdl.Log("Could not set track playback position: %s", sdl.GetError())
    }
  }
}

BackTime :: #force_inline proc(app: ^AppData, seconds: f32)
{
  app.musicTimePlayed = max(app.musicTimePlayed - mix.TrackMSToFrames(app.musicTrack, i64(seconds*1000.0)), 1)
  if !mix.SetTrackPlaybackPosition(app.musicTrack, app.musicTimePlayed) {
    sdl.Log("Could not set track playback position: %s", sdl.GetError())
  }
}

GetInput :: proc(app: ^AppData, input: ^Input) -> (shouldQuit: bool)
{
  // reset attributes that accumulate in a single frame
  input.mouseWheel = 0
  input.ignoreMissedFPS = false
  mem.zero(&input.keyPressed[sdl.Scancode(0)], size_of(input.keyPressed))

  event: sdl.Event = ---
  for sdl.PollEvent(&event) {
    #partial switch event.type {
      case .QUIT: {
        shouldQuit = true
      } break;

      case .KEY_DOWN: {
        //if !input.keyDown[event.key.scancode] do input.keyPressed[event.key.scancode] = true
        input.keyPressed[event.key.scancode] = !input.keyDown[event.key.scancode]
        input.keyDown[event.key.scancode] = true
      } break;
      case .KEY_UP: {
        input.keyDown[event.key.scancode] = false
      } break;

      case .MOUSE_WHEEL: {
        input.mouseWheel += { event.wheel.x, event.wheel.y}
      } break;
    }
  }

  keyMod := sdl.GetModState()
  input.ctrlDown = .LCTRL in keyMod || .RCTRL in keyMod
  input.shiftDown = .LSHIFT in keyMod || .RSHIFT in keyMod
  input.altDown = .LALT in keyMod || .RALT in keyMod

  mouseButtonFlags := sdl.GetMouseState(&input.mousePos.x, &input.mousePos.y)
  mouseLeftDown := .LEFT in mouseButtonFlags
  input.mouseLeftReleased = input.mouseLeftDown && !mouseLeftDown
  input.mouseLeftDown = mouseLeftDown

  return
}

OpenFolderCallback :: proc "c"(rawapp: rawptr, filelist: [^]cstring, filter: i32)
{
  // NOTE: filter is only used to open files
  app := cast(^AppData)rawapp

  if filelist == nil {
    sdl.Log("An error occurred: %s", sdl.GetError())
    return
  } else if filelist[0] == nil {
    sdl.Log("Did not select any file, the dialog was probably cancelled")
    return
  }

  context = app.eventFilterData.Context

  // NOTE: Extensions get checked in AddsSongsToList
  for i := 0; filelist[i] != nil; i += 1 {
    AddSongsToList(app, filelist[i])
  }
}

/* Pause or resume the music track depending on app.musicPause */
PauseOrResume :: #force_inline proc(app: ^AppData)
{
  if app.musicPause {
    if !mix.PauseTrack(app.musicTrack) {
      sdl.Log("Could not stop track: %s", sdl.GetError())
    }
  } else if !mix.ResumeTrack(app.musicTrack) {
    sdl.Log("Could not resume track: %s", sdl.GetError())
  }
}

RandomizeSongs :: #force_inline proc(app: ^AppData)
{
  app.musicPause = false
  rand.shuffle(app.playlist.songs[:])
  if app.playlist.activeSongIdx != -1 {
    app.playlist.activeSongIdx = 0
  }
  if app.playlist.playingSongIdx != -1 {
    app.playlist.playingSongIdx = 0
    ChangeLoadedMusicStream(app, 0)
  }
}

HandleMusicLooping :: proc(app: ^AppData)
{
  newloops: c.int = 0
  if app.musicLooping {
    newloops = -1
  }
  if !mix.SetTrackLoops(app.musicTrack, newloops) {
    sdl.Log("Could not set music track loops: %s", sdl.GetError())
  }
}

Update :: proc(app: ^AppData, input: ^Input)
{
  spall.SCOPED_EVENT(&app.spall_ctx, &app.spall_buffer, #procedure)

  if input.ctrlDown && input.keyPressed[.O] {
    sdl.ShowOpenFolderDialog(OpenFolderCallback, cast(rawptr)app, app.window, ".", true)
  }

  // If the song finished, go to the next
  // TODO: app.musicLoaded could be unnecessary here
  if !app.musicPause && app.musicLoaded && !mix.TrackPlaying(app.musicTrack) {
    NextSong(app)
  }

  // volume
  if input.keyDown[.UP] || input.keyDown[.KP_8] {
    app.volume = min(app.volume + 0.005, 1.0)
    if !mix.SetMixerGain(app.mixer, app.volume) {
      sdl.Log("Could not set volume: %s", sdl.GetError())
    }
  } else if input.keyDown[.DOWN] || input.keyDown[.KP_2] {
    app.volume = max(app.volume - 0.005, 0.0)
    if !mix.SetMixerGain(app.mixer, app.volume) {
      sdl.Log("Could not set volume: %s", sdl.GetError())
    }
  }

  // song control
  app.musicTimePlayed = mix.GetTrackPlaybackPosition(app.musicTrack)
  app.musicTimePlayedMs = mix.TrackFramesToMS(app.musicTrack, app.musicTimePlayed)
  if input.keyPressed[.RIGHT] || input.keyPressed[.KP_6] {
    ForwardTime(app, 5.0)
  } else if input.keyPressed[.LEFT] || input.keyPressed[.KP_4] {
    BackTime(app, 5.0)
  }

  if input.keyPressed[.L] { ForwardTime(app, 10.0) }
  else if input.keyPressed[.J] { BackTime(app, 10.0) }

  if input.keyPressed[.END] || input.keyPressed[.KP_1] {
    NextSong(app)
  } else if input.keyPressed[.HOME] || input.keyPressed[.KP_7] {
    if app.musicTimePlayedMs < 12000 {
      PrevSong(app)
    } else {
      if !mix.SetTrackPlaybackPosition(app.musicTrack, 0) {
        sdl.Log("Could not rewind to start of the track: %s", sdl.GetError())
      }
      app.musicTimePlayed = 0
    }
  }

  if input.keyPressed[.A] { // temporary while I find a better key for this
    app.musicLooping = !app.musicLooping
    HandleMusicLooping(app)
  }

  // NOTE: Randomize song order
  if input.keyPressed[.R] {
    RandomizeSongs(app)
  }

PAUSE_FADE_OUT_FRAMES :: 80

  if app.musicLoaded && (input.keyPressed[.K] || input.keyPressed[.SPACE]) {
    app.musicPause = !app.musicPause
    PauseOrResume(app)
  }

  List_FreeAll(&app.imageData)
  UI_Prepare(app, input)
}

Render :: proc(app: ^AppData, input: ^Input)
{
  spall.SCOPED_EVENT(&app.spall_ctx, &app.spall_buffer, #procedure)

  // Generate the auto layout for rendering
  UIRenderCommands := UI_Calculate(app, input)
  if app.playlist.activeSongChanged {
    song: ^SongData = app.playlist.songs[app.playlist.activeSongIdx]
    // TODO: should I keep this somewhere instead of destroying it immediately?
    source := strings.clone_to_cstring(song.source, context.temp_allocator)
    audio := mix.LoadAudio_IO(app.mixer, sdl.IOFromFile(source, "rb"),
                              predecode = false, closeio = true)
    GetAudioMetadataForSong(song, audio, app.arena_allocator)
    mix.DestroyAudio(audio)
  }
  if app.playlist.playingSongChanged {
    ChangeLoadedMusicStream(app, app.playlist.playingSongIdx)
  }

  sdl.SetRenderDrawColor(app.renderer, 0, 0, 0, 255)
  sdl.RenderClear(app.renderer)

  SDL_RenderClayCommands(&app.clay_renderData, &UIRenderCommands)
  //sdl.RenderTexture(app.renderer, app.iconSpritesheet.tex, nil, nil)

  sdl.RenderPresent(app.renderer)
}

@export
MainLoop :: proc(rawApp: rawptr, rawInput: rawptr) -> bool
{
  startTicks := sdl.GetTicksNS()

  app := cast(^AppData)rawApp
  input := cast(^Input)rawInput
  spall._buffer_begin(&app.spall_ctx, &app.spall_buffer, "update & render")

  free_all(context.temp_allocator)

  shouldQuit := GetInput(app, input)
  // TODO: Low power stuff, don't render if minimized, decrease fps...?
  Update(app, input)
  Render(app, input)

  spall._buffer_end(&app.spall_ctx, &app.spall_buffer)

  difTicks := f32(sdl.GetTicksNS() - startTicks)
  if difTicks < TARGET_NS {
    sdl.DelayNS(u64(TARGET_NS - difTicks))
  } else if !input.ignoreMissedFPS {
    when ODIN_DEBUG {
      // NOTE: Show ms, not ns
      sdl.Log("Missed target fps: %fms", difTicks/1000000.0)
    }
  }
  input.deltaTime = f32(sdl.GetTicksNS() - startTicks)/1000000.0

  return shouldQuit
}