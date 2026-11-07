# Rotating Soundtrack

Source links are in `Sound_links` at the repo root (pulled from `origin/main`,
added by eloisebaril): 4 YouTube URLs labeled fanfare / caca / manif background
/ orchestre.

## Why the audio isn't committed

This repo is **public** on GitHub. Downloading full tracks from YouTube and
committing them would be a real DMCA/takedown risk, separate from the
"license doesn't matter" approach we've taken with free 3D asset packs.
So: the audio is downloaded and used locally, but `assets/audio/music/` is
gitignored — it never reaches the public repo.

## How to (re)download the tracks locally

```bash
python3 -m venv .venv-ytdlp
.venv-ytdlp/bin/pip install yt-dlp
source .venv-ytdlp/bin/activate

yt-dlp -x --audio-format mp3 --audio-quality 0 \
  -o "assets/audio/music/<name>.%(ext)s" \
  "<youtube-url>"
```

Repeat per line in `Sound_links`. Both `.venv-ytdlp/` and
`assets/audio/music/` are gitignored.

**Format note:** used `mp3` (via ffmpeg's `libmp3lame`), not `opus` or
`vorbis` — Godot 4.7 has no built-in loader for raw `.opus`, and this
machine's ffmpeg build doesn't expose a working vorbis encoder for yt-dlp
to call. MP3 and OGG Vorbis are Godot's natively-supported formats; MP3 is
what actually worked here.

**One-time import quirk:** after dropping new files into
`assets/audio/music/`, Godot needs one import pass before `load()` can see
them (same gitignored-asset quirk noted elsewhere in `agents/`):

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --editor --quit-after 10
```

This generates `.mp3.import` files next to the audio (also gitignored).
Without this, `load()` fails with "No loader found for resource".

## Playback: `scripts/music_player.gd`

Registered as the `MusicPlayer` autoload in `project.godot`. On `_ready()`
it scans `res://assets/audio/music/` for `.opus`/`.ogg`/`.mp3`/`.wav` files,
shuffles them into a playlist, and plays them back-to-back via a single
`AudioStreamPlayer`, reshuffling and looping once the playlist runs out —
i.e. a rotating soundtrack, not a single looping track.

If the folder is empty or missing (e.g. a fresh clone that hasn't run the
yt-dlp step), it just logs a warning and stays silent — no crash, no
missing-file errors.

## Follow-ups

- If any of these 4 tracks are meant to ship with the game eventually,
  they need to be replaced with properly licensed/royalty-free music before
  any public release — these are just YouTube rips for local prototyping.
- No volume/ducking/mixing logic yet (e.g. lowering music during the
  megaphone's "RECRUITING..."/"À L'ATTAQUE !" stingers) — straightforward
  to add later via `MusicPlayer.player.bus` or a dedicated audio bus.
