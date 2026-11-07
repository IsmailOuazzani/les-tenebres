# Megaphone prop + click-command signals

**Superseded in part — see `agents/crowd-swarm-notes.md` for the current
contract.** Recruit is now hold-based (an influence cone) instead of a
single-click `recruit_triggered` signal, and the right-click hold-vs-click
distinction ("Not implemented" note at the bottom of this file) has since
been implemented as `attack_command_triggered`/`regroup_triggered`. The
rest of this file (raycast target logic, raise/shake animation, click
feedback) is still accurate.


Implements the player-facing half of "Core Controls" (left click = Recruit,
right click = À L'ATTAQUE!) from `vision.md`. **No NPC/crowd logic lives
here** — that's a separate, parallel workstream. This is the integration
contract for that future system.

## Files

- `addons/fps_controller/Megaphone.gd` — all behavior (`class_name Megaphone`).
- `addons/fps_controller/Megaphone.tscn` — the viewmodel scene (primitive
  cone/cylinder mesh, no external model — poly.pizza's "Megaphone" by
  4444ESOUSA was considered but a hand-built primitive was faster/more
  reliable to get working headless; swap the meshes under `VisualRoot` later
  if a real model is imported, the script doesn't care what's under there).
- Wired in as `addons/fps_controller/Player.tscn` → `Head/Camera/Megaphone`
  (child of the first-person camera, so it moves with the view).
- New input actions in `project.godot`: `recruit` (left mouse button) and
  `attack_command` (right mouse button). Did not touch any existing FPS
  controller bindings.

## Integration contract (for the crowd/NPC system)

`Megaphone` (autodiscoverable at `Player/Head/Camera/Megaphone` in the
scene tree, or via `get_viewport().get_camera_3d().get_node("Megaphone")`
from anywhere with camera access) emits:

```gdscript
signal recruit_triggered(target_position: Vector3)
signal attack_command_triggered(target_position: Vector3)
```

- `recruit_triggered` fires on left-click ("Recruit"). Connect to this to
  spawn/convert a recruited NPC at or near `target_position`.
- `attack_command_triggered` fires on right-click ("À L'ATTAQUE!"). Connect
  to this to send the current mob toward `target_position`.
- `target_position` is always a valid world-space `Vector3`: it's the point
  a camera-forward raycast (range `ray_range`, default 50m, exported on the
  node) hit, masked to physics layer 1 ("Objects" per
  `project.godot`'s `[layer_names]`, so the player's own collision on
  layer 2 never self-intersects). If the ray hits nothing, it falls back to
  a point `ray_range` meters out along the look direction — so it is never
  null and callers never need to null-check.
- Both signals fire once per click (`event.pressed` edge via
  `is_action_pressed`), not per-frame.

Example hookup from a future crowd manager:

```gdscript
@onready var megaphone: Megaphone = $"../Player/Head/Camera/Megaphone"

func _ready() -> void:
    megaphone.recruit_triggered.connect(_on_recruit)
    megaphone.attack_command_triggered.connect(_on_attack_command)

func _on_recruit(target_position: Vector3) -> void:
    # spawn/convert nearby civilians into recruits, biased toward target_position
    pass

func _on_attack_command(target_position: Vector3) -> void:
    # send current mob toward target_position
    pass
```

**Not implemented (out of scope for this task, left for the vision's "Hold
Right Click = Rally" and the crowd system):** holding right-click vs. a
single click is not distinguished yet — only the press edge is handled.
Rally-on-hold would be a natural follow-up: connect to the same
`attack_command` action's `is_action_pressed`/`is_action_just_released` in
`Megaphone.gd` (or a new signal) once the crowd system needs it.

## What the script does on each click (player-facing only)

Both actions:
1. Raycast from the active camera (see above) to find `target_position`.
2. Play a raise+shake tween on `VisualRoot` (the prop's visual mesh root;
   purely cosmetic, no gameplay state).
3. Emit the signal.

Recruit-specific: restarts a small one-shot `CPUParticles3D` burst
(`VisualRoot/Burst`) at the horn's mouth, and shows a short green
"RECRUITING..." label (`UILayer/FeedbackLabel`).

Attack-specific: flashes a brief red overlay (`UILayer/Flash`, a
full-screen `ColorRect` on a `CanvasLayer`) and drops a small red sphere
marker at `target_position` that scales to zero and frees itself after
~0.9s — a placeholder for a future decal/VFX, not a gameplay object. Also
shows a red "À L'ATTAQUE !" label.

All of this (particles/flash/marker/label) is cosmetic stub feedback per
the task spec — the crowd system doesn't need to touch any of it, and can
ignore it entirely if/when it adds its own feedback.

## Verification

Ran `/Applications/Godot.app/Contents/MacOS/Godot --path . --headless --quit-after 1`
(after a one-time `--headless --import` to build the global class-name
cache, since `.godot/` didn't exist yet in this worktree) — no parse
errors, no warnings (checked with `--verbose` too). The `Head/Camera`
child-parenting trick (adding a `Megaphone` node under a path that reaches
inside the `Head.tscn` sub-instance, written directly in `Player.tscn`'s
text format rather than via the editor's "Editable Children" toggle) loads
and runs cleanly.

**Not verified:** actual visual positioning/scale of the prop, the
animation feel, or particle/flash appearance — there's no display in this
environment. The held-prop transform (`VisualRoot`'s position/rotation in
`Megaphone.tscn`, bottom-right-ish of the camera) is a best guess and will
likely need hand-tuning in the editor after a playtest.

## Update: swapped primitive for the VOiD1 real model

Replaced the hand-built cone/cylinder under `VisualRoot` with the real
**VOiD1 Free Megaphones Collection** (https://void1gaming.itch.io/free-3d-megaphones-collection,
"name your own price," downloaded via the "No thanks, just take me to the
downloads" link — no login/payment required; license PDF kept at
`assets/megaphone/LICENSE.pdf`).

### Where it lives

- `assets/megaphone/MegaphoneCollection.fbx` — the pack's single FBX,
  containing **four** megaphone variants as sibling root nodes: `Air Horn_low`,
  `Cheerleader's Megaphone_low`, `Plastic Megaphone_low`, `Electronic
  Megaphone_low` (named per the pack's "Air Horn / Cheerleader's / Plastic /
  Electric" variants).
- `assets/megaphone/Textures/` — the "PBR MetalicRoughness" texture set
  (BaseColor/Normal/Metallic/Roughness/Height, 4096px), shared by all four
  variants (only one texture set ships, labeled "Var 1"). Folder name is
  capitalized `Textures` deliberately — the FBX's internal material
  references use that exact casing, and naming it lowercase caused
  "case mismatch" import warnings on macOS's case-insensitive filesystem.
- Did **not** convert to GLB (unlike the Kenney packs) — no Blender install
  in this environment to do the FBX→glTF bridge, and Godot 4.7's native FBX
  importer loaded it directly with zero errors, so there was no need.

### Which variant, and why

Picked **`Plastic Megaphone_low`** — the classic handheld cone megaphone,
the best fit for a protest-leader prop (vs. the air horn, cheerleader's
megaphone, or electronic bullhorn). The other three are hidden
(`visible = false`) via property overrides rather than deleted, in case a
future pass wants to swap variants — see `Megaphone.tscn`'s
`VisualRoot/MegaphoneModel` subtree.

### Import gotcha: all 4 variants ship pre-arranged in one showroom layout

Each variant is a sibling under one root node, individually positioned 1-2
world units apart along the same axis (an artist's side-by-side display
arrangement baked into the FBX) — picking just one and leaving its own
`position` untouched would render it floating meters away from the other
props. Fixed with a property override zeroing `Plastic Megaphone_low`'s
`position` back to `Vector3(0,0,0)` in `Megaphone.tscn`. If a future pass
swaps to a different variant, remember to zero its position too.

### Scale

The FBX bakes a real-world scale into each mesh's own transform (no extra
scale needed to get real units) — confirmed via a throwaway headless
inspection script (not checked in) that walked the instantiated scene and
read `MeshInstance3D.get_aabb()` + `transform`: `Plastic Megaphone_low`
comes out to roughly a 0.71-0.76m bounding cube in world units once its
baked transform is applied. That's larger and more cube-shaped than a real
megaphone's silhouette (expected to be longer than it is wide) — my
hypothesis is the model's "showroom" pose has the horn angled up and the
handle hanging down, which inflates an axis-aligned bounding box into a
near-cube even though the mesh itself is elongated. **Unconfirmed — I have
no display access in this environment** (see below).

### Held-prop transform (best guess, unverified)

```
VisualRoot: position = (0.3, -0.35, -0.6), rotation_degrees = (10, -15, -5)
VisualRoot/MegaphoneModel: scale = (0.5, 0.5, 0.5)   # brings the ~0.75m bbox down to ~0.38m
MuzzlePoint / Burst: position = (0, 0.02, -0.22)  # relative to VisualRoot
```

These numbers are carried over in spirit from the old primitive's
bottom-right-of-camera placement, scaled up for the new mesh's larger
bounding box, **not visually confirmed**. I do not know the model's
authored "forward" axis (which way the horn's mouth actually faces at
rotation `(0,0,0)`), so the rotation and the muzzle point's position are
both educated guesses, not measurements. Also did not re-tune the
raise/shake tween's offsets in `Megaphone.gd` (`_play_raise_shake`) — left
the original deltas (`+0.05` on Y, `-0.04` on Z, ~8-9° rotation wobble)
since the new prop ends up roughly the old prop's size after scaling, but
whether the shake animation still *reads* well with the new, chunkier
silhouette is unverified.

### Verification done / not done

Ran `--headless --editor --quit-after 25` once (to force Godot to import the
new FBX + textures and generate `.import` sidecars — same trick as the
Kenney map pass) followed by `--headless --quit-after 3` on the full game:
**zero errors, zero warnings** other than the harmless leaked-RID/ObjectDB
noise on abrupt headless shutdown (same as every other headless check in
this repo's agent notes).

**Not verified — no display access in this session.** I have a real
monitor attached to this machine but my shell lacks macOS Screen Recording
permission, so I can't screenshot a windowed `Godot --path .` run myself.
The user explicitly chose to eyeball this themselves via `task run` rather
than grant that permission. Before calling this done-done, someone needs to:
look at the held prop in first person, confirm it doesn't look absurdly
huge/tiny or clipped into the camera near-plane, confirm the horn is
actually pointing away from the player (not sideways/backwards), trigger
Recruit (left click) and À L'ATTAQUE! (right click) to check the
raise/shake animation and particle burst position against the real horn
mouth, and nudge `VisualRoot`'s position/rotation/scale and
`MuzzlePoint`'s position in `Megaphone.tscn` as needed.
