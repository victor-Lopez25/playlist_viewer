package main

import "core:math"

import clay "clay-odin"
import sdl "vendor:sdl3"
import "vendor:sdl3/ttf"

SDL_MeasureText :: proc "c"(text: clay.StringSlice, config: ^clay.TextElementConfig, userData: rawptr) -> clay.Dimensions
{
  fonts := cast([^]^ttf.Font)userData
  font := fonts[config.fontId]

  width, height: i32
  if !ttf.GetStringSize(font, cstring(text.chars), uint(text.length), &width, &height) {
    sdl.LogError(i32(sdl.LogCategory.ERROR), "Failed to measure text: %s", sdl.GetError())
  }

  return clay.Dimensions{f32(width), f32(height)}
}

Clay_SDL3RendererData :: struct {
  renderer: ^sdl.Renderer,
  textEngine: ^ttf.TextEngine,
  fonts: []^ttf.Font,

  roundedRectVertices: [dynamic]sdl.Vertex,
  roundedRectIndices: [dynamic]i32,
  arcPoints: [dynamic]sdl.FPoint,
}

@(private="file") NUM_CIRCLE_SEGMENTS :: 16

@(private="file")
SDL_Clay_RenderFillRoundedRect :: proc(rendererData: ^Clay_SDL3RendererData, rect: sdl.FRect, cornerRadius: f32, _color: clay.Color)
{
  color := sdl.FColor{ _color.r/255, _color.g/255, _color.b/255, _color.a/255 };

  indexCount: i32 = 0
  vertexCount: i32 = 0

  minRadius := min(rect.w, rect.h) / 2.0
  clampedRadius := min(cornerRadius, minRadius)

  numCircleSegments := max(NUM_CIRCLE_SEGMENTS, int(clampedRadius*0.5))

  totalVertices := 4 + (4 * (numCircleSegments * 2)) + 2*4
  totalIndices := 6 + (4 * (numCircleSegments * 3)) + 6*4

  resize(&rendererData.roundedRectVertices, totalVertices)
  resize(&rendererData.roundedRectIndices, totalIndices)
  vertices := rendererData.roundedRectVertices[:]
  indices := rendererData.roundedRectIndices[:]

  //define center rectangle
  vertices[vertexCount] = sdl.Vertex{ {rect.x + clampedRadius, rect.y + clampedRadius}, color, {0, 0} }; //0 center TL
  vertices[vertexCount+1] = sdl.Vertex{ {rect.x + rect.w - clampedRadius, rect.y + clampedRadius}, color, {1, 0} }; //1 center TR
  vertices[vertexCount+2] = sdl.Vertex{ {rect.x + rect.w - clampedRadius, rect.y + rect.h - clampedRadius}, color, {1, 1} }; //2 center BR
  vertices[vertexCount+3] = sdl.Vertex{ {rect.x + clampedRadius, rect.y + rect.h - clampedRadius}, color, {0, 1} }; //3 center BL
  vertexCount += 4

  indices[indexCount] = 0
  indices[indexCount+1] = 1
  indices[indexCount+2] = 3
  indices[indexCount+3] = 1
  indices[indexCount+4] = 2
  indices[indexCount+5] = 3
  indexCount += 6

  step := f32(math.PI)/2 / f32(numCircleSegments)
  for i := 0; i < numCircleSegments; i += 1 {
    angle1 := f32(i)*step
    angle2 := (f32(i)+1.0)*step

    for j: i32 = 0; j < 4; j += 1 { // Iterate over four corners
      cx, cy, signX, signY: f32

      switch j {
        case 0: cx = rect.x + clampedRadius
        cx = rect.x + clampedRadius; cy = rect.y + clampedRadius; signX = -1; signY = -1; break; // Top-left
        case 1: cx = rect.x + rect.w - clampedRadius; cy = rect.y + clampedRadius; signX = 1; signY = -1; break; // Top-right
        case 2: cx = rect.x + rect.w - clampedRadius; cy = rect.y + rect.h - clampedRadius; signX = 1; signY = 1; break; // Bottom-right
        case 3: cx = rect.x + clampedRadius; cy = rect.y + rect.h - clampedRadius; signX = -1; signY = 1; break; // Bottom-left
        case: return
      }

      vertices[vertexCount] = sdl.Vertex{ {cx + sdl.cosf(angle1) * clampedRadius * signX, cy + sdl.sinf(angle1) * clampedRadius * signY}, color, {0, 0} }
      vertices[vertexCount+1] = sdl.Vertex{ {cx + sdl.cosf(angle2) * clampedRadius * signX, cy + sdl.sinf(angle2) * clampedRadius * signY}, color, {0, 0} }
      vertexCount += 2

      indices[indexCount] = j;  // Connect to corresponding central rectangle vertex
      indices[indexCount+1] = vertexCount - 2;
      indices[indexCount+2] = vertexCount - 1;
      indexCount += 3
    }
  }

  //Define edge rectangles
  // Top edge
  vertices[vertexCount] = sdl.Vertex{ {rect.x + clampedRadius, rect.y}, color, {0, 0} }; //TL
  vertices[vertexCount+1] = sdl.Vertex{ {rect.x + rect.w - clampedRadius, rect.y}, color, {1, 0} }; //TR
  vertexCount += 2

  indices[indexCount] = 0;
  indices[indexCount+1] = vertexCount - 2; //TL
  indices[indexCount+2] = vertexCount - 1; //TR
  indices[indexCount+3] = 1;
  indices[indexCount+4] = 0;
  indices[indexCount+5] = vertexCount - 1; //TR
  indexCount += 6
  // Right edge
  vertices[vertexCount] = sdl.Vertex{ {rect.x + rect.w, rect.y + clampedRadius}, color, {1, 0} }; //RT
  vertices[vertexCount+1] = sdl.Vertex{ {rect.x + rect.w, rect.y + rect.h - clampedRadius}, color, {1, 1} }; //RB
  vertexCount += 2

  indices[indexCount] = 1;
  indices[indexCount+1] = vertexCount - 2; //RT
  indices[indexCount+2] = vertexCount - 1; //RB
  indices[indexCount+3] = 2;
  indices[indexCount+4] = 1;
  indices[indexCount+5] = vertexCount - 1; //RB
  // Bottom edge
  vertices[vertexCount] = sdl.Vertex{ {rect.x + rect.w - clampedRadius, rect.y + rect.h}, color, {1, 1} }; //BR
  vertices[vertexCount+1] = sdl.Vertex{ {rect.x + clampedRadius, rect.y + rect.h}, color, {0, 1} }; //BL
  indexCount += 6
  vertexCount += 2

  indices[indexCount] = 2;
  indices[indexCount+1] = vertexCount - 2; //BR
  indices[indexCount+2] = vertexCount - 1; //BL
  indices[indexCount+3] = 3;
  indices[indexCount+4] = 2;
  indices[indexCount+5] = vertexCount - 1; //BL
  // Left edge
  vertices[vertexCount] = sdl.Vertex{ {rect.x, rect.y + rect.h - clampedRadius}, color, {0, 1} }; //LB
  vertices[vertexCount+1] = sdl.Vertex{ {rect.x, rect.y + clampedRadius}, color, {0, 0} }; //LT
  indexCount += 6
  vertexCount += 2

  indices[indexCount] = 3;
  indices[indexCount+1] = vertexCount - 2; //LB
  indices[indexCount+2] = vertexCount - 1; //LT
  indices[indexCount+3] = 0;
  indices[indexCount+4] = 3;
  indices[indexCount+5] = vertexCount - 1; //LT
  indexCount += 6

  // Render everything
  sdl.RenderGeometry(rendererData.renderer, nil, &vertices[0], vertexCount, &indices[0], indexCount);
}

