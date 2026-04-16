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
  PDBS_ENV_VAR :: "VIEWER_PDB_NUMBER"
  PDBS_DIR :: OUT_DIRECTORY + "/pdbs"
  EXECUTABLE :: "viewer.exe" 
} else {
  EXECUTABLE :: "viewer"
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
  for arg in os.args[1:] {
    switch arg {
      case "clean":   shouldClean = true
      case "debug":   debugMode = true
      case "release": debugMode = false
      case "run":     shouldRun = true
      case "norun":   shouldRun = false
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

  absExePath, alloc_err := os.get_absolute_path(EXECUTABLE, context.allocator)
  fmt.assertf(alloc_err == nil, "Could not get abs path of " + EXECUTABLE + ": %v", alloc_err)
  isRunning := IsExecutableRunning(absExePath)

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
    fmt.assertf(ok, "Could not parse int from " + PDBS_ENV_VAR + " env")
    pdb_num += 1
    pdb_num_str = strconv.write_int(buf[:], i64(pdb_num), base)
    err := os.set_env(PDBS_ENV_VAR, pdb_num_str)
    fmt.assertf(err == nil, "Could not set " + PDBS_ENV_VAR + " env: %v", err)
  }

  pdb_name := fmt.tprintf("-pdb-name:" + PDBS_DIR + "\\app_%v.pdb", pdb_num)

  cmd: [dynamic]string
  append(&cmd, "odin", "build", "src", "-vet", "-vet-using-param", "-vet-style", 
         "-build-mode:dll", pdb_name, "-out:" + OUT_DIRECTORY + "/app" + DLL_EXT)
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
           "-vet", "-vet-using-param", "-vet-style",
           "-pdb-name:" + OUT_DIRECTORY + "\\main_hot_reload.pdb")
    if debugMode {
      append(&cmd, "-debug")
    } else {
      append(&cmd, ..RELEASE_FLAGS)
    }
    desc.command = cmd[:]
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
    state, stdout, stderr, err = os.process_exec(desc, context.temp_allocator)
    fmt.assertf(err == nil, "Could not execute process %v: %v", desc.command, err)
    if state.exit_code != 0 {
      fmt.eprintf(string(stderr))
      fmt.eprintfln("Could not get odin root. Compiler exit code: %v", state.exit_code)
      os.exit(1)
    }

    paths, err := strings.split_lines(string(stdout), context.temp_allocator)
    fmt.assertf(err == nil, "Could not get memory for odin root paths: %v", err)

    if !os.exists("SDL3" + DLL_EXT) {
      sdl_dll_path := fmt.tprintf("%s/vendor/sdl3/SDL3" + DLL_EXT, paths[0])
      if os.exists(sdl_dll_path) {
        fmt.eprintfln("SDL3" + DLL_EXT + " not found in current directory. Copying from %s", sdl_dll_path)
        os_err := os.copy_file(".", sdl_dll_path)
        fmt.assertf(os_err == nil, "Could not copy file: %v", os_err)
      } else {
        fmt.eprintfln("Please copy SDL3" + DLL_EXT + " from <your_odin_compiler>/vendor/sdl3/SDL3" + DLL_EXT + " to the same directory as " + EXECUTABLE)
      }
    }

    if !os.exists("SDL3_ttf" + DLL_EXT) {
      sdl_dll_path := fmt.tprintf("%s/vendor/sdl3/ttf/SDL3_ttf" + DLL_EXT, paths[0])
      if os.exists(sdl_dll_path) {
        fmt.eprintfln("SDL3_ttf" + DLL_EXT + " not found in current directory. Copying from %s", sdl_dll_path)
        os_err := os.copy_file(".", sdl_dll_path)
        fmt.assertf(os_err == nil, "Could not copy file: %v", os_err)
      } else {
        fmt.eprintfln("Please copy SDL3_ttf" + DLL_EXT + " from <your_odin_compiler>/vendor/sdl3/ttf/SDL3_ttf" + DLL_EXT + " to the same directory as " + EXECUTABLE)
      }
    }

    if !os.exists("SDL3_mixer" + DLL_EXT) {
      sdl_dll_path := fmt.tprintf("%s/vendor/sdl3/ttf/SDL3_mixer" + DLL_EXT, paths[0])
      if os.exists(sdl_dll_path) {
        fmt.eprintfln("SDL3_mixer" + DLL_EXT + " not found in current directory. Copying from %s", sdl_dll_path)
        os_err := os.copy_file(".", sdl_dll_path)
        fmt.assertf(os_err == nil, "Could not copy file: %v", os_err)
      } else {
        fmt.eprintfln("Please copy SDL3_mixer" + DLL_EXT + " from <your_odin_compiler>/vendor/sdl3/ttf/SDL3_mixer" + DLL_EXT + " to the same directory as " + EXECUTABLE)
      }
    }
  
    if shouldRun {
      os_err: os.Error

      clear(&cmd)
      append(&cmd, EXECUTABLE)
      desc.command = cmd[:]
      state, stdout, stderr, os_err = os.process_exec(desc, context.temp_allocator)
      fmt.assertf(err == nil, "Could not execute process %v: %v", desc.command, err)
      fmt.println(string(stdout))
      fmt.println(string(stderr))
      if state.exit_code != 0 {
        fmt.eprintfln("Error while executing " + EXECUTABLE + " status: %v", state.exit_code)
      }
    }
  }
}
