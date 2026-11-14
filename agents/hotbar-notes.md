# Weapon hotbar UI

Bottom-center HUD element showing which weapon (Megaphone / Croissant) is
currently equipped, per the user's ask for "item hotbar at the bottom so
user can know if they switch items." Pure UI feedback for the existing
weapon-switch mechanic (`WeaponSwitcher.gd`) — not a new core mechanic, so
`vision.md` wasn't touched.

## Files

- `addons/fps_controller/WeaponSwitcher.gd` — added `weapon_switched(index)`
  signal (emitted once in `_ready()` and again on every switch) plus
  `get_weapon_names() -> Array[String]` (just each weapon node's own
  `.name`, so `Megaphone`/`Croissant` show up without any extra config) and
  `get_active_index()`. WeaponSwitcher still owns zero UI itself — this is
  the whole integration surface.
- `scenes/hud.tscn` — added `Root/HotbarMargin/Hotbar` (an `HBoxContainer`
  anchored bottom-center). Left empty in the scene; populated entirely in
  code.
- `scripts/hud.gd` — new `weapon_switcher_path` export. `_build_hotbar()`
  builds one square `PanelContainer` slot per weapon (key number + name
  labels, rounded `StyleBoxFlat`); `_on_weapon_switched()` re-styles the
  active slot (brighter border + text) vs. inactive ones.
- `scenes/test_map.tscn` — wired `HUD.weapon_switcher_path` to
  `../Player/Head/Camera/WeaponSwitcher`.

## Decision: no inventory addon

Per CLAUDE.md's "prefer existing libraries" rule, checked the Asset
Library/GitHub before hand-rolling the slot UI. Searched for a
lightweight, UI-only hotbar addon — found none. The only maintained Godot 4
options (GLoot, expressobits/inventory-system, slot-inventory) are full
inventory *systems*: item `Resource`s, slot/stack data models,
drag-and-drop, serialization. Adopting one just to show "which of 2 fixed
weapons is active" would mean restructuring Megaphone/Croissant as
inventory items for machinery we don't otherwise need. User agreed:
restyled the hotbar in-house with built-in `PanelContainer`/`StyleBoxFlat`
instead. Revisit GLoot specifically if the game ever grows a real
inventory (pickups, loot, stacking) — it's MIT-licensed and the best
option found.

## Gotcha: don't look up code-created child nodes by name/path

First pass built each slot's `KeyLabel`/`NameLabel` in code and then
re-fetched them later via `panel.get_node("VBoxContainer/KeyLabel")` to
restyle on switch. Broke at runtime (`Node not found`) — nodes created in
code don't reliably get the auto-assigned class-name-based `name` you'd get
from the editor. Fixed by keeping direct references in parallel arrays
(`_hotbar_key_labels`, `_hotbar_name_labels`) alongside `_hotbar_slots`
instead of looking anything up by path.

## Verification

Ran `task run-headless`, checked `logs/run-headless.log`. First pass
surfaced the `get_node` bug above (`SCRIPT ERROR: Attempt to call function
'add_theme_color_override' in base 'null instance'`); after the fix, zero
hotbar-related errors or warnings. (A separate in-flight compass-HUD
feature from a concurrent session logs its own unrelated
`Parent(export property) is not set` warning — not this change.)

**Not verified — no display access in this session.** Slot sizing
(`_SLOT_SIZE = Vector2(72, 72)`), colors, and corner radius are a first
guess; someone should eyeball it via `task run` and adjust
`scripts/hud.gd`'s `_SLOT_*` constants / `_make_slot_style()` if it looks
off.
