package hotreload

import "core:os" /* set_current_directory */
import "core:io"
import "core:mem"
import "core:fmt"
import "core:time"
import "core:os/os2"
import "core:dynlib"
import "core:path/filepath"

DLL_DIR :: "bin/hotreload/"
DLL_NAME :: "bin/app." + dynlib.LIBRARY_FILE_EXTENSION

dllFileHandle: ^os2.File
dllFileInfo: os2.File_Info
couldOpenFile: os2.Error
couldReadInfo: os2.Error

Api :: struct {
  library: dynlib.Library,
  InitAll: proc(rawptr, rawptr),
  InitPartial: proc(rawptr, rawptr),
  DeInitAll: proc(rawptr, rawptr),
  DeInitPartial: proc(rawptr, rawptr),
  MemorySize: proc() -> (int, int),
  MainLoop: proc(rawptr, rawptr) -> bool,

  modificationTime: time.Time,
  version: int,
}

copy_file_from_handle :: proc(dst_path: string, src: ^os2.File) -> os2.Error
{
  info := os2.fstat(src, context.temp_allocator) or_return
	if info.type == .Directory {
		return .Invalid_File
	}

	dst := os2.open(dst_path, {.Read, .Write, .Create, .Trunc}, info.mode & 0o777) or_return
	defer os2.close(dst)

	_, err := io.copy(os2.to_writer(dst), os2.to_reader(src))
	return err
}

CopyDll :: proc(to: string) -> bool {
  src, ferr := os2.open(DLL_NAME)
  if ferr != nil { return false }
  defer os2.close(src)

  copy_err := copy_file_from_handle(to, src)

  if copy_err != nil {
	  fmt.printfln("Failed to copy " + DLL_NAME + " to %s: %v", to, copy_err)
	  return false
  }
  return true
}

LoadDllProcs :: proc(version: int) -> (app: Api, ok: bool) {
  GetSymbol :: proc(library: dynlib.Library, sym: string, $T: typeid, func: ^T) -> bool {
    symbol, ok := dynlib.symbol_address(library, sym)
    if !ok {
      fmt.eprintfln("Could not load %s from " + DLL_NAME + ": %s", sym, dynlib.last_error())
    }
    func^ = cast(T)symbol
    return ok
  }

  modTime, err := os2.last_write_time_by_name(DLL_NAME)
  if err != os2.ERROR_NONE {
    fmt.eprintfln("Failed to get last write time of " + DLL_NAME + ": %v", err)
	  return
  }

  dll_name := fmt.tprintf(DLL_DIR + "app_%d." + dynlib.LIBRARY_FILE_EXTENSION, version)
  CopyDll(dll_name) or_return

  loadOk: bool
  app.library, loadOk = dynlib.load_library(dll_name)
  if !loadOk {
    fmt.eprintfln("Could not load %s: %s", dll_name, dynlib.last_error())
    return
  }

  GetSymbol(app.library, "InitAll", proc(rawptr, rawptr), &app.InitAll) or_return
  GetSymbol(app.library, "InitPartial", proc(rawptr, rawptr), &app.InitPartial) or_return
  GetSymbol(app.library, "DeInitAll", proc(rawptr, rawptr), &app.DeInitAll) or_return
  GetSymbol(app.library, "DeInitPartial", proc(rawptr, rawptr), &app.DeInitPartial) or_return
  GetSymbol(app.library, "MemorySize", proc() -> (int, int), &app.MemorySize) or_return
  GetSymbol(app.library, "MainLoop", proc(rawptr, rawptr) -> bool, &app.MainLoop) or_return

  app.version = version
  app.modificationTime = modTime
  ok = true
  return
}

UnloadApi :: proc(api: ^Api)
{
  if api.library != nil {
    if !dynlib.unload_library(api.library) {
      fmt.eprintfln("Could not unload " + DLL_NAME + ": %s", dynlib.last_error())
    }
  }
  name := fmt.tprintf(DLL_DIR + "app_%d." + dynlib.LIBRARY_FILE_EXTENSION, api.version)
  err := os2.remove(name)
  if err != nil {
    fmt.eprintfln("Failed to remove %s: %v", name, err)
  }
}

CompareSizes :: proc(size1old, size2old, size1new, size2new: int) -> bool {
  return (size1old != size1new) || (size2old != size2new)
}

main :: proc() {
  exe_path := os2.args[0]
  exe_dir := filepath.dir(string(exe_path), context.temp_allocator)
  os.set_current_directory(exe_dir)

  version := 0
  api, ok := LoadDllProcs(version)
  if !ok {
    os.exit(1)
  }

  version += 1
  appDataSize, inputSize := api.MemorySize()
  rawInput: rawptr
  rawApp, allocErr := mem.alloc(appDataSize)
  fmt.assertf(allocErr == nil, "Could not allocate mem for app: %v", allocErr)
  rawInput, allocErr = mem.alloc(inputSize)
  fmt.assertf(allocErr == nil, "Could not allocate mem for app: %v", allocErr)
  api.InitAll(rawApp, rawInput)

  oldApis := make([dynamic]Api, context.allocator)
  quit := false
  for !quit {
    fileTime, err := os2.last_write_time_by_name(DLL_NAME)
    reload := err == os2.ERROR_NONE && api.modificationTime != fileTime

    if reload {
      newApi, newOk := LoadDllProcs(version)
      if newOk {
        forceRestart := CompareSizes(api.MemorySize(), newApi.MemorySize())

        if !forceRestart {
          // normal hot reload
          append(&oldApis, api)
          api.DeInitPartial(rawApp, rawInput)
          api = newApi
          api.InitPartial(rawApp, rawInput)
        } else {
          // Full reset since I need to get new memory for rawApp & rawInput
          api.DeInitAll(rawApp, rawInput)

          for &a in oldApis { UnloadApi(&a) }

          clear(&oldApis)
          UnloadApi(&api)
          api = newApi
          appDataSize, inputSize = api.MemorySize()
          rawApp, allocErr = mem.alloc(appDataSize)
          fmt.assertf(allocErr == nil, "Could not allocate mem for app: %v", allocErr)
          rawInput, allocErr = mem.alloc(inputSize)
          fmt.assertf(allocErr == nil, "Could not allocate mem for app: %v", allocErr)
          api.InitAll(rawApp, rawInput)
        }
        version += 1
      }
    }

    quit = api.MainLoop(rawApp, rawInput)
  }

  api.DeInitAll(rawApp, rawInput)

  for &a in oldApis { UnloadApi(&a) }
  delete(oldApis)
}


// Make game use good GPU on laptops.
/*
@(export) NvOptimusEnablement: u32 = 1
@(export) AmdPowerXpressRequestHighPerformance: i32 = 1
*/