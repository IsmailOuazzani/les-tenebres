# les tenebres

Godot 4.7 project. See `vision.md` for the game concept, core mechanics, and design pillars.

**Rule:** `vision.md` should stay short. Keep it a high-level reference, not a growing design document — resist adding exhaustive detail over time.

**Rule:** Agent notes (research findings, implementation decisions, TODOs) go in the `agents/` folder in this repo, not scattered in chat or lost between sessions.

**Rule:** Prefer existing libraries, addons, and controllers over reinventing the wheel — this applies even to small pieces (a billboard health bar, a progress bar shader), not just big systems. This applies from the very first response on a feature, not just when writing code: before proposing or implementing any custom system (FPS controllers, crowd/AI behavior, UI frameworks, health/progress bars, hit/damage VFX, etc.), search the Godot Asset Library and GitHub for a solid free/open-source option first, and lead with those results — don't sketch a homegrown approach first and only search if asked. This holds even when the user says to "stay in idea land" or asks for brainstorming with no implementation yet — ideas should still be addon-first. Example: the destructible-prop health bar was originally two overlapping `QuadMesh` billboards that z-fought; it was replaced with the MIT-licensed `addons/progress_bar_3d` (single quad + shader, no z-fighting by construction) rather than patching the custom version.

**Rule:** When a change depends on the live scene tree — a cross-node lookup (`get_node`, `get_viewport().get_camera_3d()`, group/signal wiring across instanced scenes), or anything added to a scene that was built or edited by a procedural/generator script rather than by hand in the editor — verify the actual runtime tree (e.g. `print_tree_pretty()` via `task run-headless`, then check `logs/run-headless.log`), not just that the project loads without parse/script errors. "No errors" only proves the file is syntactically valid; it does not prove a node exists where the code expects it. Scenes assembled by a script (rather than the editor's own instancing/override mechanism) are especially prone to silently duplicating nodes instead of properly overriding nested-instance children — this exact bug (a duplicate `Player/Head/Camera` with no `Megaphone` child, caused by `test_map.tscn` being rebuilt via a generator script) cost significant back-and-forth before a tree dump caught it.

**Rule:** Multiple agents may be working in this repo at the same time (parallel sessions, worktrees, etc.). Don't assume you're the only one touching files — check `git status`/`git diff` for unexpected changes before overwriting work, avoid clobbering edits that aren't yours, and don't run destructive or repo-wide operations (resets, force-pushes, mass reformatting) without confirming they won't stomp on another agent's in-flight changes.

**Rule:** Whenever the user asks about a core change (to the game concept, core mechanics, or design pillars), ask if they want it added to `vision.md`.

## Running the game

Use the Taskfile (`task` CLI):

- `task run` — launch the game without the editor; output is logged to `logs/run.log` (gitignored)
- `task run-headless` — launch without a window (no rendering); output is logged to `logs/run-headless.log` (gitignored)
- `task editor` — open the project in the Godot editor

**Rule:** Never run `task run` (or launch the Godot binary windowed) yourself. The user runs the windowed game and reports back what they see. For your own verification, use `task run-headless` plus a one-off debug script (`--headless --script res://scripts/_debug_*.gd` extending `SceneTree`) to inspect scene/material/node state via prints to `logs/run-headless.log`, not a live window.

**Rule:** When pulling in a third-party `.glb`/`.gltf` asset, check whether it references external image files (e.g. a shared `colormap.png` atlas) instead of embedding them — copy those texture files into the project too, not just the model file. If the model gets imported by Godot before its texture exists (or before a full reimport), Godot bakes a cached material with a null `albedo_texture` into `.godot/imported/`, and a plain `--headless --import` pass does *not* reliably refresh that cache even after the texture is added later. Verify by loading the scene in a `--headless --script` debug script and printing `mesh_instance.get_active_material(i).albedo_texture` — don't assume "no import errors" means the texture linked correctly. If it's still null, delete the asset's `.import` file and its corresponding `.godot/imported/*.scn`/`*.res` before reimporting to force a clean rebuild.
