package spallwrapper

import "core:time"
import "core:prof/spall"

Begin_Event :: spall.Begin_Event
Buffer :: spall.Buffer
Context :: spall.Context
End_Event :: spall.End_Event
Manual_Buffer_Header :: spall.Manual_Buffer_Header
Manual_Event_Type :: spall.Manual_Event_Type
Manual_Stream_Header :: spall.Manual_Stream_Header
Name_Event :: spall.Name_Event
Pad_Skip :: spall.Pad_Skip

when ODIN_DEBUG {
  // NOTE: random thing from core:time to avoid error
  Nanosecond :: time.Duration(1)

  BUFFER_DEFAULT_SIZE :: 0x10_0000
  SCOPED_EVENT :: spall.SCOPED_EVENT
  buffer_create :: spall.buffer_create
  buffer_destroy :: spall.buffer_destroy
  buffer_flush :: spall.buffer_flush
  context_create_with_scale :: spall.context_create_with_scale
  context_create_with_sleep :: spall.context_create_with_sleep
  context_destroy :: spall.context_destroy
  _buffer_begin :: spall._buffer_begin
  _buffer_end :: spall._buffer_end
} else {
  BUFFER_DEFAULT_SIZE :: 0x4

  SCOPED_EVENT :: proc(ctx: ^Context, buffer: ^Buffer, name: string, args: string = "", location := #caller_location) -> bool { return true }

  buffer_create :: proc(data: []u8, tid: u32 = 0, pid: u32 = 0) -> (buffer: Buffer, ok: bool) #optional_ok { ok = true; return }

  buffer_destroy :: proc(ctx: ^Context, buffer: ^Buffer) {}

  buffer_flush :: proc "contextless" (ctx: ^Context, buffer: ^Buffer) {}

  context_create_with_scale :: proc(filename: string, precise_time: bool, timestamp_scale: f64) -> (ctx: Context, ok: bool) { ok = true; return }

  context_create_with_sleep :: proc(filename: string, sleep: time.Duration = 2 * time.Second) -> (ctx: Context, ok: bool) { ok = true; return }

  context_destroy :: proc(ctx: ^Context) {}

  @(no_instrumentation)
  _buffer_begin :: proc "contextless" (ctx: ^Context, buffer: ^Buffer, name: string, args: string = "", location := #caller_location) #no_bounds_check /* bounds check would segfault instrumentation */ {}

  @(no_instrumentation)
  _buffer_end :: proc "contextless" (ctx: ^Context, buffer: ^Buffer) #no_bounds_check /* bounds check would segfault instrumentation */ {}
}

context_create :: proc{
  context_create_with_scale,
  context_create_with_sleep,
}