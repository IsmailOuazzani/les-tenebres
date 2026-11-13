# les tenebres

Godot 4.7 project. See `vision.md` for the game concept, core mechanics, and design pillars.

**Rule:** `vision.md` should stay short. Keep it a high-level reference, not a growing design document — resist adding exhaustive detail over time.

**Rule:** Agent notes (research findings, implementation decisions, TODOs) go in the `agents/` folder in this repo, not scattered in chat or lost between sessions.

**Rule:** Prefer existing libraries, addons, and controllers over reinventing the wheel — this applies even to small pieces (a billboard health bar, a progress bar shader), not just big systems. Before writing custom systems (FPS controllers, crowd/AI behavior, UI frameworks, health/progress bars, etc.), check the Godot Asset Library and GitHub for a solid free/open-source option first and use it instead of a homegrown version. Example: the destructible-prop health bar was originally two overlapping `QuadMesh` billboards that z-fought; it was replaced with the MIT-licensed `addons/progress_bar_3d` (single quad + shader, no z-fighting by construction) rather than patching the custom version.

**Rule:** When a change depends on the live scene tree — a cross-node lookup (`get_node`, `get_viewport().get_camera_3d()`, group/signal wiring across instanced scenes), or anything added to a scene that was built or edited by a procedural/generator script rather than by hand in the editor — verify the actual runtime tree (e.g. `print_tree_pretty()` via `task run-headless`, then check `logs/run-headless.log`), not just that the project loads without parse/script errors. "No errors" only proves the file is syntactically valid; it does not prove a node exists where the code expects it. Scenes assembled by a script (rather than the editor's own instancing/override mechanism) are especially prone to silently duplicating nodes instead of properly overriding nested-instance children — this exact bug (a duplicate `Player/Head/Camera` with no `Megaphone` child, caused by `test_map.tscn` being rebuilt via a generator script) cost significant back-and-forth before a tree dump caught it.

**Rule:** Multiple agents may be working in this repo at the same time (parallel sessions, worktrees, etc.). Don't assume you're the only one touching files — check `git status`/`git diff` for unexpected changes before overwriting work, avoid clobbering edits that aren't yours, and don't run destructive or repo-wide operations (resets, force-pushes, mass reformatting) without confirming they won't stomp on another agent's in-flight changes.

## Running the game

Use the Taskfile (`task` CLI):

- `task run` — launch the game without the editor; output is logged to `logs/run.log` (gitignored)
- `task run-headless` — launch without a window (no rendering); output is logged to `logs/run-headless.log` (gitignored)
- `task editor` — open the project in the Godot editor
