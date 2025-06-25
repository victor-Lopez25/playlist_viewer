## Playlist viewer

A program to show playlists and also to play them :)

The reason why I started making this is so I can actually store a list of songs in a place where youtube or spotify can't remove songs from, locally. I know removing songs is not necessarily because these places want to remove them, sometimes it's the creators themselves. However, I believe youtube/spotify should notify you of such changes in your playlists, and definitely not what they do: "Unavailable videos are hidden"

As a side note, I deleted most of the work done in this project by accident so a lot of it is going to be redone in the first commits and the program used to be more complete

WARNING: This software is unfinished and subject to change, until any releases are made in github, it will most likely not be stable

For planned updates/fixes, see TODO.txt

## Usage

Right now, the program will keep a trace of various events in a file called 'trace.spall'. I will soon have this be optional, however, last time I checked, it made a 500MB file from a 9h trace.

```console
./viewer
```

### Dependencies
 - odin programming language: https://odin-lang.org/
 - clay layout library (vendored in this project): https://github.com/nicbarker/clay
 - spall profiler (in odin core library): https://github.com/colrdavidson/spall-web
 - sdl3 (vendored in odin): https://wiki.libsdl.org/SDL3/FrontPage
 - sdl3_ttf (vendored in odin): https://wiki.libsdl.org/SDL3_ttf/FrontPage
 - sdl3_mixer (vendored in this project): https://wiki.libsdl.org/SDL3_mixer/FrontPage

### Building
Install odinlang if you don't have it: https://odin-lang.org/docs/install/

If on linux/macos you might need to install sdl3, sdl3_ttf and sdl3_mixer

windows:
```console
build.bat [run|clean]
```

linux/macos: (macos untested!)
```console
./BUILD.sh [run]
```
