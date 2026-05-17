package build

import "core:os"
import "core:fmt"
import "core:dynlib"
import "core:strconv"
import "core:strings"

RELEASE_FLAGS :: []string{"-no-bounds-check", "-disable-assert", "-no-type-assert", "-o:speed"}
OUT_DIRECTORY :: "bin"
DLL_DIR :: OUT_DIRECTORY + "/hotreload"

when ODIN_OS == .Windows {
  PDBS_ENV_VAR :: "PLAYER_PDB_NUMBER"
  PDBS_DIR :: OUT_DIRECTORY + "/pdbs"
  EXECUTABLE :: "pv.exe" 
} else {
  EXECUTABLE :: "pv"
}

DLL_EXT :: "." + dynlib.LIBRARY_FILE_EXTENSION

IsExecutableRunning :: proc(exe: string) -> bool
{
  found := false
  pids, err := os.process_list(context.temp_allocator)
  fmt.assertf(err == nil, "Could not get process list: %v", err)
  for pid in pids {
    info, err := os.process_info_by_pid(pid, {.Executable_Path}, context.temp_allocator)
    fmt.assertf(err == nil, "Could not get process info: %v", err)
    if info.executable_path == exe {
      found = true
      break
    }
  }

  free_all(context.temp_allocator)
  return found
}

