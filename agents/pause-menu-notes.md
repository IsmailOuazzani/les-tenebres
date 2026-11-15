# Pause menu + upgrade-card current-value readout

## Pause menu (scripts/pause_menu.gd, scenes/pause_menu.tscn)

Escape used to call `NetworkManager.return_to_menu()` directly from
`scenes/test_map.gd`'s `_unhandled_input()`, tearing the whole session down
on a single accidental tap. It now opens a real pause screen (Resume / Leave
Match) instead; "Leave Match" is the only thing that still calls
`return_to_menu()`.

Single-player pauses `get_tree()`, same convention as `game_over.gd` /
`upgrade_screen.gd` (mouse visible, `process_mode = PROCESS_MODE_ALWAYS` on
the CanvasLayer so its own buttons still work while paused).

Multiplayer deliberately does **not** pause the tree -- see
`multiplayer-notes.md`'s "nothing pauses the tree in a networked session"
rule; pausing on the listen server would freeze the authoritative simulation
for every player, not just the one who hit Escape. Instead the menu is
local-only: it calls `NetPlayer.set_input_locked(true)` (scripts/player.gd)
on `PlayerRegistry.local(self)`, which flips that one character's
`process_mode` to `PROCESS_MODE_DISABLED`. That freezes movement, look and
weapon/megaphone input for the pausing player only (process_mode propagates
to children, so Head/Sprint/Megaphone/Croissant/WeaponSwitcher stop too --
same mechanism `_setup_remote()` already uses to silence a remote-owned
character). Every other player and the simulation keep running untouched.

`PauseMenu` won't open over another full-screen overlay (game over, Act
scoreboard, upgrade shop) -- those three now `add_to_group(&"blocking_screen")`
in their `_ready()`, and `_try_open()` checks that group before opening, so
Escape can't stack a second screen on top of one that already owns the
mouse/pause state.

Verified via `scripts/_debug_verify_pause_menu.gd` (headless harness,
boots `test_map.tscn` in single-player, fires a real `ui_cancel` action,
checks `PauseMenu.visible` / `get_tree().paused` / mouse mode, exercises
`set_input_locked()`, and opens/closes the upgrade shop to confirm nothing
regressed). Headless has no display server, so mouse-mode assertions there
are informational only -- `Input.set_mouse_mode()` can't actually capture
without a window; this showed up as `MOUSE_MODE_CAPTURED` silently staying
`VISIBLE` in the headless run even though the same call works in a real
windowed session.

## Upgrade card current-value readout (scripts/upgrade_manager.gd, scripts/upgrade_screen.gd)

`UpgradeManager.get_upgrades()` gained a `current_value` string field,
computed by `_current_value_text()` straight from the live
`*_mult`/`player_bonus_health` vars (never recomputed from `level`, so it
can't drift from what's actually applied). Phrased as the total change from
the neutral level-0 baseline, e.g. `"+20% move speed"` or `"+40 max HP"`.

`upgrade_screen.gd`'s `_build_card()` adds one more label under the
description showing `"Current: <current_value>"`, dimmed at level 0 and
tinted green once a level is bought, so a player can see what they already
have stacked on top of what the next level costs -- not just the level
number.
