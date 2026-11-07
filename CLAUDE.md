# les tenebres

Godot 4.7 project. See `vision.md` for the game concept, core mechanics, and design pillars.

**Rule:** `vision.md` should stay short. Keep it a high-level reference, not a growing design document — resist adding exhaustive detail over time.

**Rule:** Agent notes (research findings, implementation decisions, TODOs) go in the `agents/` folder in this repo, not scattered in chat or lost between sessions.

**Rule:** Prefer existing libraries, addons, and controllers over reinventing the wheel. Before writing custom systems (FPS controllers, crowd/AI behavior, UI frameworks, etc.), check the Godot Asset Library and GitHub for a solid free/open-source option first.

## Running the game

Use the Taskfile (`task` CLI):

- `task run` — launch the game without the editor
- `task run-headless` — launch without a window (no rendering)
- `task editor` — open the project in the Godot editor
