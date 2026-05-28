package main

import "core:fmt"
import spall "spall-wrapper"

import clay "clay-odin"
import sdl "vendor:sdl3"
import mix "vendor:sdl3/mixer"

Font_Inconsolata :: 0
Font_LiberationMono :: 1

ELEMENT_ID_NIL :: clay.ElementId{ 0, 0, 0, clay.String{true, 0, nil} }

InitClay :: proc(app: ^AppData) -> bool
{
  error_handler :: proc "c" (errorData: clay.ErrorData) {
    // see clay.ErrorData for more data
    sdl.LogError(1, "%s", errorData.errorText.chars)
    //switch errorData.errorType {

    //}
  }
  spall.SCOPED_EVENT(&app.spall_ctx, &app.spall_buffer, #procedure)
  min_memory_size := uint(clay.MinMemorySize())
  memory := make([^]u8, min_memory_size)
  if memory == nil {
    sdl.Log("Could not allocate memory for clay (ui)")
    return false
  }
  arena: clay.Arena = clay.CreateArenaWithCapacityAndMemory(min_memory_size, memory)
  clay.Initialize(arena, { width = f32(app.windowWidth), height = f32(app.windowHeight) }, { handler = error_handler })
  clay.SetMeasureTextFunction(SDL_MeasureText, &app.clay_renderData.fonts[0])

  return true
}

UI_Prepare :: proc(app: ^AppData, input: ^Input)
{
  spall.SCOPED_EVENT(&app.spall_ctx, &app.spall_buffer, #procedure)
  @static scrollbarData: struct {
    clickOrigin, positionOrigin: clay.Vector2,
    mouseDown: bool,
  }

  when ODIN_DEBUG {
    if input.keyPressed[.D] {
      clay.SetDebugModeEnabled(!clay.IsDebugModeEnabled())
    }
  }

  playlist := &app.playlist

  UI_mousePos := clay.Vector2{input.mousePos.x, input.mousePos.y}
  clay.SetPointerState(UI_mousePos, input.mouseLeftDown && !scrollbarData.mouseDown)
  clay.SetLayoutDimensions(clay.Dimensions{f32(app.windowWidth), f32(app.windowHeight)})
  if !input.mouseLeftDown { scrollbarData.mouseDown = false }

  if input.mouseLeftDown && !scrollbarData.mouseDown && clay.PointerOver(clay.ID("ScrollBar")) {
    scrollContainerData := clay.GetScrollContainerData(clay.ID("SongList"))
    scrollbarData.clickOrigin = UI_mousePos
    scrollbarData.positionOrigin = scrollContainerData.scrollPosition^
    scrollbarData.mouseDown = true
  } else if scrollbarData.mouseDown {
    scrollContainerData := clay.GetScrollContainerData(clay.ID("SongList"))
    if scrollContainerData.contentDimensions.height > 0 {
      ratio := clay.Vector2 {
        scrollContainerData.contentDimensions.width / scrollContainerData.scrollContainerDimensions.width,
        scrollContainerData.contentDimensions.height / scrollContainerData.scrollContainerDimensions.height,
      }
      if scrollContainerData.config.vertical {
        scrollContainerData.scrollPosition.y = scrollbarData.positionOrigin.y + (scrollbarData.clickOrigin.y - input.mousePos.y) * ratio.y
      }
      if scrollContainerData.config.horizontal {
        scrollContainerData.scrollPosition.x = scrollbarData.positionOrigin.x + (scrollbarData.clickOrigin.x - input.mousePos.x) * ratio.x
      }
    }
  }

  playlist.activeSongChanged = false
  playlist.playingSongChanged = false

  SCROLL_INTENSITY :: 2
  clay.UpdateScrollContainers(true, clay.Vector2{input.mouseWheel.x, input.mouseWheel.y*SCROLL_INTENSITY}, input.deltaTime)
}

COLOR_ORANGE :: clay.Color{225, 138, 50, 255}
//COLOR_ORANGE :: clay.Color{10, 138, 50, 255}
COLOR_BLUE :: clay.Color{111, 173, 162, 255}
COLOR_LIGHT :: clay.Color{224, 215, 210, 255}
COLOR_DARKBLUE :: clay.Color{10, 86, 86, 255}
COLOR_RED :: clay.Color{168, 66, 28, 255}

// clay.SizingGrow({})
sizingGrow0  :: clay.SizingAxis{type = .Grow}
sizingGrow00 :: clay.Sizing{{type = .Grow}, {type = .Grow}}

SliderDeclaration :: struct {
  id: clay.ElementId,
  width: clay.SizingAxis,
  min, max: f32,
  value: ^f32,
}

GeneralSlider :: proc(app: ^AppData, input: ^Input, sliderDeclaration: SliderDeclaration, loc := #caller_location)
{
  fmt.assertf(sliderDeclaration.value != nil, "nil for value attribute isn't allowed, called from: %v", loc)
  fmt.assertf(sliderDeclaration.id.id != 0, "uninitialized id attribute isn't allowed, called from: %v", loc)
  if clay.UI(sliderDeclaration.id)({layout = {sizing = {sliderDeclaration.width, clay.SizingFixed(30)}, childAlignment = {.Center, .Center}}}) {
    dotSize: f32 = 24
    dotRadius: f32 = 12
    percentage := sliderDeclaration.value^/sliderDeclaration.max
    sliderData := clay.GetElementData(sliderDeclaration.id)
    if clay.Hovered() {
      if input.mouseLeftDown { app.sliderSelected = sliderDeclaration.id }
    }
    if app.sliderSelected.id == sliderDeclaration.id.id && app.sliderSelected.offset == sliderDeclaration.id.offset {
      percentage = (input.mousePos.x - sliderData.boundingBox.x) / sliderData.boundingBox.width
      percentage = clamp(percentage, 0.0, 1.0)
      sliderDeclaration.value^ = percentage*sliderDeclaration.max
      if input.mouseLeftReleased { app.sliderSelected = ELEMENT_ID_NIL }
    }

    // NOTE: border attribute is calculated one frame after if I understand correctly, so it's better to use another ui element for the border
    if clay.UI()({layout = {sizing = {sizingGrow0, clay.SizingFixed(16)}}, cornerRadius = clay.CornerRadiusAll(4), backgroundColor = COLOR_LIGHT}) {}
    if clay.UI()({floating = {attachTo = .Parent, offset = {percentage*sliderData.boundingBox.width - dotSize/2, 0}, attachment = {.LeftCenter, .LeftCenter}}, layout = {sizing = {clay.SizingFixed(dotSize), clay.SizingFixed(dotSize)}, childAlignment = {.Center, .Center}}, /*border = {width = clay.BorderOutside(4), color = {40, 40, 40, 255}},*/ cornerRadius = clay.CornerRadiusAll(dotRadius), backgroundColor = {40, 40, 40, 255}}) {
      if clay.UI()({layout = {sizing = {clay.SizingFixed(20), clay.SizingFixed(20)}}, cornerRadius = clay.CornerRadiusAll(dotRadius), backgroundColor = COLOR_RED}) {}
    }
  }
}

// NOTE: This one has a slightly different behaviour
SongSlider :: proc(app: ^AppData, input: ^Input, id: clay.ElementId)
{
  if clay.UI(id)({layout = {sizing = {sizingGrow0, clay.SizingFixed(30)}, childAlignment = {.Center, .Center}}}) {
    dotSize: f32 = 24
    percentage := f32(app.musicTimePlayed) / f32(app.musicTimeLength)
    sliderData := clay.GetElementData(id)
    if clay.Hovered() {
      if input.mouseLeftDown { app.sliderSelected = id }
    }
    if app.sliderSelected.id == id.id {
      percentage = (input.mousePos.x - sliderData.boundingBox.x) / sliderData.boundingBox.width
      percentage = clamp(percentage, 0.0, 1.0)
      if input.mouseLeftReleased {
        if !mix.SetTrackPlaybackPosition(app.musicTrack, sdl.Sint64(percentage*f32(app.musicTimeLength))) {
          sdl.Log("Failed to seek into the music track")
        }
        app.sliderSelected = ELEMENT_ID_NIL
      }
    }
    app.musicSliderValue = percentage * f32(app.musicTimeLength)

    if clay.UI()({layout = {sizing = {sizingGrow0, clay.SizingFixed(20)}}, cornerRadius = clay.CornerRadiusAll(1), backgroundColor = COLOR_DARKBLUE}) {}
    
    if clay.UI()({floating = {attachTo = .Parent, offset = {percentage*sliderData.boundingBox.width - dotSize/2, 0}, attachment = {.LeftCenter, .LeftCenter}}, layout = {sizing = {clay.SizingFixed(dotSize), clay.SizingFixed(dotSize)}, childAlignment = {.Center, .Center}}, /*border = {width = clay.BorderOutside(4), color = {40, 40, 40, 255}},*/ cornerRadius = clay.CornerRadiusAll(2), backgroundColor = {40, 40, 40, 255}}) {
      if clay.UI()({layout = {sizing = {clay.SizingFixed(20), clay.SizingFixed(20)}}, cornerRadius = clay.CornerRadiusAll(2), backgroundColor = COLOR_RED}) {}
    }
  }
}

IconButton :: proc(app: ^AppData, input: ^Input, id: clay.ElementId, color: clay.Color, idx: UI_Button, isOn: ^bool = nil, invertShading := false) -> (pressed: bool)
{
  color := color
  clay._OpenElementWithId(id)

  if clay.Hovered() {
    if input.mouseLeftDown {
      color *= {0.8,0.8,0.8,1.0} if !invertShading else {1.2,1.2,1.2,1.0}
    } else {
      if input.mouseLeftReleased {
        if isOn != nil { isOn^ = !(isOn^) }
        pressed = true
      }
      color *= {0.85,0.85,0.85,1.0} if !invertShading else {1.15,1.15,1.15,1.0}
    }
    color.x = min(color.x, 255)
    color.y = min(color.y, 255)
    color.z = min(color.z, 255)
  }

  clay.ConfigureOpenElement({
    layout = {padding = clay.PaddingAll(2)},
    backgroundColor = color,
    cornerRadius = clay.CornerRadiusAll(2),
  })

  imgdata := Clay_ImageRenderData{
    texture = nil,
    spritesheet = &app.iconSpritesheet,
    imgIdx = i32(idx),
  }
  if clay.UI()({
    layout = {sizing = {width = clay.SizingFixed(32), height = clay.SizingFixed(32)}},
    image = {imageData = List_Append(&app.imageData, imgdata, app.arena_allocator)}}) {}

  clay._CloseElement()

  return
}

UI_Calculate :: proc(app: ^AppData, input: ^Input) -> clay.ClayArray(clay.RenderCommand)
{
  spall.SCOPED_EVENT(&app.spall_ctx, &app.spall_buffer, #procedure)

  CLAY_BORDER_OUTSIDE :: #force_inline proc(widthValue: u16) -> clay.BorderWidth
  {
    return clay.BorderWidth{widthValue, widthValue, widthValue, widthValue, 0}
  }

  GetElementId :: #force_inline proc(id: string) -> clay.ElementId
  {
    return clay.GetElementId(clay.MakeString(id))
  }

  playlist := &app.playlist

  clay.BeginLayout()

  if clay.UI(clay.ID("OuterContainer"))({layout = {sizing = sizingGrow00, padding = clay.PaddingAll(16), childGap = 16}, backgroundColor = {250,250,255,255}}) {
    if clay.UI(clay.ID("SideBar"))({layout = {
        layoutDirection = .TopToBottom, sizing = {width = clay.SizingFixed(300), height = clay.SizingGrow({})}, padding = {0, 0, 0, 16}, childGap = 16},
        backgroundColor = COLOR_LIGHT})
    {
      if clay.UI(clay.ID("Playlist"))({layout = {layoutDirection = .LeftToRight, sizing = sizingGrow00}, backgroundColor = COLOR_ORANGE}) {
        if clay.UI()({layout = {layoutDirection = .TopToBottom, padding = {16,16,16,16}, sizing = sizingGrow00}}) {
          clay.Text(playlist.name, clay.TextElementConfig({fontSize = 14, textColor = {0, 0, 0, 255}}))
          songCountText := fmt.tprintf("%d songs", len(playlist.songs))
          clay.Text(songCountText, clay.TextElementConfig({fontSize = 12, textColor = {0, 0, 0, 255}}))
        }
 
        if clay.UI(clay.ID("PlaylistButtons"))({layout = {padding = {16,16,16,16}, childGap = 8}}) {
          if IconButton(app, input, clay.ID("OpenDirTempButton"), COLOR_LIGHT, UI_Button.OPEN_DIR)
          {
            sdl.ShowOpenFolderDialog(OpenFolderAddTempCallback, cast(rawptr)app, app.window, ".", true)
          }

          if IconButton(app, input, clay.ID("OpenDirPermButton"), COLOR_LIGHT, UI_Button.OPEN_DIR_PLUS)
          {
            sdl.ShowOpenFolderDialog(OpenFolderAddPermCallback, cast(rawptr)app, app.window, ".", true)
          }
        }
      }

      if clay.UI(clay.ID("SongList"))({layout = { layoutDirection = .TopToBottom, padding = {16, 24, 0, 0}, childGap = 6, sizing = {width = sizingGrow0, height = sizingGrow0 }}, //clay.SizingFit({})}},
        clip = {vertical = true, childOffset = clay.GetScrollOffset()}})
      {
        for songIdx := 0; songIdx < len(playlist.songs); songIdx += 1
        {
          song := playlist.songs[songIdx]
          
          clay._OpenElementWithId(clay.ID(playlist.songs[songIdx].name, u32(songIdx)))

          colorMultiplier: f32 = 0.8 if app.playlist.playingSongIdx == songIdx else 1.0
          color := clay.Color{colorMultiplier,colorMultiplier,colorMultiplier,1.0}
          if clay.Hovered() {
            if input.mouseLeftDown {
              color = {176, 90, 34, 255} * color
              if playlist.playingSongIdx != songIdx {
                playlist.playingSongChanged = true
              }
              if playlist.activeSongIdx != songIdx {
                playlist.activeSongChanged = true
              }
              playlist.playingSongIdx = songIdx
              playlist.activeSongIdx = songIdx
            } else {
              color = {200, 110, 40, 255} * color
            }
          } else {
            color = COLOR_ORANGE * color
          }

          clay.ConfigureOpenElement({
            layout = {sizing = sizingGrow00, padding = {16,16,16,16}},
            backgroundColor = color,
          })

          clay.Text(song.filename, clay.TextElementConfig({fontSize = 16, textColor = {0, 0, 0, 255}}))

          clay._CloseElement()
        }
      }
    }

    if clay.UI(clay.ID("ActiveSongContainer"))({layout = {layoutDirection = .TopToBottom, sizing = sizingGrow00, padding = {16, 16, 16, 16}, childGap = 16}, backgroundColor = COLOR_LIGHT}) {
      if playlist.activeSongIdx != -1 {
        activeSong := playlist.songs[playlist.activeSongIdx]
        clay.Text(activeSong.name, clay.TextElementConfig({fontSize = 16, textColor = {0, 0, 0, 255}}))
        clay.Text(activeSong.group, clay.TextElementConfig({fontSize = 16, textColor = {0, 0, 0, 255}}))
        if app.musicLoaded {
          if clay.UI(clay.ID("MusicInfo"))({layout = {layoutDirection = .TopToBottom, sizing = sizingGrow00, padding = {16, 16, 16, 16}, childGap = 8}, backgroundColor = COLOR_ORANGE}) {
            musicLenSecs := app.musicTimeLengthMs / 1000
            musicLenMins := musicLenSecs / 60
            musicLenSecs %= 60
            musicPlayedSecs := mix.TrackFramesToMS(app.musicTrack, sdl.Sint64(app.musicSliderValue)) / 1000
            musicPlayedMins := musicPlayedSecs / 60
            musicPlayedSecs %= 60
            musicText := fmt.tprintf("%2d:%2d/%2d:%2d", musicPlayedMins, musicPlayedSecs, musicLenMins, musicLenSecs)
            clay.Text(musicText, clay.TextElementConfig({fontSize = 14, textColor = {0, 0, 0, 255}}))

            if clay.UI()({layout = {sizing = {sizingGrow0, clay.SizingFit({})}, padding = {4, 4, 0, 0}}}) {
              SongSlider(app, input, clay.ID("SongProgressSlider"))
            }

            prevVolume := app.volume
            if clay.UI()({layout = {layoutDirection = .TopToBottom, sizing = sizingGrow00, childAlignment = {.Left, .Bottom}}})
            {
              if clay.UI(clay.ID("BottomContainer"))({
                layout = {
                  layoutDirection = .LeftToRight,
                  sizing = sizingGrow00,
                  childAlignment = {.Left, .Bottom},
                  childGap = 4,
                }})
              {
                backcolor := COLOR_LIGHT
                backcolor_dark := backcolor * {0.95,0.95,0.95,1.0}
                if IconButton(app, input, clay.ID("PlayButton"), backcolor, 
                              UI_Button.PLAY if app.musicPause else UI_Button.PAUSE,
                              &app.musicPause)
                {
                  PauseOrResume(app)
                }

                if IconButton(app, input, clay.ID("RandomizeButton"), backcolor,
                              UI_Button.RANDOMIZE)
                {
                  RandomizeSongs(app)
                }

                if IconButton(app, input, clay.ID("LoopingButton"),
                              backcolor_dark if app.musicLooping else backcolor,
                              UI_Button.LOOP_CURRENT, &app.musicLooping, app.musicLooping)
                {
                  HandleMusicLooping(app)
                }

                if clay.UI()({layout = {layoutDirection = .TopToBottom, sizing = sizingGrow00, childAlignment = {.Right, .Bottom}}})
                {
                  GeneralSlider(app, input, {id = clay.ID("volumeSlider"), width = clay.SizingPercent(0.5), max = 1.0, value = &app.volume})
                  clay.Text(fmt.tprintf("volume: %3.1f%%", 100.0*app.volume), clay.TextElementConfig({fontSize = 14, textColor = {0, 0, 0, 255}}))
                }
              }
            }

            if app.volume != prevVolume {
              if !mix.SetMixerGain(app.mixer, app.volume) {
                sdl.Log("Could not set volume: %s", sdl.GetError())
              }
            }
          }
        }
      }
    }
  }

  scrollData := clay.GetScrollContainerData(GetElementId("SongList"))
  if scrollData.found {
    if clay.UI(clay.ID("ScrollBar"))({floating = {attachTo = .ElementWithId,
      offset = {0, -(scrollData.scrollPosition.y/scrollData.contentDimensions.height) * scrollData.scrollContainerDimensions.height},
      zIndex = 1, parentId = GetElementId("SongList").id, attachment = {element = .RightTop, parent = .RightTop}}})
    {
      if clay.UI(clay.ID("ScrollBarButton"))({layout = {sizing = {clay.SizingFixed(12), clay.SizingFixed((scrollData.scrollContainerDimensions.height/scrollData.contentDimensions.height)*scrollData.scrollContainerDimensions.height)}},
        backgroundColor = clay.PointerOver(clay.ID("ScrollBar")) ? {100, 100, 140, 150} : {120, 120, 160, 150},
        cornerRadius = clay.CornerRadiusAll(6)}) {}
    }
  }

  return clay.EndLayout(input.deltaTime)
}
