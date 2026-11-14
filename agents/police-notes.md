# Police Enemy System (MVP) -- Implementation Notes

Status: **implemented**. Built from a direct spec for a minimal police
enemy system (spawn one cop every 10s, three-state AI, protester combat, a
reusable health component). Work was paused partway through for a live
concurrent edit on `Player.tscn`/`Megaphone.gd`/`test_map.tscn` (a
weapon-switching/Croissant feature landing in parallel); resumed and
finished once that settled -- see "Wiring, now done" below.

## What landed

- **`scripts/health_component.gd`** (`HealthComponent`, a plain `Node`):
  `max_health`/`current_health`, `take_damage(amount)`, `health_changed`,
  `died`. Deliberately dumb -- no cooldown/interval logic of its own; every
  caller (cop, protester) already ticks on its own attack-interval timer
  before calling `take_damage()`, so "damage applied at controlled
  intervals" lives at the call site, not in the component. Attached as a
  child node literally named `HealthComponent` on any combat-capable scene
  so callers can do `target.get_node_or_null("HealthComponent")` without
  needing a typed reference.
- **`scripts/police.gd`** / **`scenes/police.tscn`** (`Police`, red capsule
  placeholder, same body shape as `scenes/npc.tscn`): `CHASE_PLAYER` /
  `FIGHT_PROTESTER` / `ATTACK_PLAYER`, pure distance checks, re-evaluated
  from scratch every physics frame in `_update_state()` -- protester
  interception always wins over whatever else the cop was doing, per the
  spec's "ATTACK_PLAYER ... Prioritize nearby protesters if they
  intercept." No separate disengage radius: re-running the nearest-protester
  search every frame using `interception_radius` for both engage and
  disengage is simpler and still matches the spec ("no behavior trees").
  40 HP, 6 dmg/sec, 1.5m attack range, 2.5m interception radius, all
  `@export`ed per the spec's "expose values for easy balancing." `setup(player)`
  is called once by the spawner right after `instantiate()` since cops are
  spawned dynamically and can't get a `NodePath` wired up in the editor.
- **`scripts/police_spawner.gd`** (`PoliceSpawner`, a `Node3D`): one cop
  every `spawn_interval` (10s) in a ring around the player
  (`spawn_radius_min`/`max`), preferring a point outside the active
  camera's forward view cone (dot-product check against the camera's
  horizontal forward vector) -- falls back to the last attempt if 20 tries
  all land in view. Not yet instanced anywhere (see below).
- **`scripts/npc.gd`** / **`scenes/npc.tscn`**: protesters get a
  `HealthComponent` (25 HP) + the same billboard `ProgressBar3D` health bar
  pattern as `scripts/destructible_prop.gd`, shown only once damaged.
  `recruit()` now also does `add_to_group(&"protester")` -- only recruited
  NPCs are valid cop-interception targets, per the spec's "**Existing
  recruited protesters** should automatically damage nearby cops." Combat
  itself (`_process_police_combat()`) runs every physics frame regardless
  of steering state (FOLLOW/CHARGE), on its own 0.5s attack-interval timer,
  independent of whatever state the NPC's movement is in -- per the spec's
  "Protesters can intercept police by moving into their proximity," this is
  passive/automatic, not a new NPC state. On death, calls the new
  `CrowdController.remove_recruit(self)` (erases from `recruited`, reclamps
  `_send_pointer`) before `queue_free()`.
- **`scripts/crowd_controller.gd`**: added `remove_recruit(npc)` as the
  counterpart to `_recruit()`, called from `npc.gd`'s death handler.

## Wiring, now done

1. **Player health.** `HealthComponent` (100 HP) added as a child of
   `addons/fps_controller/Player.tscn`'s root, alongside the existing
   `Megaphone`/`Sprint`/`Croissant`/`WeaponSwitcher` additions on top of the
   vendored `MovementController` base scene.
2. **`PoliceSpawner` wired into `scenes/test_map.tscn`** as a sibling of
   `NPCSpawner`/`CrowdController`, `player_path = ../Player`, `police_scene
   = res://scenes/police.tscn`.
3. **Player death handling.** New `GameState.trigger_player_death()` (sets
   `_game_over_fired`, emits `game_over` -- same terminal state Grabuge
   decay reaches) connected from `scenes/test_map.gd`'s `_ready()` to
   `Player/HealthComponent.died`, so the vendored `Player.tscn` doesn't need
   to know about `GameState`.
4. **Player HUD health readout** (nice-to-have, not in the DoD, but
   otherwise cop damage would be invisible to the player). Added
   `HealthLabel`/`HealthBar` to `scenes/hud.tscn`, a `player_health_path`
   export on `hud.gd` wired to `../Player/HealthComponent` in
   `test_map.tscn`, same pattern as the existing crowd-count/Grabuge
   readouts.

## Verified

`task run-headless` equivalent (`--quit-after 12`, long enough to cross the
10s spawn interval): clean, no parse/script/runtime errors. Per CLAUDE.md's
rule on verifying live scene trees for anything added to a scene touched by
a generator script, did a one-off `print_tree_pretty()` in
`scenes/test_map.gd`'s `_ready()` (reverted after) and confirmed
`Player/HealthComponent`, all 30 `NPC/HealthComponent`s, and the new
`PoliceSpawner` node are correctly nested exactly once each -- not
duplicated or misplaced.

