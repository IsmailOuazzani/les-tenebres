# Audio system notes

Implements the sound-effects spec for Protest Simulator. **Phase 1 ("core
feedback") is fully implemented** with real, license-verified assets.
Phases 2-4 (interactions, Grabuge/UI, personality/polish) are **not**
implemented yet -- see "Deferred (Phases 2-4)" below. No Paris/city
atmosphere audio was added, per the spec's explicit exclusion.

## Architecture

- `default_bus_layout.tres` -- 6 buses: `Master`, `Crowd`, `Voices`, `SFX`,
  `UI`, `Stingers`, all routed to Master. Registered via
  `project.godot`'s `[audio] buses/default_bus_layout`.
- `scripts/audio_manager.gd` -- `AudioManager` autoload. Data-driven: all
  sound files are registered once in the `SOUNDS` dict; every other system
  calls event-named functions (`play_recruit_feedback()`,
  `play_attack_command()`, etc.) and never touches a file path or audio
  node directly.
  - Pooled `AudioStreamPlayer3D`s for 3D one-shots (`_voice_pool` /
    `_sfx_pool`, sized by `max_simultaneous_voices` /
    `max_simultaneous_world_sfx`), round-robin-acquired so NPC-count growth
    never spawns new nodes per sound.
    - Dedicated single-purpose players for the few things that are
    starts/stops/loops rather than one-shots: megaphone static loop, Send
    Mob charge tone, the attack voice, and the crowd-ambience loop.
  - All tunables from spec section 17 are `@export`ed at the top of the
    script so they're editable from the AudioManager node in the editor.
  - `play_missing(event_key)` is the seam Phase 2-4 work should call into
    for events that don't have an asset/integration yet, instead of silently
    doing nothing (spec section 2's fallback instruction). Not called
    anywhere yet since no Phase 2-4 integration points exist.

## Integration points (who calls AudioManager)

- `addons/fps_controller/Megaphone.gd`: recruit hold start/stop -> static
  loop; Send Mob hold start/update/release -> charge tone + attack voice.
- `scripts/crowd_controller.gd`: `_recruit()` -> individual/collective
  recruit feedback (by position); `_on_send_mob()` -> mob roar scaled by the
  actual committed NPC count (post ring-slice, not the raw percentage).
- `scripts/audio_manager.gd` itself connects to `GameState.disruption_recorded`
  for a basic success cheer (the one Phase 2 hook wired early since the
  signal and a suitable asset already existed -- everything else in Phase
  2-4 is intentionally left unwired).
- Crowd-ambience volume is driven every frame from live
  `CrowdController.get_recruited_count()` + `GameState.grabuge`, independent
  axes per the spec's "10 protesters at 90% Grabuge sounds excited but
  small; 300 at 90% sounds enormous; 300 at 10% sounds tired" examples.

## Asset manifest

All Phase 1 assets are sourced from **Freesound.org, CC0 1.0 (Public Domain
Dedication)** -- verified per-sound via each sound's own license link
(`creativecommons.org/publicdomain/zero/1.0/`), not assumed. CC0 requires no
attribution, but creators are credited below for traceability. Pixabay's
suggested links in the spec are blocked by Cloudflare bot-protection for
non-interactive fetching (download requires a browser + a Turnstile
challenge), so equivalent CC0 Freesound clips were substituted instead --
each chosen to match the spec's description for that slot.

All source files were trimmed (leading/trailing silence), fade-in/out'd
where looped, and loudness-normalized with `ffmpeg` (`loudnorm`/
`silenceremove`). Short one-shots -> `.wav`; loops/longer clips ->
`.ogg` (Vorbis).

| File | Event slot | Source | Creator | License |
|---|---|---|---|---|
| `audio/megaphone/megaphone_click.wav` | Megaphone on/off click | [freesound 556358](https://freesound.org/people/cookies%2Bpolicy/sounds/556358/) | cookies+policy | CC0 |
| `audio/megaphone/megaphone_static_loop.ogg` | Megaphone static hum loop | [freesound 556361](https://freesound.org/people/cookies%2Bpolicy/sounds/556361/) | cookies+policy | CC0 |
| `audio/megaphone/charge_whistle.wav` | Send Mob charge tone | [freesound 538422](https://freesound.org/people/Rosa-Orenes256/sounds/538422/) | Rosa-Orenes256 | CC0 |
| `audio/megaphone/attack_shout_placeholder.wav` | "À L'ATTAQUE !" (placeholder, see below) | [freesound 57204](https://freesound.org/people/Jace/sounds/57204/) | Jace | CC0 |
| `audio/recruitment/recruit_shout.wav` | Individual recruit feedback | same as above (57204) | Jace | CC0 |
| `audio/crowd/cheers/crowd_cheer_burst.wav` | Rapid-recruit collective cheer, disruption success | [freesound 397434](https://freesound.org/people/FoolBoyMedia/sounds/397434/) | FoolBoyMedia | CC0 |
| `audio/crowd/voices/mob_roar_burst.wav` | Mob response "AAAAAAAH!" | [freesound 563011](https://freesound.org/people/florianreichelt/sounds/563011/) | florianreichelt | CC0 |
| `audio/crowd/crowd_ambience_protest.ogg` | Crowd ambience, Layer A | [freesound 210104](https://freesound.org/people/felix.blume/sounds/210104/) | felix.blume | CC0 |

**`attack_shout_placeholder.wav` is NOT a French recording.** It's the
same generic "Men Shouting Hey" clip the spec itself names as a temporary
placeholder, run through a bandpass+compression chain to sound
megaphone-filtered/distorted so the event/ducking pipeline is final even
though the line isn't. Per the spec's own instruction, a real "À
L'ATTAQUE !" voice line needs an actual recording -- swap the file in
`AudioManager.SOUNDS["attack_shout"]` once one exists; no other code
changes needed.

## Deferred (Phases 2-4)

Not implemented this pass -- no assets downloaded, no integration points
added. Flagged here per spec section 2's "clearly identified missing
assets" instruction rather than silently skipped:

- Regrouping voice/whistle (section 3F) -- no regroup command exists yet in
  the mob-selector system to hang it off of.
- Individual French NPC voice lines (section 4, Layer B) and collective
  chants (Layer C) -- need real French recordings per the spec's own
  fallback note; no synthesized/mismatched-language substitute was added.
- Crowd movement layer (section 4, Layer D -- footsteps).
- Big-physics-accident "OOOOOH" and failed-disruption murmur (section 5B/C).
- All contextual object interactions: vehicle horns/alarms/crashes,
  barricade rattling/collapse, statue climbing (section 6).
- Cartoon physics stingers (section 7).
- Police audio (section 8) -- siren, footsteps, combat impacts.
- Grabuge gain/fanfare/low-warning/collapse sounds (section 9A, B, D, E) --
  `GameState.grabuge_changed` exists and is a clean hook for this later.
- Game over sting (section 10) -- `GameState.game_over` exists and is a
  clean hook for this later.
- Snap feed notification sounds (section 11) and target-acquisition UI
  sounds (section 12) -- need Kenney UI Audio assets, not downloaded.
- Failure/comedy stingers (section 13).
- The debug/testing panel (section 18).

`AudioManager.play_missing(event_key)` is ready for all of the above to log
once per key instead of doing nothing silently, once each gets wired up.

## Known rough edges

- `charge_whistle.wav` is a single short blast (not a sustained tone), so
  the charge-up rise is simulated by re-triggering it on a shortening
  interval + ramping `pitch_scale`/`volume_db`, rather than a continuously
  bending note. Revisit if a sustained whistle/siren sample becomes
  available.
- `mob_roar_burst.wav` layering (1/3/5/8 copies by crowd-size threshold) is
  one source clip at slight pitch/offset variance, not genuinely distinct
  recordings -- real variety would need more source clips.
