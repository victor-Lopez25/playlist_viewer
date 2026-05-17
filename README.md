## Playlist Viewer

A program to show playlists and also to play them :)

The reason why I started making this is so I can actually store a list of songs in a place where youtube or spotify can't remove songs from, locally. I know removing songs is not necessarily because these places want to remove them, sometimes it's the creators themselves. However, I believe youtube/spotify should notify you of such changes in your playlists, and definitely not what they do: "Unavailable videos are hidden"

**WARNING**: This software is unfinished and subject to change

For planned updates/fixes, see TODO.txt

For prebuilt binaries (windows only for now), see [releases](https://github.com/victor-Lopez25/playlist_viewer/releases/latest)

## Usage

```console
./pv
```

### Current keyboard actions
| Key | Action |
| :--- | :--- |
| **Arrow Left** | rewind 5 seconds |
| **Arrow Right** | advance 5 seconds |
| **Arrow Up** | increase volume by 0.5% |
| **Arrow Down** | decrease volume by 0.5% |
| **Key J** | rewind 10 seconds |
| **Key L** | advance 10 seconds |
| **End** | skip to next song in the list |
| **Keypad 1** | skip to next song in the list |
| **Home** | rewind to start of song or previous song (if in the first 12 seconds) |
| **Keypad 7** | rewind to start of song or previous song (if in the first 12 seconds) |
| **Key R** | randomize song order |
| **Key A** | enable looping on current song |
| **Ctrl + O** | open music files directory (will add the music files from the directory to the list) |

When built in debug mode, the program will keep a trace of various events in a file called 'trace.spall'. A 9h trace is about 500MB. **This is disabled in release mode**

## Building
Install odinlang if you don't have it: https://odin-lang.org/docs/install/

If on linux/macos you might need to install sdl3, sdl3_ttf, sdl3_image and sdl3_mixer.

If you want to build from source:
 - SDL3: https://github.com/libsdl-org/SDL/blob/main/INSTALL.md
 - SDL3_ttf: https://github.com/libsdl-org/SDL_ttf/blob/main/INSTALL.md
 - SDL3_image: https://github.com/libsdl-org/SDL_image/blob/main/INSTALL.md
 - SDL3_mixer: https://github.com/libsdl-org/SDL_mixer/blob/main/INSTALL.md

If you want official releases:
 - SDL3: https://github.com/libsdl-org/SDL/releases/latest
 - SDL3_ttf: https://github.com/libsdl-org/SDL_ttf/releases/latest
 - SDL3_ttf: https://github.com/libsdl-org/SDL_image/releases/latest
 - SDL3_mixer: https://github.com/libsdl-org/SDL_mixer/releases/latest

windows/linux/macos: **From this directory**, run
```console
odin run . -- [debug|release] [run] [clean]
```
(macos untested!)

### Dependencies
 - odin programming language: https://odin-lang.org/
 - clay layout library (vendored in this project): https://github.com/nicbarker/clay
 - spall profiler (in odin core library): https://github.com/colrdavidson/spall-web
 - sdl3 (vendored in odin): https://wiki.libsdl.org/SDL3/FrontPage
 - sdl3_ttf (vendored in odin): https://wiki.libsdl.org/SDL3_ttf/FrontPage
 - sdl3_image (vendored in odin): https://wiki.libsdl.org/SDL3_image/FrontPage
 - sdl3_mixer (vendored in odin): https://wiki.libsdl.org/SDL3_mixer/FrontPage
