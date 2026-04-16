## Playlist viewer

A program to show playlists and also to play them :)

The reason why I started making this is so I can actually store a list of songs in a place where youtube or spotify can't remove songs from, locally. I know removing songs is not necessarily because these places want to remove them, sometimes it's the creators themselves. However, I believe youtube/spotify should notify you of such changes in your playlists, and definitely not what they do: "Unavailable videos are hidden"

As a side note, I deleted most of the work done in this project by accident so a lot of it is going to be redone in the first commits and the program used to be more complete

**WARNING**: This software is unfinished and subject to change

For planned updates/fixes, see TODO.txt

## Usage

```console
./viewer
```

When built in debug mode, the program will keep a trace of various events in a file called 'trace.spall'. A 9h trace is about 500MB. **This is disabled in release mode**

### Dependencies
 - odin programming language: https://odin-lang.org/
 - clay layout library (vendored in this project): https://github.com/nicbarker/clay
 - spall profiler (in odin core library): https://github.com/colrdavidson/spall-web
 - sdl3 (vendored in odin): https://wiki.libsdl.org/SDL3/FrontPage
 - sdl3_ttf (vendored in odin): https://wiki.libsdl.org/SDL3_ttf/FrontPage
 - sdl3_mixer (vendored in odin): https://wiki.libsdl.org/SDL3_mixer/FrontPage

### Building
Install odinlang if you don't have it: https://odin-lang.org/docs/install/

If on linux/macos you might need to install sdl3, sdl3_ttf and sdl3_mixer.

If you want to build from source:
 - SDL3: https://github.com/libsdl-org/SDL/blob/main/INSTALL.md
 - SDL3_ttf: https://github.com/libsdl-org/SDL_ttf/blob/main/INSTALL.md
 - SDL3_mixer: https://github.com/libsdl-org/SDL_mixer/blob/main/INSTALL.md

If you want official releases:
 - SDL3: https://github.com/libsdl-org/SDL/releases/latest
 - SDL3_ttf: https://github.com/libsdl-org/SDL_ttf/releases/latest
 - SDL3_mixer: https://github.com/libsdl-org/SDL_mixer/releases/latest

windows/linux/macos: (macos untested!)
```console
odin run . -- [debug|release] [run] [clean]
```
