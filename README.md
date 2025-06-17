## Playlist viewer

A program to show playlists and also to play them :)

The reason why I started making this is so I can actually store a list of songs in a place where youtube or spotify can't remove songs from, locally. I know removing songs is not necessarily because these places want to remove them, sometimes it's the creators themselves. However, I believe youtube/spotify should notify you of such changes in your playlists, and definitely not what they do: "Unavailable videos are hidden"

As a side note, I deleted most of the work done in this project by accident so a lot of it is going to be redone in the first commits and the program used to be more complete. Most importantly, *this isnt the final name for this T-T.*

WARNING: This software is unfinished and subject to change, until any releases are made in github, it will most likely not be stable

For planned updates/fixes, see TODO.txt

## Usage

Right now, the program will keep a trace of various events in a file called 'trace.spall'. I will soon have this be optional, however, last time I checked, it made a 500MB file from a 9h trace.

```console
./viewer
```

### Dependencies
 - odin programming language: https://odin-lang.org/
 - raylib (vendored in odin): https://www.raylib.com/
 - clay layout library (vendored in this project): https://github.com/nicbarker/clay
 - spall profiler (in odin core library): https://github.com/colrdavidson/spall-web

### Building
Install odinlang if you don't have it: https://odin-lang.org/docs/install/

windows:
```console
build.bat [run|clean]
```

linux/macos: (macos untested!)
```console
./BUILD.sh [run]
```