@(private="file")
SDL_Clay_RenderArc :: proc(rendererData: ^Clay_SDL3RendererData, center: sdl.FPoint, radius, startAngle, endAngle, thickness: f32, color: clay.Color)
{
  sdl.SetRenderDrawColor(rendererData.renderer, u8(color.r), u8(color.g), u8(color.b), u8(color.a))

  radStart := startAngle * (math.PI / 180.0)
  radEnd := endAngle * (math.PI / 180.0)

  numCircleSegments := max(NUM_CIRCLE_SEGMENTS, i32(radius*1.5)) //increase circle segments for larger circles, 1.5 is arbitrary.

  angleStep := (radEnd - radStart) / f32(numCircleSegments)
  thicknessStep: f32 = 0.4 //arbitrary value to avoid overlapping lines. Changing THICKNESS_STEP or numCircleSegments might cause artifacts.

  resize(&rendererData.arcPoints, numCircleSegments + 1)
  points := rendererData.arcPoints[:]

  for t := thicknessStep; t < thickness - thicknessStep; t += thicknessStep {
    clampedRadius := max(radius - t, 1.0)

    for i: i32 = 0; i <= numCircleSegments; i += 1 {
      angle := radStart + f32(i) * angleStep
      points[i] = sdl.FPoint {
        sdl.roundf(center.x + sdl.cosf(angle) * clampedRadius),
        sdl.roundf(center.y + sdl.sinf(angle) * clampedRadius),
      }
    }
    sdl.RenderLines(rendererData.renderer, &points[0], numCircleSegments + 1)
  }
}

