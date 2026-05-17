package main

import "core:os"
import "core:mem"
import "core:fmt"
import "core:strings"
import "core:encoding/json"
import sdl "vendor:sdl3"
import sdl_img "vendor:sdl3/image"

AsepriteRect :: struct {
  x: i32,
  y: i32,
  w: i32,
  h: i32,
}

AsepriteScale :: struct {
  w: i32,
  h: i32,
}

AsepriteSpritesheetJson :: struct {
  frames: []struct {
    filename: string,
    frame: AsepriteRect,
    rotated: bool,
    trimmed: bool,
    spriteSourceSize: AsepriteRect,
    sourceSize: AsepriteScale,
    duration: i32, // duration in ms
  },
  meta: struct {
    app: string,
    version: string,
    image: string,
    format: string,
    size: AsepriteScale,
    scale: string,
  },
}

TRANSPARENT :: 0
PRIMARY     :: 1
SECONDARY   :: 2
TERNIARY    :: 3

SpritesheetData :: struct {
  aseprite: AsepriteSpritesheetJson,
  indexedImg: ^sdl.Surface,
  palette: ^sdl.Palette,
  tex: ^sdl.Texture,
  texMutex: ^sdl.Mutex,
  pixelIndexes: [4]u8,
}

LoadAsepriteSpritesheetData :: proc(spritesheetData: ^SpritesheetData, jsonfile: string, allocator: mem.Allocator) -> bool
{
  spritesheetData.texMutex = sdl.CreateMutex()
  if spritesheetData.texMutex == nil {
    fmt.eprintfln("Could not create mutex for spritesheet texture: %s", sdl.GetError())
    return false
  }

  data, os_err := os.read_entire_file(jsonfile, context.temp_allocator)
  if os_err != nil {
    fmt.eprintfln("Could not read %s: %v", jsonfile, os_err)
    return false
  }

  unmarshal_err := json.unmarshal(
    data = data,
    ptr = &spritesheetData.aseprite,
    allocator = allocator,
  )
  if unmarshal_err != nil {
    fmt.eprintfln("Could not unmarshal aseprite json data from %s: %v", jsonfile, unmarshal_err)
    return false
  }

  imgfile: cstring = ---
  if !os.exists(spritesheetData.aseprite.meta.image) {
    path, _ := os.join_path({os.dir(jsonfile), spritesheetData.aseprite.meta.image}, context.temp_allocator)
    imgfile = strings.clone_to_cstring(path, context.temp_allocator)
  } else {
    imgfile = strings.clone_to_cstring(spritesheetData.aseprite.meta.image, context.temp_allocator)
  }
  srcImg := sdl_img.Load(imgfile)
  defer sdl.DestroySurface(srcImg)
  if srcImg == nil {
    fmt.eprintfln("Could not load spritesheet image from file %s: %s", 
      spritesheetData.aseprite.meta.image, sdl.GetError())
    return false
  }

  spritesheetData.indexedImg = sdl.ConvertSurface(srcImg, .INDEX8)
  if spritesheetData.indexedImg == nil {
    fmt.eprintfln("Could not convert spritesheet surface to indexed: %s", sdl.GetError())
    return false
  }

  spritesheetData.palette = sdl.GetSurfacePalette(spritesheetData.indexedImg)
  if spritesheetData.palette == nil {
    fmt.eprintfln("Could not create spritesheet palette: %s", sdl.GetError())
    return false
  }

  spritesheetData.pixelIndexes[TRANSPARENT] = u8(sdl.MapSurfaceRGB(spritesheetData.indexedImg, 0xFF, 0, 0))
  spritesheetData.pixelIndexes[PRIMARY] = u8(sdl.MapSurfaceRGB(spritesheetData.indexedImg, 0xFF, 0xFF, 0xFF))
  spritesheetData.pixelIndexes[SECONDARY] = u8(sdl.MapSurfaceRGB(spritesheetData.indexedImg, 0, 0, 0))
  spritesheetData.pixelIndexes[TERNIARY] = u8(sdl.MapSurfaceRGB(spritesheetData.indexedImg, 0x99, 0x99, 0x99))

  if !sdl.SetSurfaceColorKey(spritesheetData.indexedImg, true, u32(spritesheetData.pixelIndexes[TRANSPARENT])) {
    fmt.eprintfln("Could not set transparent pixel color key: %s", sdl.GetError())
    return false
  }
  return true
}

MapSpritesheetColors :: proc(renderer: ^sdl.Renderer, spritesheet: ^SpritesheetData, primary, secondary, terniary: sdl.Color) -> bool
{
  colors := [4]sdl.Color {
    {0, 0, 0, 0}, primary, secondary, terniary,
  }

  for idxidx: u8 = 1; idxidx < len(spritesheet.pixelIndexes); idxidx += 1 {
    idx := spritesheet.pixelIndexes[idxidx]
    spritesheet.palette.colors[idx] = colors[idxidx]
  }

  tex := sdl.CreateTextureFromSurface(renderer, spritesheet.indexedImg)
  if tex == nil {
    fmt.eprintfln("Could not create spritesheet texture from surface: %s", sdl.GetError())
    return false
  }

  sdl.LockMutex(spritesheet.texMutex)
  if spritesheet.tex != nil {
    sdl.DestroyTexture(spritesheet.tex)
  }
  spritesheet.tex = tex
  sdl.UnlockMutex(spritesheet.texMutex)

  return true
}

DestroySpritesheetData :: proc(data: ^SpritesheetData, allocator: mem.Allocator)
{
  for f in data.aseprite.frames {
    delete(f.filename, allocator)
  }
  delete(data.aseprite.frames, allocator)
  delete(data.aseprite.meta.app, allocator)
  delete(data.aseprite.meta.version, allocator)
  delete(data.aseprite.meta.image, allocator)
  delete(data.aseprite.meta.format, allocator)
  delete(data.aseprite.meta.scale, allocator)

  DestroySDL_SpritesheetData(data)
}

/* does not destroy anything in data.aseprite */
DestroySDL_SpritesheetData :: proc(data: ^SpritesheetData)
{
  sdl.DestroySurface(data.indexedImg)
  sdl.DestroyTexture(data.tex)
  sdl.DestroyMutex(data.texMutex)
}