main :: proc()
{
  fmt.println(os.args)

  shouldClean := false
  debugMode := true
  shouldRun := false
  prepareRelease := false
  for arg in os.args[1:] {
    switch arg {
      case "clean":   shouldClean = true
      case "debug":   debugMode = true
      case "release": debugMode = false
      case "run":     shouldRun = true
      case "norun":   shouldRun = false
      case "prepare-release": {
        debugMode = false
        shouldRun = false
        prepareRelease = true
      }
    }
  }

  if shouldClean {
    os.remove(EXECUTABLE)
    os.remove_all(OUT_DIRECTORY)
    paths, err := os.glob("*.spall", context.temp_allocator)
    for p in paths {
      os.remove(p)
    }
  }

  isRunning := false
  absExePath, alloc_err := os.get_absolute_path(EXECUTABLE, context.temp_allocator)
  if alloc_err == nil {
    isRunning = IsExecutableRunning(absExePath)
  }

  if !os.exists(OUT_DIRECTORY) {
    os.make_directory(OUT_DIRECTORY)
  }

  if !isRunning {
    os.remove_all(DLL_DIR)
    os.make_directory(DLL_DIR)
    when ODIN_OS == .Windows {
      os.remove_all(PDBS_DIR)
      os.make_directory(PDBS_DIR)

      err := os.set_env(PDBS_ENV_VAR, "0")
      fmt.assertf(err == nil, "Could not set " + PDBS_ENV_VAR + " env: %v", err)
    }
  }

  pdb_num: int
  when ODIN_OS == .Windows {
    base := 10
    buf: [64]u8
    ok: bool

    pdb_num_str := os.get_env(buf[:], PDBS_ENV_VAR)
    pdb_num, ok = strconv.parse_int(pdb_num_str, base)
    if !ok {
      // If this failed it's because the terminal was closed
      pdb_num = 0
      fmt.eprintfln("Failed to parse int from " + PDBS_ENV_VAR + ". Defaulting to 1")
    }
    pdb_num += 1
    pdb_num_str = strconv.write_int(buf[:], i64(pdb_num), base)
    err := os.set_env(PDBS_ENV_VAR, pdb_num_str)
    fmt.assertf(err == nil, "Could not set " + PDBS_ENV_VAR + " env: %v", err)
    pdb_name := fmt.tprintf("-pdb-name:" + PDBS_DIR + "\\app_%v.pdb", pdb_num)
  } else {
    err: os.Error
  }

  cmd: [dynamic]string
  append(&cmd, "odin", "build", "src", "-vet", "-vet-using-param", "-vet-style", 
         "-build-mode:dll", "-out:" + OUT_DIRECTORY + "/app" + DLL_EXT)
  when ODIN_OS == .Windows {
    append(&cmd, pdb_name)
  }

  if debugMode {
    append(&cmd, "-debug")
  } else {
    append(&cmd, ..RELEASE_FLAGS)
  }

  desc := os.Process_Desc{
    command = cmd[:],
  }
  state: os.Process_State
  stdout, stderr: []u8

  fmt.printfln("CMD: %v", desc.command)
  state, stdout, stderr, err = os.process_exec(desc, context.temp_allocator)
  fmt.assertf(err == nil, "Could not execute process %v: %v", desc.command, err)
  fmt.printf(string(stdout))
  fmt.eprintf(string(stderr))
  if state.exit_code != 0 {
    fmt.eprintfln("Failed to compile app. Compiler exit code: %v", state.exit_code)
    os.exit(1)
  }

  if !isRunning {
    clear(&cmd)
    append(&cmd, "odin", "build", "src/hot-reload", "-out:" + EXECUTABLE, 
           "-vet", "-vet-using-param", "-vet-style")
    when ODIN_OS == .Windows {
      append(&cmd, "-pdb-name:" + OUT_DIRECTORY + "\\main_hot_reload.pdb")
    }
    if debugMode {
      append(&cmd, "-debug")
    } else {
      append(&cmd, ..RELEASE_FLAGS)
    }
    desc.command = cmd[:]
    fmt.printfln("CMD: %v", desc.command)
    state, stdout, stderr, err = os.process_exec(desc, context.temp_allocator)
    fmt.assertf(err == nil, "Could not execute process %v: %v", desc.command, err)
    fmt.printf(string(stdout))
    fmt.eprintf(string(stderr))
    if state.exit_code != 0 {
      fmt.eprintfln("Failed to compile app. Compiler exit code: %v", state.exit_code)
      os.exit(1)
    }
    
    clear(&cmd)
    append(&cmd, "odin", "root")
    desc.command = cmd[:]
    fmt.printfln("CMD: %v", desc.command)
    state, stdout, stderr, err = os.process_exec(desc, context.temp_allocator)
    fmt.assertf(err == nil, "Could not execute process %v: %v", desc.command, err)
    if state.exit_code != 0 {
      fmt.eprintf(string(stderr))
      fmt.eprintfln("Could not get odin root. Compiler exit code: %v", state.exit_code)
      os.exit(1)
    }

    paths, err := strings.split_lines(string(stdout), context.temp_allocator)
    fmt.assertf(err == nil, "Could not get memory for odin root paths: %v", err)

    when ODIN_OS == .Windows {
      // NOTE: SDL3, SDL3_ttf and SDL3_mixer only have bindings on linux, it is not prebuilt, so we depend on system libraries
      sdl_dll_name := "SDL3.dll" if ODIN_OS == .Windows else "libSDL3.so"
      if !os.exists("SDL3" + DLL_EXT) {
        sdl_dll_path := fmt.tprintf("%svendor/sdl3/SDL3" + DLL_EXT, paths[0])
        if os.exists(sdl_dll_path) {
          fmt.eprintfln("SDL3" + DLL_EXT + " not found in current directory. Copying from %s", sdl_dll_path)
          os_err := os.copy_file("./SDL3.dll", sdl_dll_path)
          fmt.assertf(os_err == nil, "Could not copy file: %v", os_err)
        } else {
          fmt.eprintfln("Please copy SDL3" + DLL_EXT + " from <your_odin_compiler>/vendor/sdl3/SDL3" + DLL_EXT + " to the same directory as " + EXECUTABLE)
        }
      }
      
      if !os.exists("SDL3_ttf" + DLL_EXT) {
        sdl_dll_path := fmt.tprintf("%svendor/sdl3/ttf/SDL3_ttf" + DLL_EXT, paths[0])
        if os.exists(sdl_dll_path) {
          fmt.eprintfln("SDL3_ttf" + DLL_EXT + " not found in current directory. Copying from %s", sdl_dll_path)
          os_err := os.copy_file("./SDL3_ttf.dll", sdl_dll_path)
          fmt.assertf(os_err == nil, "Could not copy file: %v", os_err)
        } else {
          fmt.eprintfln("Please copy SDL3_ttf" + DLL_EXT + " from <your_odin_compiler>/vendor/sdl3/ttf/SDL3_ttf" + DLL_EXT + " to the same directory as " + EXECUTABLE)
        }
      }
    
      if !os.exists("SDL3_mixer" + DLL_EXT) {
        sdl_dll_path := fmt.tprintf("%svendor/sdl3/mixer/SDL3_mixer" + DLL_EXT, paths[0])
        if os.exists(sdl_dll_path) {
          fmt.eprintfln("SDL3_mixer" + DLL_EXT + " not found in current directory. Copying from %s", sdl_dll_path)
          os_err := os.copy_file("./SDL3_mixer.dll", sdl_dll_path)
          fmt.assertf(os_err == nil, "Could not copy file: %v", os_err)
        } else {
          fmt.eprintfln("Please copy SDL3_mixer" + DLL_EXT + " from <your_odin_compiler>/vendor/sdl3/mixer/SDL3_mixer" + DLL_EXT + " to the same directory as " + EXECUTABLE)
        }
      }

      if !os.exists("SDL3_image" + DLL_EXT) {
        sdl_dll_path := fmt.tprintf("%svendor/sdl3/image/SDL3_image" + DLL_EXT, paths[0])
        if os.exists(sdl_dll_path) {
          fmt.eprintfln("SDL3_image" + DLL_EXT + " not found in current directory. Copying from %s", sdl_dll_path)
          os_err := os.copy_file("./SDL3_image.dll", sdl_dll_path)
          fmt.assertf(os_err == nil, "Could not copy file: %v", os_err)
        } else {
          fmt.eprintfln("Please copy SDL3_image" + DLL_EXT + " from <your_odin_compiler>/vendor/sdl3/image/SDL3_image" + DLL_EXT + " to the same directory as " + EXECUTABLE)
        }
      }
    }
    
    if shouldRun {
      os_err: os.Error

      clear(&cmd)
      append(&cmd, EXECUTABLE)
      desc.command = cmd[:]
      fmt.printfln("CMD: %v", desc.command)
      state, stdout, stderr, os_err = os.process_exec(desc, context.temp_allocator)
      fmt.assertf(err == nil, "Could not execute process %v: %v", desc.command, err)
      fmt.println(string(stdout))
      fmt.println(string(stderr))
      if state.exit_code != 0 {
        fmt.eprintfln("Error while executing " + EXECUTABLE + " status: %v", state.exit_code)
      }
    } else if prepareRelease {
      when ODIN_OS == .Windows {
        os_err: os.Error

        os_err = os.remove("playlist_viewer.zip")
        fmt.assertf(os_err == nil, "Could not remove playlist_viewer.zip: %v", os_err)

        clear(&cmd)
        append(&cmd, "7z", "a", "-tzip", "-r", "playlist_viewer.zip", 
               "build.odin", "pv.exe", "SDL3*.dll", "TODO.txt", "README.md", "LICENSE", "lists/NCS.list",
               "src", "bin", "resources", "songs/*NCS*")
        desc.command = cmd[:]
        fmt.printfln("CMD: %v", desc.command)
        state, stdout, stderr, os_err = os.process_exec(desc, context.temp_allocator)
        fmt.assertf(err == nil, "Could not execute process %v: %v", desc.command, err)
        fmt.println(string(stdout))
        fmt.println(string(stderr))
        if state.exit_code != 0 {
          fmt.eprintfln("Error while preparing for release. status: %v", state.exit_code)
        }
      } else {
        // TODO: Release binaries for other oses?
      }
    }
  }
}
