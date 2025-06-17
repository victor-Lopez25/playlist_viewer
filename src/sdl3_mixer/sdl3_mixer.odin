package sdl3_mixer

/* sdl3 mixer bindings, in case it takes very long to get official bindings for odin in vendor */

import "core:c"
import SDL "vendor:sdl3"

when ODIN_OS == .Windows {
  foreign import lib "SDL3_mixer.lib"
} else {
  foreign import lib "system:SDL3_mixer"
}

MAJOR_VERSION :: 3
MINOR_VERSION :: 0
MICRO_VERSION :: 0

InitFlag :: enum c.int {
  FLAC   = 0,
  MOD    = 1,
  MP3    = 3,
  OGG    = 4,
  MID    = 5,
  OPUS   = 6,
}

InitFlags :: distinct bit_set[InitFlag; c.int]

INIT_FLAC :: InitFlags{.FLAC}
INIT_MOD  :: InitFlags{.MOD}
INIT_MP3  :: InitFlags{.MP3}
INIT_OGG  :: InitFlags{.OGG}
INIT_MID  :: InitFlags{.MID}
INIT_OPUS :: InitFlags{.OPUS}

Chunk :: struct {
  allocated: c.int,
  abuf:      [^]u8,
  alen:      u32,
  volume:    u8,  /* Per-sample volume, 0-128 */
}

Fading :: enum c.int {
  NO_FADING,
  FADING_OUT,
  FADING_IN,
}

NO_FADING  :: Fading.NO_FADING
FADING_OUT :: Fading.FADING_OUT
FADING_IN  :: Fading.FADING_IN

MusicType :: enum c.int {
  NONE,
  WAV,
  MOD,
  MID,
  OGG,
  MP3,
  FLAC,
  OPUS,
  WAVPACK,
  GME,
}

NONE    :: MusicType.NONE
WAV     :: MusicType.WAV
MOD     :: MusicType.MOD
MID     :: MusicType.MID
OGG     :: MusicType.OGG
MP3     :: MusicType.MP3
FLAC    :: MusicType.FLAC
OPUS    :: MusicType.OPUS
WAVPACK :: MusicType.WAVPACK
GME     :: MusicType.GME

CHANNELS          :: 8
CHANNEL_POST      :: -2 // NOTE: Not sure if this is needed here
EFFECTSMAXSPEED   :: "MIX_EFFECTSMAXSPEED" // NOTE: Not sure if this is needed here

DEFAULT_FREQUENCY :: 44100
DEFAULT_FORMAT    :: SDL.AudioFormat.S16
DEFAULT_CHANNELS  :: 2
MAX_VOLUME        :: 128

Music :: struct {}

/* We'll use SDL for reporting errors */
// NOTE: Neither Mix_SetError nor Mix_ClearError exist in the sdl3_mixer wiki,
// these were in the odin bindings for sdl2/mixer
SetError   :: SDL.SetError
GetError   :: SDL.GetError
ClearError :: SDL.ClearError

EffectFunc_t :: proc "c"(chan: c.int, stream: rawptr, len: c.int, udata: rawptr)
EffectDone_t :: proc "c"(chan: c.int, udata: rawptr)

MixFunc :: proc "c"(udata: rawptr, stream: ^u8, len: int)