**Not verified -- no display access in this environment:** how the cop
capsule/outline actually reads visually, whether 6 dmg/sec feels
appropriately threatening against 100 HP, whether the spawn-outside-camera
heuristic actually keeps cops from popping in right in front of the player,
and whether protesters reliably peel off to fight an intercepting cop
without visibly stalling the mob's charge. **Someone needs to run `task
run`**: get recruits, let a cop catch up, confirm it either starts biting
you or gets intercepted by your mob, and confirm a dead protester actually
leaves `CrowdController.recruited` (e.g. a Send Mob command right after a
protester death shouldn't try to move a freed node).

## Update: interception gated on CHARGE state

Direct feedback: cops were engaging any nearby recruited protester,
including ones just standing in FOLLOW near the player -- so a cop chasing
the player through a crowd would get dragged into a fight it was never
directed into. Per the new vision.md "Police" line, cops should beeline for
the player and only engage once the player actively sends part of the crowd
at them.

Fix: `Police._find_nearest_protester()` now skips any protester whose
`is_charging()` (new `scripts/npc.gd` method, `state == State.CHARGE`)
returns false. Symmetrically, `NPC._process_police_combat()` (protesters'
auto-attack on nearby cops) now only runs while the protester itself is
`State.CHARGE` -- a FOLLOW-state crowd no longer passively plinks a cop that
runs past it either. Both sides of the engagement are now gated on the same
"was this protester actively sent here" check, so a cop ignoring the crowd
and a crowd ignoring the cop stay consistent with each other.

Not verified in-engine (no display access here) -- someone should confirm:
a cop beelines straight through/past a standing FOLLOW crowd without
stopping, and only breaks off once a Send Mob charge lands a few protesters
near it.

## Update: police are now a direct Send Mob target

Direct feedback: aiming at a cop didn't outline it like `destructible_prop`
(trash etc.) does -- turned out cops were on physics layer 3 ("NPCs") only,
and `Megaphone`'s aim raycast queries layer 1 ("Objects") by default, so the
ray never even hit a cop. Per the updated vision.md ("Police are a Send Mob
target like any destructible object"), fixed end to end:

- `scenes/police.tscn`: `collision_layer` changed from `4` (NPCs only) to
  `5` (NPCs | Objects) so the aim raycast can hit a cop at all. Added an
  `Outline` capsule mesh (same yellow-highlight material/pattern as
  `destructible_prop.tscn`'s Outline), hidden by default.
- `scripts/police.gd`: joins the `"destructible"` group alongside the
  existing `"police"` group; added `set_targeted(active)` (toggles the new
  Outline) and `take_damage(amount)` (delegates to the existing
  `HealthComponent`) matching `destructible_prop.gd`'s contract exactly, so
  `Megaphone`'s reticle and `CrowdController`'s `_on_send_mob`/
  `_process_attack_target_damage` need zero special-casing for cops. Added
  a `destroyed` signal, emitted from `_on_died()` before `queue_free()`, so
  `CrowdController`'s one-shot `_attack_target.destroyed` connection clears
  correctly when a directly-targeted cop dies.

Deliberately did *not* bypass the CHARGE-gated interception above: Send
Mob-ing a cop doesn't fight it directly by itself, it just sends selected
protesters charging toward the cop's position, which is exactly what makes
them `is_charging()` and lets the existing interception/melee logic (plus
CrowdController's passive attack-target damage tick) take over once they
arrive. No new combat path, just a new way to aim the existing one.

Not verified in-engine (no display access here) -- someone should confirm:
the cop actually gets the yellow outline when aimed at, Send Mob-ing a cop
spawns the attack marker/flash like any other target, and the cop's health
bar ticks down correctly from both a direct charge and ordinary protester
melee.

## Update: charges now track a moving target; interception scoped per-cop

Two more bugs from direct feedback, same session:

1. **Charging at a cop that then moves** never actually caught it --
   `CrowdController._on_send_mob` took a one-shot snapshot of
   `target.global_position` at command time, so protesters charged toward
   where the cop *used to be*. Fixed with a new `NPC.enter_charge_at_target
   (target, offset, reaction_delay)` (alongside the existing
   `enter_charge(destination, ...)` for plain move-to-point commands):
   stores the target + a scatter offset, and `_process_charge()` re-reads
   `target.global_position + offset` every frame instead of a static
   `target_position`. `CrowdController` now calls this variant whenever
   `_on_send_mob`'s `target` is non-null; stationary destructibles (props)
   behave identically either way since their position never changes.

2. **Targeting one cop pulled every other nearby cop into fighting the
   crowd too**, even cops the player never selected -- `_find_nearest_
   protester()`/`_find_nearest_cop()` only checked "is this protester
   charging at all," not *which* cop/target it was actually sent at.
   Replaced `NPC.is_charging()` with `NPC.can_engage(cop)`: true for a
   plain move-to-point charge (`_charge_target == null` -- any cop may
   still intercept, the original distance-based design for "directed near
   a cop without selecting it"), but for a charge aimed at a specific
   destructible (`_charge_target != null`) only *that* object counts, so a
   protester charging at cop A no longer fights cop B just by passing near
   it. Applied symmetrically on both sides (`Police._find_nearest_
   protester()` and `NPC._find_nearest_cop()`).

Newly spawned cops still default to `State.CHASE_PLAYER` (`PoliceSpawner.
_spawn_police()` calls `setup(player)` right after instantiate, and that's
the var's default) -- confirmed unaffected by either fix, just flagging
since it was called out as a must-hold invariant.

Not verified in-engine: does a charging protester actually catch up to a
cop that keeps moving away, and does targeting cop A while cop B is nearby
leave cop B chasing the player undisturbed.
