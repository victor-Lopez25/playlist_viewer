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
import "core:path/slashpath"

import spall "spall-wrapper"

import sdl "vendor:sdl3"
import "vendor:sdl3/ttf"
import mix "vendor:sdl3/mixer"

DATAFILE_NAME :: "prog.dat"

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

ParseSingleSong :: proc(text: ^string) -> (SongData, bool)
{
  TrimQuotesAndCommaIfPresent :: #force_inline proc(text: string) -> string
  {
    // accept no comma
    if text[len(text)-1] == ',' {
      return text[1:len(text) - 2]
    }
    else {
      return text[1:len(text) - 1]
    }
  }

  song: SongData
  nok := false
  foundEnd := false
  for line in strings.split_lines_iterator(text)
  {
    if strings.has_prefix(line, "}") {
      foundEnd = true
      break
    }

    trimmedLine := strings.trim_space(line)
    if strings.has_prefix(trimmedLine, "group:") {
      trimmedLine = strings.trim_space(trimmedLine[len("group:"):])
      trimmedLine = TrimQuotesAndCommaIfPresent(trimmedLine)
      song.group = trimmedLine
    }
    else if strings.has_prefix(trimmedLine, "song:") {
      trimmedLine = strings.trim_space(trimmedLine[len("song:"):])
      trimmedLine = TrimQuotesAndCommaIfPresent(trimmedLine)
      song.name = trimmedLine
    }
    else if strings.has_prefix(trimmedLine, "source:") {
      trimmedLine = strings.trim_space(trimmedLine[len("source:"):])
      trimmedLine = TrimQuotesAndCommaIfPresent(trimmedLine)
      song.source = trimmedLine
    }
    else if strings.has_prefix(trimmedLine, "sourceType:") {
      trimmedLine = strings.trim_space(trimmedLine[len("sourceType:"):])
      if trimmedLine[len(trimmedLine)-1] == ',' {
        trimmedLine = trimmedLine[:len(trimmedLine)-1]
      }
      if trimmedLine == "File" { song.sourceType = .File }
      else if trimmedLine == "Link" { song.sourceType = .Link }
      else {
        // TODO: better error msg
        fmt.println("Unknown source type")
        nok = true
      }
    }
  }
  // TODO: error msg (not found end)
  nok = nok || !foundEnd
  return song, !nok
}

ParseSongs :: proc(app: ^AppData, data: []u8) -> [dynamic]SongData
{
  spall.SCOPED_EVENT(&app.spall_ctx, &app.spall_buffer, #procedure)
  songs: [dynamic]SongData

  source := string(data)

  startList := false
  for line in strings.split_lines_iterator(&source)
  {
    if strings.has_prefix(line, "main list:") {
      assert(!startList)
      startList = true
      continue
    }
    if line == "" do startList = false
    if !startList do continue

    if !strings.has_prefix(line, "{") {
      // TODO: better error msg
      fmt.println("parse error")
      break
    }
    song, ok := ParseSingleSong(&source)
    if !ok {
      // TODO: better error msg
      fmt.println("parse error")
      break
    }
    //fmt.printfln("[\n  group: \"%s\"\n  song: \"%s\"\n  source: \"%s\"\n  sourceType: %v\n]", song.group, song.name, song.source, song.sourceType)
    append(&songs, song)
  }

  return songs
}

ParseSongs_v1 :: proc(data: []u8) -> [dynamic]SongData
{
  songs: [dynamic]SongData

  source := string(data)

  startList := false
  for line in strings.split_lines_iterator(&source)
  {
    if strings.has_prefix(line, "main list:") {
      assert(!startList)
      startList = true
      continue
    }
    if line == "" do startList = false
    if !startList do continue

    songName, sep, album, group: string
    songName, sep, album = strings.partition(line, " - ")
    album, sep, group = strings.partition(album, " - ")
    if group == "" {
      group = album
      album = ""
    }

    //fmt.printfln("%s - %s - %s", group, album, songName)

    song : SongData = {
      name = songName,
      group = group,
      album = album,
    }
    fmt.printfln("%c\n  group: \"%s\"\n  song: \"%s\"\n},", '{', song.group, song.name)
    append(&songs, song)
  }

  // PrintSongs(songs[:])
  // CountSongs(songs[:])

  return songs
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
        if prevAudio != nil {
          mix.DestroyAudio(prevAudio)
        }
      } else {
        sdl.Log("Could not play music: %s", sdl.GetError())
      }
    }
  }
}

