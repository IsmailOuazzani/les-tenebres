# Megaphone prop + click-command signals

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