@(default_calling_convention="c", link_prefix="Mix_")
foreign lib {
  Version :: proc() -> c.int ---

  Init :: proc(flags: InitFlags) -> InitFlags ---
  Quit :: proc() ---

  OpenAudio              :: proc(devid: SDL.AudioDeviceID, spec: ^SDL.AudioSpec) -> bool ---
  CloseAudio             :: proc() ---
  AllocateChannels       :: proc(numchans: c.int) -> c.int ---
  QuerySpec              :: proc(frequency: ^c.int, format: ^SDL.AudioFormat, channels: ^c.int) -> bool ---
  EachSoundFont          :: proc(function: proc "c" (cstring, rawptr), data: rawptr) -> bool ---
  LoadWAV                :: proc(file: cstring) -> ^Chunk ---
  LoadWAV_IO             :: proc(src: ^SDL.IOStream, closeio: bool) -> ^Chunk ---
  LoadMUS                :: proc(file: cstring) -> ^Music ---
  LoadMUS_IO             :: proc(src: ^SDL.IOStream, closeio: bool) -> ^Chunk ---
  LoadMUSType_IO         :: proc(src: ^SDL.IOStream, type: MusicType, closeio: bool) -> ^Music ---
  QuickLoad_WAV          :: proc(mem: [^]u8) -> ^Chunk ---
  QuickLoad_RAW          :: proc(mem: [^]u8, len: u32) -> ^Chunk ---
  FreeChunk              :: proc(chunk: ^Chunk) ---
  FreeMusic              :: proc(music: ^Music) ---
  GetChunk               :: proc(channel: c.int) -> ^Chunk ---
  GetNumChunkDecoders    :: proc() -> c.int ---
  GetChunkDecoder        :: proc(index: c.int) -> cstring ---
  HasChunkDecoder        :: proc(name: cstring) -> bool ---
  GetNumMusicDecoders    :: proc() -> c.int ---
  GetMusicDecoder        :: proc(index: c.int) -> cstring ---
  HasMusicDecoder        :: proc(name: cstring) -> bool ---
  GetMusicType           :: proc(music: ^Music) -> MusicType ---
  GetMusicTitle          :: proc(music: ^Music) -> cstring ---
  GetMusicTitleTag       :: proc(music: ^Music) -> cstring ---
  GetMusicArtistTag      :: proc(music: ^Music) -> cstring ---
  GetMusicAlbumTag       :: proc(music: ^Music) -> cstring ---
  GetMusicCopyrightTag   :: proc(music: ^Music) -> cstring ---
  GetMusicLoopEndTime    :: proc(music: ^Music) -> f64 ---
  GetMusicLoopLengthTime :: proc(music: ^Music) -> f64 ---
  GetMusicLoopStartTime  :: proc(music: ^Music) -> f64 ---
  GetMusicPosition       :: proc(music: ^Music) -> f64 ---
  MusicDuration          :: proc(music: ^Music) -> f64 ---
  GetNumTracks           :: proc(music: ^Music) -> c.int ---
  GetSoundFonts          :: proc() -> cstring ---
  GetTimidityCfg         :: proc() -> cstring ---

  MasterVolume           :: proc(volume: c.int) -> c.int ---
  Volume                 :: proc(channel, volume: c.int) -> c.int ---
  VolumeChunk            :: proc(chunk: ^Chunk, volume: c.int) -> c.int ---
  VolumeMusic            :: proc(volume: c.int) -> c.int ---

  GroupAvailable         :: proc(tag: c.int) -> c.int ---
  GroupChannel           :: proc(which, tag: c.int) -> bool ---
  GroupChannels          :: proc(from, to, tag: c.int) -> bool ---
  GroupCount             :: proc(tag: c.int) -> bool ---
  GroupNewer             :: proc(tag: c.int) -> c.int ---
  GroupOldest            :: proc(tag: c.int) -> c.int ---
  ReserveChannels        :: proc(num: c.int) -> c.int ---

  Pause                  :: proc(channel: c.int) ---
  PauseAudio             :: proc(pause_on: c.int) ---
  Paused                 :: proc(channel: c.int) -> c.int ---
  PausedMusic            :: proc() -> bool ---
  PauseGroup             :: proc(tag: c.int) ---
  PauseMusic             :: proc() ---
  Resume                 :: proc(channel: c.int) ---
  ResumeGroup            :: proc(tag: c.int) ---
  ResumeMusic            :: proc() ---
  PlayChannel            :: proc(channel: c.int, chunk: ^Chunk, loops: c.int) -> c.int ---
  PlayChannelTimed       :: proc(channel: c.int, chunk: ^Chunk, loops, ticks: c.int) -> c.int ---
  Playing                :: proc(channel: c.int) -> c.int ---
  PlayingMusic           :: proc() -> bool ---
  PlayMusic              :: proc(music: ^Music, loops: c.int) -> bool ---
  RewindMusic            :: proc() ---
  StartTrack             :: proc(music: ^Music, track: c.int) -> bool ---

  SetDistance            :: proc(channel: c.int, distance: u8) -> bool ---
  SetMusicPosition       :: proc(position: f64) -> bool ---
  SetPanning             :: proc(channel: c.int, left, right: u8) -> bool ---
  SetPosition            :: proc(channel: c.int, angle: i16, distance: u8) -> bool ---
  SetReverseStereo       :: proc(channel, flip: c.int) -> bool ---
  SetSoundFonts          :: proc(paths: cstring) -> bool ---
  SetTimidityCfg         :: proc(path: cstring) -> bool ---

  HaltChannel            :: proc(channel: c.int) ---
  HaltGroup              :: proc(tag: c.int) ---
  HaltMusic              :: proc() ---
  ModMusicJumpToOrder    :: proc(order: c.int) -> bool ---

  RegisterEffect         :: proc(chan: c.int, f: EffectFunc_t, d: EffectDone_t, arg: rawptr) -> bool ---
  UnregisterAllEffects   :: proc(channel: c.int) -> bool ---
  UnregisterEffect       :: proc(channel: c.int, f: EffectFunc_t) -> bool ---
  ExpireChannel          :: proc(channel, ticks: c.int) -> c.int ---
  FadeInChannel          :: proc(channel: c.int, chunk: ^Chunk, loops, ms: c.int) -> c.int ---
  FadeInChannelTimed     :: proc(channel: c.int, chunk: ^Chunk, loops, ms, ticks: c.int) -> c.int ---
  FadeInMusic            :: proc(music: ^Music, loops, ms: c.int) -> bool ---
  FadeInMusicPos         :: proc(music: ^Music, loops, ms: c.int, position: f64) -> bool ---
  FadeOutChannel         :: proc(which, ms: c.int) -> c.int ---
  FadeOutGroup           :: proc(tag, ms: c.int) -> c.int ---
  FadeOutMusic           :: proc(ms: c.int) -> bool ---
  FadingChannel          :: proc(which: c.int) -> Fading ---
  FadingMusic            :: proc() -> Fading ---

  SetPostMix             :: proc(mix_func: MixFunc, arg: rawptr) ---
  HookMusic              :: proc(mix_func: MixFunc, arg: rawptr) ---
  HookMusicFinished      :: proc(music_finished: proc "c" ()) ---
  GetMusicHookData       :: proc() -> rawptr ---

  ChannelFinished        :: proc(channel_finished: proc "c" (channel: c.int)) ---
}