ChangeLoadedMusicStream :: proc(app: ^AppData, newIdx: int)
{
  spall.SCOPED_EVENT(&app.spall_ctx, &app.spall_buffer, #procedure)

  playlist := &app.playlist
  if playlist.songs[playlist.activeSongIdx].source != "" {
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
  }
}

AddSongsToList :: proc(app: ^AppData, listFile: cstring) -> bool
{
  if listFile == nil || listFile == "" do return false

  pathinfo: sdl.PathInfo
  ok := sdl.GetPathInfo(listFile, &pathinfo)
  if !ok do return false

  ReadDirectoryData :: struct { ctx: runtime.Context, songData: ^[dynamic]SongData }
  ReadDirectoryFile :: proc "c"(rawdata: rawptr, dirname, fname: cstring) -> sdl.EnumerationResult
  {
    data := cast(^ReadDirectoryData)rawdata
    context = data.ctx

    name := string(fname)
    fullpath := slashpath.join({string(dirname), name})
    ext := slashpath.ext(name)
    info: sdl.PathInfo
    ok := sdl.GetPathInfo(strings.clone_to_cstring(fullpath, context.temp_allocator), &info)
    if !ok do return .CONTINUE

    if len(ext) > 1 { ext = ext[1:] }
    if info.type != .DIRECTORY && (ext == "mp3" || ext == "ogg" || ext == "qoa" || ext == "xm" || ext == "mod" || ext == "wav") {
      song := SongData{
        group = "",
        name = strings.clone(os.short_stem(name)),
        album = "",
        source = fullpath,
        sourceType = .File,
      }
      append(data.songData, song)
    }

    return .CONTINUE
  }

  if pathinfo.type == .DIRECTORY {
    data := ReadDirectoryData{ ctx = context, songData = &app.playlist.songData }
    ok = sdl.EnumerateDirectory(listFile, ReadDirectoryFile, &data)
  }
  else {
    size: uint
    rawdata := sdl.LoadFile(listFile, &size)
    data := slice.from_ptr(cast(^u8)rawdata, int(size))
    if ok {
      parsedSongs := ParseSongs(app, data)
      for s in parsedSongs do append(&app.playlist.songData, s)
      app.playlistFileAbsPath = listFile
    }
  }

  if ok {
    resize(&app.playlist.songs, len(app.playlist.songData))
    for i := 0; i < len(app.playlist.songData); i += 1 { app.playlist.songs[i] = &app.playlist.songData[i] }
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

  sdl.SetLogPriorities(.VERBOSE)

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

  font := ttf.OpenFont("resources/Inconsolata-Regular.ttf", 16);
  if font == nil {
    sdl.Log("Could not load font: %s", sdl.GetError())
    return false
  }
  app.clay_renderData.fonts[Font_Inconsolata] = font
  font = ttf.OpenFont("resources/liberation-mono.ttf", 16);
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

@export
AppInit :: proc(rawApp: rawptr, rawInput: rawptr) -> bool
{
  app := cast(^AppData)rawApp
  input := cast(^Input)rawInput

  ok: bool
  app.spall_ctx, ok = spall.context_create("trace.spall")
  if !ok {
    sdl.Log("Could not create Spall context")
    return false
  }
  app.spall_backing_buffer = make([]u8, spall.BUFFER_DEFAULT_SIZE)
  if app.spall_backing_buffer == nil {
    sdl.Log("Could not allocate spall backing buffer")
    return false
  }
  app.spall_buffer = spall.buffer_create(app.spall_backing_buffer, u32(sync.current_thread_id()))
  spall.SCOPED_EVENT(&app.spall_ctx, &app.spall_buffer, #procedure)

  clistFile: cstring = "songs"
  //clistFile: cstring = ""

  err: os.Error
  data: []u8
  spall._buffer_begin(&app.spall_ctx, &app.spall_buffer, "data file parsing")
  if os.exists(DATAFILE_NAME) {
    data, err = os.read_entire_file(DATAFILE_NAME, context.temp_allocator)
    if err != nil {
      fmt.eprintfln("Could not read " + DATAFILE_NAME + " file: %v", err)
      return false
    }

    volume := (cast(^f32)&data[0])^
    app.volume = clamp(volume, 0.0, 0.4)
  }
  spall._buffer_end(&app.spall_ctx, &app.spall_buffer) // data file parsing

  listFile := string(clistFile)

  spall._buffer_begin(&app.spall_ctx, &app.spall_buffer, "playlist building")
  AddSongsToList(app, clistFile)
  app.playlist.activeSongIdx = -1
  app.playlist.name = os.short_stem(listFile)

  if !slashpath.is_abs(listFile) {
    abspath, _ := os.get_absolute_path(listFile, context.temp_allocator)
    app.playlistFileAbsPath = strings.clone_to_cstring(abspath)
  }
  spall._buffer_end(&app.spall_ctx, &app.spall_buffer) // playlist building

  // volume 1 is way too high
  if app.volume == 0 { app.volume = 0.18 }

  if !InitSDL3(app, input) {
    return false
  }
  if !AppInitPartial(rawApp, rawInput) {
    return false
  }

  if !mix.SetMixerGain(app.mixer, app.volume) {
    sdl.Log("Could not set volume: %s", sdl.GetError())
  }

  rand.reset(0) // NOTE: Debugging purposes

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
    //playlistAbsPathData := transmute([]u8)app.playlistFileAbsPath
    bytesWritten: int = ---
    dF, err := os.open(DATAFILE_NAME, os.O_TRUNC | os.O_CREATE)
    fmt.assertf(err == nil, "Could not open file: %s: %v", DATAFILE_NAME, err)
    bytesWritten, err = os.write(dF, slice.bytes_from_ptr(&app.volume, size_of(app.volume)))
    if err != nil {
      fmt.eprintfln("Could not write data into datafile: %v", err)
    }
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
}

@export MemorySize :: proc() -> (int, int) { return size_of(AppData), size_of(Input) }

////////////////////////////////////////////
// Utilities

NextSong :: proc(app: ^AppData) {
  newIdx := (app.playlist.activeSongIdx + 1) % len(app.playlist.songs)
  app.playlist.activeSongIdx = newIdx
  ChangeLoadedMusicStream(app, newIdx)
}

PrevSong :: proc(app: ^AppData) {
  newIdx := (app.playlist.activeSongIdx - 1) %% len(app.playlist.songs)
  app.playlist.activeSongIdx = newIdx
  ChangeLoadedMusicStream(app, newIdx)
}

ForwardTime :: #force_inline proc(app: ^AppData, seconds: f32)
{
  // TODO: Use TrackMSToFrames or AudioMSToFrames?
  app.musicTimePlayed = min(app.musicTimePlayed + mix.TrackMSToFrames(app.musicTrack, i64(seconds*1000.0)), app.musicTimeLength)
  if app.musicTimePlayed == app.musicTimeLength {
    NextSong(app)
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

  for i := 0; filelist[i] != nil; i += 1 {
    AddSongsToList(app, filelist[i])
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
  if input.keyDown[.UP] {
    app.volume = min(app.volume + 0.005, 1.0)
    if !mix.SetMixerGain(app.mixer, app.volume) {
      sdl.Log("Could not set volume: %s", sdl.GetError())
    }
  }
  if input.keyDown[.DOWN] {
    app.volume = max(app.volume - 0.005, 0.0)
    if !mix.SetMixerGain(app.mixer, app.volume) {
      sdl.Log("Could not set volume: %s", sdl.GetError())
    }
  }

  // song control
  app.musicTimePlayed = mix.GetTrackPlaybackPosition(app.musicTrack)
  if input.keyPressed[.RIGHT] { ForwardTime(app, 5.0) }
  else if input.keyPressed[.LEFT] { BackTime(app, 5.0) }
  if input.keyPressed[.L] { ForwardTime(app, 10.0) }
  else if input.keyPressed[.J] { BackTime(app, 10.0) }

  if input.keyPressed[.END] || input.keyPressed[.KP_1] {
    NextSong(app)
  } else if input.keyPressed[.HOME] || input.keyPressed[.KP_7] {
    if app.musicTimePlayed < 12.0 {
      PrevSong(app)
    } else {
      if !mix.SetTrackPlaybackPosition(app.musicTrack, 0) {
        sdl.Log("Could not rewind to start of the track: %s", sdl.GetError())
      }
      app.musicTimePlayed = 0
    }
  }

  if input.keyPressed[.A] { // temporary while there is no UI for this
    app.musicLooping = !app.musicLooping
    newloops: c.int
    if app.musicLooping {
      newloops = -1
    }
    if !mix.SetTrackLoops(app.musicTrack, newloops) {
      sdl.Log("Could not set music track loops: %s", sdl.GetError())
    }
  }

  // NOTE: Randomize song order
  if input.keyPressed[.R] {
    app.playlist.activeSongIdx = 0
    app.musicPause = false
    rand.shuffle(app.playlist.songs[:])
    ChangeLoadedMusicStream(app, 0)
  }

PAUSE_FADE_OUT_FRAMES :: 80

  if app.musicLoaded && (input.keyPressed[.K] || input.keyPressed[.SPACE]) {
    app.musicPause = !app.musicPause
    if app.musicPause {
      if !mix.StopTrack(app.musicTrack, PAUSE_FADE_OUT_FRAMES) {
        sdl.Log("Could not stop track: %s", sdl.GetError())
      }
    } else if !mix.ResumeTrack(app.musicTrack) {
      sdl.Log("Could not resume track: %s", sdl.GetError())
    }
  }

  //timePlayed := ray.GetMusicTimePlayed(music)/ray.GetMusicTimeLength(music)
  //fmt.println(timePlayed)

  UI_Prepare(app, input)
}

Render :: proc(app: ^AppData, input: ^Input)
{
  spall.SCOPED_EVENT(&app.spall_ctx, &app.spall_buffer, #procedure)

  // Generate the auto layout for rendering
  UIRenderCommands := UI_Calculate(app, input)

  sdl.SetRenderDrawColor(app.renderer, 0, 0, 0, 255)
  sdl.RenderClear(app.renderer)

  SDL_RenderClayCommands(&app.clay_renderData, &UIRenderCommands)

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
  if false { // ray.IsWindowMinimized() {
    // TODO: Also decrease fps?
    //ray.UpdateMusicStream(app.music)
    if !app.musicPause && app.musicLoaded && false { // !ray.IsMusicStreamPlaying(app.music) {
      newIdx := (app.playlist.activeSongIdx + 1) % len(app.playlist.songs)
      app.playlist.activeSongIdx = newIdx
      ChangeLoadedMusicStream(app, newIdx)
    }
    //ray.BeginDrawing(); ray.EndDrawing() // end frame
  }
  else {
    Update(app, input)
    Render(app, input)
  }

  spall._buffer_end(&app.spall_ctx, &app.spall_buffer)

  if app.playlist.activeSongIdx != -1 {
    //fmt.println("song selected")
  }

  difTicks := f32(sdl.GetTicksNS() - startTicks)
  if difTicks < TARGET_NS {
    sdl.DelayNS(u64(TARGET_NS - difTicks))
  }
  else if !input.ignoreMissedFPS {
    sdl.Log("Missed target fps: %fms", difTicks/1000000.0) // NOTE: Show ms, not ns
  }
  input.deltaTime = f32(sdl.GetTicksNS() - startTicks)/1000000.0

  return shouldQuit
}