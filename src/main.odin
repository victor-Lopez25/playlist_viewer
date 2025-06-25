package main

import "base:runtime"
import "core:os"
import "core:fmt"
import "core:mem"
import "core:sync"
import "core:slice"
import "core:strings"
import "core:math/rand"
import "core:path/filepath"

import "core:prof/spall"
import sdl "vendor:sdl3"
import "vendor:sdl3/ttf"

import mix "sdl3_mixer"

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
  app.music = mix.LoadMUS_IO(sdl.IOFromFile(file, "rb"), true)

  if mix.PlayMusic(app.music, 0) { // 0 loops
    app.musicLoaded = true
  } else {
    // NOTE: If the music could not be played, the music structure will be freed next frame
    fmt.println("Could not play music:", mix.GetError())
  }
}

ChangeLoadedMusicStream :: proc(app: ^AppData, newIdx: int)
{
  spall.SCOPED_EVENT(&app.spall_ctx, &app.spall_buffer, #procedure)

  playlist := &app.playlist
  if playlist.songs[playlist.activeSongIdx].source != "" {
    if app.musicLoaded {
      mix.FreeMusic(app.music)
      app.musicLoaded = false
    }

    activeSong := playlist.songs[newIdx]
    switch activeSong.sourceType {
      case .None: assert(false, "unreachable")
      case .Link: {
        assert(false, "unimplemented")
      }
      case .File: {
        b: strings.Builder = strings.builder_make_len_cap(0, 40, context.temp_allocator)
        filepath := fmt.sbprintf(&b, "../songs/%s", activeSong.source)
        if os.exists(filepath) {
          file, _ := strings.to_cstring(&b)
          LoadMusicFromFile(app, file)
        }
        else if os.exists(activeSong.source) {
            filename := strings.clone_to_cstring(activeSong.source, context.temp_allocator)
            LoadMusicFromFile(app, filename)
        } else {
          fmt.println("Could not find song")
        }
      }
    }

    // NOTE: Gather 'static' data from app.music here
    app.musicTimeLength = f32(mix.MusicDuration(app.music))
    app.musicTimePlayed = 0.0
  }
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

InitSDL3 :: proc(app: ^AppData, input: ^Input)
{
  spall.SCOPED_EVENT(&app.spall_ctx, &app.spall_buffer, #procedure)
  ok := sdl.Init({.AUDIO, .VIDEO}) // NOTE: Any subsystem that isn't video can be initialized in a different thread
  assert(ok, "Could not init sdl")

  app.windowWidth = 1000
  app.windowHeight = 800
  app.window = sdl.CreateWindow("playlist viewer", app.windowWidth, app.windowHeight, {.RESIZABLE})
  assert(app.window != nil, "Could not create sdl window")
  app.renderer = sdl.CreateRenderer(app.window, nil)
  assert(app.renderer != nil, "Could not create sdl renderer")

  ok = ttf.Init()
  assert(ok, "Could not init sdl_ttf")

  app.clay_renderData.renderer = app.renderer;
  app.clay_renderData.textEngine = ttf.CreateRendererTextEngine(app.clay_renderData.renderer);
  assert(app.clay_renderData.textEngine != nil, "Could not create text engine from renderer")

  app.clay_renderData.fonts = make([]^ttf.Font, 2)
  assert(app.clay_renderData.fonts != nil, "Could not allocate memory for the font array")

  font := ttf.OpenFont("resources/Inconsolata-Regular.ttf", 16);
  assert(font != nil, "Could not load font")
  app.clay_renderData.fonts[Font_Inconsolata] = font
  font = ttf.OpenFont("resources/liberation-mono.ttf", 16);
  assert(font != nil, "Could not load font")
  app.clay_renderData.fonts[Font_LiberationMono] = font

  app.eventFilterData.app = app
  app.eventFilterData.input = input
  app.eventFilterData.Context = context
  ok = sdl.AddEventWatch(InputEventFilter, &app.eventFilterData)
  assert(ok, "Could not add sdl event watch: InputEventFilter")

  // Audio
  sdl.Log("Audio driver: %s", sdl.GetCurrentAudioDriver())

  tryInit := mix.InitFlags{.MP3}
  initFlags := mix.Init(tryInit)
  assert(tryInit == initFlags, "Could not init sdl3_mixer")

  ok = mix.OpenAudio(0, nil)
  assert(ok, "Could not open audio device")
}

@export
InitAll :: proc(rawApp: rawptr, rawInput: rawptr)
{
  app := cast(^AppData)rawApp
  input := cast(^Input)rawInput

  app.spall_ctx = spall.context_create("trace.spall")
  app.spall_backing_buffer = make([]u8, spall.BUFFER_DEFAULT_SIZE)
  app.spall_buffer = spall.buffer_create(app.spall_backing_buffer, u32(sync.current_thread_id()))
  spall.SCOPED_EVENT(&app.spall_ctx, &app.spall_buffer, #procedure)

  // TODO: Do something smarter for this?
  listFile := "songs"

  err: os.Error
  ok: bool

  data: []u8
  spall._buffer_begin(&app.spall_ctx, &app.spall_buffer, "data file parsing")
  if os.exists(DATAFILE_NAME) {
    data, err = os.read_entire_file_or_err(DATAFILE_NAME)
    fmt.assertf(err == nil, "Could not read " + DATAFILE_NAME + " file: %v", err)

    volume := (cast(^f32)&data[0])^
    app.volume = clamp(volume, 0.0, 0.4)
  }
  spall._buffer_end(&app.spall_ctx, &app.spall_buffer) // data file parsing

  spall._buffer_begin(&app.spall_ctx, &app.spall_buffer, "playlist building")
  songData: [dynamic]SongData
  if listFile != "" {
    if os.is_dir(listFile) {
      fileInfos: []os.File_Info
      songDir, ferr := os.open(listFile)
      assert(ferr == nil, "Could not open directory")
      // TODO: Read more than the max count of files when exceeded?
      fileInfos, err = os.read_dir(songDir, 128) // 128 files max
      assert(err == nil)
      for fi in fileInfos {
        ext := filepath.ext(fi.name)
        if len(ext) > 1 { ext = ext[1:] }
        if !fi.is_dir && (ext == "mp3" || ext == "ogg" || ext == "qoa" || ext == "xm" || ext == "mod" || ext == "wav") {
          song := SongData{
            group = "",
            name = filepath.short_stem(fi.name),
            album = "",
            source = fi.fullpath,
            sourceType = .File,
          }
          append(&songData, song)
        }
      }
    }
    else {
      data, ok = os.read_entire_file(listFile)
      assert(ok)
      songData = ParseSongs(app, data)
    }
  }

  songs := make([dynamic]^SongData, len(songData), len(songData))
  for i := 0; i < len(songData); i += 1 { songs[i] = &songData[i] }
  app.playlist = Playlist{
    songData = songData,
    songs = songs,
    name = filepath.short_stem(listFile),
    activeSongIdx = -1,
  }
  app.playlistFileAbsPath = listFile
  if !filepath.is_abs(listFile) { app.playlistFileAbsPath, _ = filepath.abs(listFile) }
  spall._buffer_end(&app.spall_ctx, &app.spall_buffer) // playlist building

  // volume 1 is way too high
  if app.volume == 0 { app.volume = 0.18 }

  InitSDL3(app, input)
  InitPartial(rawApp, rawInput)

  _ = mix.VolumeMusic(i32(app.volume*128.0))

  return
}

@export
InitPartial :: proc(rawApp: rawptr, rawInput: rawptr)
{
  // Here, startup anything that needs to be restarted each time a new dll is loaded
  app := cast(^AppData)rawApp
  //input := cast(^Input)rawInput

  InitClay(app)
}

@export
DeInitPartial :: proc(rawApp: rawptr, rawInput: rawptr)
{
  // Here, close anything that needs to be restarted each time a new dll is loaded
  //app := cast(^AppData)rawApp
  //input := cast(^Input)rawInput

  //Clay_Close()
}

@export
DeInitAll :: proc(rawApp: rawptr, rawInput: rawptr)
{
  app := cast(^AppData)rawApp
  input := cast(^Input)rawInput
  DeInitPartial(rawApp, rawInput)

  ttf.CloseFont(app.clay_renderData.fonts[0])
  ttf.CloseFont(app.clay_renderData.fonts[1])
  delete(app.clay_renderData.fonts)
  ttf.DestroyRendererTextEngine(app.clay_renderData.textEngine)
  ttf.Quit()

  if app.music != nil {
    mix.FreeMusic(app.music)
  }
  mix.CloseAudio()
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
  if app.musicLooping {
    mix.PlayMusic(app.music, 0)
  } else {
    newIdx := (app.playlist.activeSongIdx + 1) % len(app.playlist.songs)
    app.playlist.activeSongIdx = newIdx
    ChangeLoadedMusicStream(app, newIdx)
  }
}

PrevSong :: proc(app: ^AppData) {
  newIdx := (app.playlist.activeSongIdx - 1) %% len(app.playlist.songs)
  app.playlist.activeSongIdx = newIdx
  ChangeLoadedMusicStream(app, newIdx)
}

ForwardTime :: #force_inline proc(app: ^AppData, seconds: f32)
{
  app.musicTimePlayed = min(app.musicTimePlayed + seconds, app.musicTimeLength)
  if app.musicTimePlayed == app.musicTimeLength {
    NextSong(app)
  } else {
    mix.SetMusicPosition(f64(app.musicTimePlayed))
  }
}

BackTime :: #force_inline proc(app: ^AppData, seconds: f32)
{
  app.musicTimePlayed = max(app.musicTimePlayed - seconds, 0.06)
  mix.SetMusicPosition(f64(app.musicTimePlayed))
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

Update :: proc(app: ^AppData, input: ^Input)
{
  spall.SCOPED_EVENT(&app.spall_ctx, &app.spall_buffer, #procedure)

  //ray.UpdateMusicStream(app.music)

  // If the song finished, go to the next
  // TODO: app.musicLoaded could be unnecessary here
  if !app.musicPause && app.musicLoaded && !mix.PlayingMusic() {
    NextSong(app)
  }

  // volume
  if input.keyDown[.UP] {
    app.volume = min(app.volume + 0.005, 1.0)
    mix.VolumeMusic(i32(app.volume*128.0))
  }
  if input.keyDown[.DOWN] {
    app.volume = max(app.volume - 0.005, 0.0)
    mix.VolumeMusic(i32(app.volume*128.0))
  }

  // song control
  app.musicTimePlayed = f32(mix.GetMusicPosition(app.music))
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
      mix.RewindMusic()
      app.musicTimePlayed = 0.0
    }
  }

  if input.keyPressed[.A] { // temporary while there is no UI for this
    app.musicLooping = !app.musicLooping
  }

  // NOTE: Randomize song order
  if input.keyPressed[.R] {
    app.playlist.activeSongIdx = 0
    app.musicPause = false
    rand.shuffle(app.playlist.songs[:])
    ChangeLoadedMusicStream(app, 0)
  }

  if app.musicLoaded && (input.keyPressed[.K] || input.keyPressed[.SPACE]) {
    app.musicPause = !app.musicPause
    if app.musicPause { mix.PauseMusic() }
    else { mix.ResumeMusic() }
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