currentClippingRectangle: sdl.Rect

SDL_RenderClayCommands :: proc(rendererData: ^Clay_SDL3RendererData, rcommands: ^clay.ClayArray(clay.RenderCommand))
{
  for i: i32 = 0; i < rcommands.length; i += 1 {
    rcmd := clay.RenderCommandArray_Get(rcommands, i)
    bounding_box := rcmd.boundingBox

    rect := sdl.FRect{ f32(int(bounding_box.x)), f32(int(bounding_box.y)), f32(int(bounding_box.width)), f32(int(bounding_box.height)) }

    switch rcmd.commandType {
      case .Rectangle: {
        config := &rcmd.renderData.rectangle
        sdl.SetRenderDrawBlendMode(rendererData.renderer, {.BLEND})
        sdl.SetRenderDrawColor(rendererData.renderer, u8(config.backgroundColor.r), u8(config.backgroundColor.g), u8(config.backgroundColor.b), u8(config.backgroundColor.a))
        if config.cornerRadius.topLeft > 0 {
          SDL_Clay_RenderFillRoundedRect(rendererData, rect, config.cornerRadius.topLeft, config.backgroundColor)
        } else {
          sdl.RenderFillRect(rendererData.renderer, &rect)
        }
      } break;

      case .Text: {
        config := &rcmd.renderData.text
        font := rendererData.fonts[config.fontId]
        text := ttf.CreateText(rendererData.textEngine, font, cstring(config.stringContents.chars), uint(config.stringContents.length))
        ok := ttf.SetTextColor(text, u8(config.textColor.r), u8(config.textColor.g), u8(config.textColor.b), u8(config.textColor.a))
        assert(ok)
        ok = ttf.DrawRendererText(text, rect.x, rect.y)
        assert(ok)
        ttf.DestroyText(text)
      } break;
      
      case .Border: {
        config := &rcmd.renderData.border

        minRadius := min(rect.w, rect.h) /2.0
        clampedRadii := clay.CornerRadius{
          topLeft = min(config.cornerRadius.topLeft, minRadius),
          topRight = min(config.cornerRadius.topRight, minRadius),
          bottomLeft = min(config.cornerRadius.bottomLeft, minRadius),
          bottomRight = min(config.cornerRadius.bottomRight, minRadius),
        }
        //edges
        sdl.SetRenderDrawColor(rendererData.renderer, u8(config.color.r), u8(config.color.g), u8(config.color.b), u8(config.color.a))
        if config.width.left > 0 {
          starting_y := rect.y + clampedRadii.topLeft
          length := rect.h - clampedRadii.topLeft - clampedRadii.bottomLeft
          line := sdl.FRect{ rect.x, starting_y, f32(config.width.left), length }
          sdl.RenderFillRect(rendererData.renderer, &line)
        }
        if config.width.right > 0 {
          starting_x := rect.x + rect.w - f32(config.width.right)
          starting_y := rect.y + clampedRadii.topRight
          length := rect.h - clampedRadii.topRight - clampedRadii.bottomRight
          line := sdl.FRect{ starting_x, starting_y, f32(config.width.right), length }
          sdl.RenderFillRect(rendererData.renderer, &line)
        }
        if config.width.top > 0 {
          starting_x := rect.x + clampedRadii.topLeft
          starting_y := rect.y + rect.h - f32(config.width.bottom)
          length := rect.w - clampedRadii.bottomLeft - clampedRadii.bottomRight
          line := sdl.FRect{ starting_x, starting_y, length, f32(config.width.bottom) }
          // NOTE: Not sure why this was in the original clay_sdl3 renderer
          //sdl.SetRenderDrawColor(rendererData.renderer, u8(config.color.r), u8(config.color.g), u8(config.color.b), u8(config.color.a))
          sdl.RenderFillRect(rendererData.renderer, &line)
        }
        //corners
        if config.cornerRadius.topLeft > 0 {
          centerX := rect.x + clampedRadii.topLeft -1
          centerY := rect.y + clampedRadii.topLeft
          SDL_Clay_RenderArc(rendererData, {centerX, centerY}, clampedRadii.topLeft, 180.0, 270.0, f32(config.width.top), config.color)
        }
        if config.cornerRadius.topRight > 0 {
          centerX := rect.x + rect.w - clampedRadii.topRight -1
          centerY := rect.y + clampedRadii.topRight
          SDL_Clay_RenderArc(rendererData, {centerX, centerY}, clampedRadii.topRight, 270.0, 360.0, f32(config.width.top), config.color)
        }
        if config.cornerRadius.bottomLeft > 0 {
          centerX := rect.x + clampedRadii.bottomLeft -1
          centerY := rect.y + rect.h - clampedRadii.bottomLeft -1
          SDL_Clay_RenderArc(rendererData, {centerX, centerY}, clampedRadii.bottomLeft, 90.0, 180.0, f32(config.width.bottom), config.color)
        }
        if config.cornerRadius.bottomRight > 0 {
          centerX := rect.x + rect.w - clampedRadii.bottomRight -1 //TODO: why need to -1 in all calculations???
          centerY := rect.y + rect.h - clampedRadii.bottomRight -1
          SDL_Clay_RenderArc(rendererData, {centerX, centerY}, clampedRadii.bottomRight, 0.0, 90.0, f32(config.width.bottom), config.color)
        }
      } break;
      
      case .ScissorStart: {
        boundingBox := rcmd.boundingBox
        currentClippingRectangle.x = i32(boundingBox.x)
        currentClippingRectangle.y = i32(boundingBox.y)
        currentClippingRectangle.w = i32(boundingBox.width)
        currentClippingRectangle.h = i32(boundingBox.height)
        sdl.SetRenderClipRect(rendererData.renderer, &currentClippingRectangle)
      } break;
      
      case .ScissorEnd: {
        sdl.SetRenderClipRect(rendererData.renderer, nil)
      } break;
      
      case .Image: {
        texture := cast(^sdl.Texture)rcmd.renderData.image.imageData
        dest := sdl.FRect{ rect.x, rect.y, rect.w, rect.h }
        sdl.RenderTexture(rendererData.renderer, texture, nil, &dest)
      } break;
      
      case .Custom: break; // Nothing here for now...

      case .None: fallthrough
      case: sdl.Log("Unknown render command type: %d", rcmd.commandType)
    }
  }
}