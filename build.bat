@echo off
rem Hot reloading script mostly from: https://github.com/karl-zylinski/odin-raylib-hot-reload-game-template/blob/main/build_hot_reload.bat
:: Copyright (c) 2024 Karl Zylinski
::
:: Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
::
:: The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
::
:: THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

set odinreleaseflags=-no-bounds-check -disable-assert -no-type-assert -o:speed

set PREV_DIR=%cd%
cd /D %~dp0

set APP_RUNNING=false
set OUT_DIR=bin
set PDBS_DIR=%OUT_DIR%\pdbs
set DLL_DIR=%OUT_DIR%\hotreload

set EXE=viewer.exe

if "%~1"=="clean" (
  rem Go to batch file directory (don't want to delete stuff not here)
  del /q *.exe > nul 2>&1
  del /q *.dat > nul 2>&1
  del /q %OUT_DIR%\*
  rem NOTE: pdbs and dlls will get deleted anyway when rerunning
  del /q %PDBS_DIR%\*
  del /q %DLL_DIR%\*
  goto endbuild
)

:: Check if app is running
FOR /F %%x IN ('tasklist /NH /FI "IMAGENAME eq %EXE%"') DO IF %%x == %EXE% set APP_RUNNING=true

if not exist %OUT_DIR% mkdir %OUT_DIR%
if not exist %DLL_DIR% mkdir %DLL_DIR%

:: If app isn't running then:
:: - delete all app_XXX.dll files
:: - delete all PDBs in pdbs subdir
:: - optionally create the pdbs subdir
:: - write 0 into pdbs\pdb_number so app.dll PDBs start counting from zero
::
:: This makes sure we start over "fresh" at PDB number 0 when starting up the
:: game and it also makes sure we don't have so many PDBs laying around.
if %APP_RUNNING% == false (
  del /q /s %DLL_DIR% >nul 2>nul
  del /q %PDBS_DIR%\* >nul 2>nul
  if not exist "%PDBS_DIR%" mkdir %PDBS_DIR%
  echo 0 > %PDBS_DIR%\pdb_number
)

:: Load PDB number from file, increment and store back. For as long as the app
:: is running the pdb_number file won't be reset to 0, so we'll get a PDB of a
:: unique name on each hot reload.
set /p PDB_NUMBER=<%PDBS_DIR%\pdb_number
set /a PDB_NUMBER=%PDB_NUMBER%+1
echo %PDB_NUMBER% > %PDBS_DIR%\pdb_number

odin build src -vet -vet-using-param -vet-style -debug -build-mode:dll -out:%OUT_DIR%\app.dll -pdb-name:%PDBS_DIR%\app_%PDB_NUMBER%.pdb > nul
if %ERRORLEVEL% neq 0 goto endbuilderr
if %APP_RUNNING% == true (
  goto endbuild
)

:: Build app.exe, which starts the program and loads app.dll and does the logic for hot reloading.
odin build src/hot-reload -out:%EXE% -debug -vet -vet-using-param -vet-style -pdb-name:%OUT_DIR%\main_hot_reload.pdb
if %ERRORLEVEL% neq 0 goto endbuilderr

set ODIN_PATH=
for /f "delims=" %%i in ('odin root') do set "ODIN_PATH=%%i"

if not exist "SDL3.dll" (
  if exist "%ODIN_PATH%\vendor\sdl3\SDL3.dll" (
    echo SDL3.dll not found in current directory. Copying from %ODIN_PATH%\vendor\sdl3\SDL3.dll
    copy "%ODIN_PATH%\vendor\sdl3\SDL3.dll" .
    IF %ERRORLEVEL% NEQ 0 goto endbuilderr
  ) else (
    echo Please copy SDL3.dll from <your_odin_compiler>/vendor/sdl3/SDL3.dll to the same directory as app.exe
    goto endbuilderr
  )
)

if not exist "SDL3_ttf.dll" (
  if exist "%ODIN_PATH%\vendor\sdl3\ttf\SDL3_ttf.dll" (
    echo SDL3_ttf not found in current directory. Copying from %ODIN_PATH%\vendor\sdl3\ttf\SDL3_ttf.dll
    copy "%ODIN_PATH%\vendor\sdl3\ttf\SDL3_ttf.dll" .
    IF %ERRORLEVEL% NEQ 0 goto endbuilderr
  ) else (
    echo Please copy SDL3_ttf from <your_odin_compiler>/vendor/sdl3/SDL3_ttf to the same directory as app.exe
    goto endbuilderr
  )
)

if not exist "SDL3_mixer.dll" (
  if exist "%ODIN_PATH%\vendor\sdl3\mixer\SDL3_mixer.dll" (
    echo SDL3_mixer.dll not found in current directory. Copying from %ODIN_PATH%\vendor\sdl3\mixer\SDL3_mixer.dll
    copy "%ODIN_PATH%\vendor\sdl3\mixer\SDL3_mixer.dll" .
    IF %ERRORLEVEL% NEQ 0 goto endbuilderr
  ) else (
    echo Please copy SDL3_mixer.dll from <your_odin_compiler>/vendor/sdl3/SDL3_mixer.dll to the same directory as app.exe
    goto endbuilderr
  )
)

if "%~1"=="run" (
  %EXE%
)

:endbuild
cd %PREV_DIR% > nul
exit /b 0

:endbuilderr
cd %PREV_DIR% > nul
exit /b 1
