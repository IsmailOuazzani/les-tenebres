extends Node

## UpgradeManager: between-wave player/crowd upgrade purchasing, per
## vision.md's Upgrade System section and agents/wave-survival-notes.md's
## integration contract (the contract this file implements exactly).
## Registered as the `UpgradeManager` autoload (see project.godot [autoload]).
##
## Owns six repeatable upgrades (ids below), each a multiplier (or, for
## player_health, a flat HP bonus) that starts at a neutral value and is
## nudged per purchase. Purchases are paid for via GameState.spend_grabuge()
## and never touch grabuge_total_earned, so buying upgrades can never shrink
## the civilian spawn pool (see agents/grabuge-notes.md / game_state.gd).
##
## This autoload only tracks the numbers and spends currency -- it does NOT
## reach into the player or NPCs itself. scenes/test_map.gd applies player
## upgrades (from outside the vendored addons/fps_controller/ scene, per the
## contract's "known gotchas"), and scripts/npc.gd / crowd_controller.gd read
## the crowd multipliers directly. See each file's comments for how.
##
## ## Multiplayer
##
## Upgrades are **shared and server-authoritative**, for the same reason
## Grabuge is: there is one protest, one war chest and one crowd, so one
## upgrade set. A level bought by any player applies to every player (and to
## the shared crowd) -- the alternative, per-player upgrade sets paid for out
## of a shared wallet, would also mean a client's crowd upgrades had no
## effect at all, since the crowd is simulated only on the server.
##
## A client's purchase is therefore a *request*: purchase() rpc_id(1)s the
## server, which does the spending and broadcasts the resulting level back.
## purchase() returns false on a client even when the request will succeed --
## callers refresh off `upgrade_purchased` / `GameState.grabuge_changed`
## rather than off the return value (see scripts/upgrade_screen.gd).

signal upgrade_purchased(id: StringName, new_level: int)

## -- Per-purchase effect sizes (vision.md's Upgrade System table) --
## All configurable here, named rather than inlined, per CLAUDE.md's
## "all numbers must be configurable" rule for this feature.
const PLAYER_SPEED_STEP: float = 0.10       ## +10% move speed per level
const PLAYER_JUMP_STEP: float = 0.15        ## +15% jump height per level
const PLAYER_HEALTH_STEP: float = 20.0      ## +20 max HP (and +20 heal) per level
const CROWD_SPEED_STEP: float = 0.10        ## +10% protester move speed per level
const CROWD_HEALTH_STEP: float = 0.20       ## +20% protester max HP per level
const CROWD_DAMAGE_STEP: float = 0.15       ## +15% protester damage per level

## -- Pricing --
## Base price (level 0 -> 1) and the per-level price multiplier. Suggested
## in the brief; tune here if playtesting says otherwise.
const PRICE_GROWTH: float = 1.5

const BASE_PRICES: Dictionary = {
	&"player_speed": 40.0,
	&"player_jump": 40.0,
	&"player_health": 60.0,
	&"crowd_speed": 50.0,
	&"crowd_health": 50.0,
	&"crowd_damage": 70.0,
}

## Display metadata, keyed by id -- kept alongside the prices/steps above so
## adding a 7th upgrade later is a matter of adding one entry per Dictionary,
## not touching get_upgrades()/purchase()'s logic.
const UPGRADE_NAMES: Dictionary = {
	&"player_speed": "Speed",
	&"player_jump": "Jump",
	&"player_health": "Health",
	&"crowd_speed": "Crowd Velocity",
	&"crowd_health": "Crowd Health",
	&"crowd_damage": "Crowd Strength",
}

const UPGRADE_DESCRIPTIONS: Dictionary = {
	&"player_speed": "+10% move speed",
	&"player_jump": "+15% jump height",
	&"player_health": "+20 max HP, heals 20 HP",
	&"crowd_speed": "+10% protester move speed",
	&"crowd_health": "+20% protester max HP",
	&"crowd_damage": "+15% protester damage",
}

## Canonical upgrade id list -- iteration order for get_upgrades().
const UPGRADE_IDS: Array[StringName] = [
	&"player_speed",
	&"player_jump",
	&"player_health",
	&"crowd_speed",
	&"crowd_health",
	&"crowd_damage",
]

## -- Live multipliers, read by whoever owns the stat. All start at 1.0 (no
## effect) -- see reset(). Derived from `_levels` below via
## _multiplier_for(), never multiplied in place, so repeat purchases can't
## compound onto an already-multiplied value.
var player_speed_mult: float = 1.0
var player_jump_mult: float = 1.0
var crowd_speed_mult: float = 1.0
var crowd_health_mult: float = 1.0
var crowd_damage_mult: float = 1.0

## Flat bonus HP added to the player's max_health -- NOT a multiplier, per
## the contract.
var player_bonus_health: float = 0.0

## Purchase level per upgrade id, 0 = never bought. Source of truth that
## every multiplier/bonus above is derived from.
var _levels: Dictionary = {}


func _ready() -> void:
	reset()


## One entry per upgrade: {id, name, description, price, level, affordable,
## current_value}. Built fresh each call (cheap, 6 entries) so callers (the
## upgrade screen) always see live prices/affordability without needing their
## own signal bookkeeping beyond upgrade_purchased + GameState.grabuge_changed.
func get_upgrades() -> Array[Dictionary]:
	var upgrades: Array[Dictionary] = []
	for id in UPGRADE_IDS:
		var level: int = _levels.get(id, 0)
		var price: float = _price_for(id, level)
		upgrades.append({
			"id": id,
			"name": UPGRADE_NAMES[id],
			"description": UPGRADE_DESCRIPTIONS[id],
			"price": price,
			"level": level,
			"affordable": price <= GameState.grabuge_available,
			"current_value": _current_value_text(id),
		})
	return upgrades


## Current total effect of `id` at its live level, phrased as a change from
## the neutral (level 0) baseline -- shown on the upgrade card so a player
## can see what they already have, not just what the next level costs. Reads
## the live mult/bonus vars directly rather than recomputing from level, so
## this can never drift out of sync with what's actually applied.
func _current_value_text(id: StringName) -> String:
	match id:
		&"player_speed":
			return "+%d%% move speed" % roundi((player_speed_mult - 1.0) * 100.0)
		&"player_jump":
			return "+%d%% jump height" % roundi((player_jump_mult - 1.0) * 100.0)
		&"player_health":
			return "+%d max HP" % roundi(player_bonus_health)
		&"crowd_speed":
			return "+%d%% protester speed" % roundi((crowd_speed_mult - 1.0) * 100.0)
		&"crowd_health":
			return "+%d%% protester HP" % roundi((crowd_health_mult - 1.0) * 100.0)
		&"crowd_damage":
			return "+%d%% protester damage" % roundi((crowd_damage_mult - 1.0) * 100.0)
	return ""


## Attempts to buy one more level of `id`. Returns true and applies the
## effect on success, false (no change at all) if GameState.spend_grabuge()
## can't afford it or `id` isn't a known upgrade.
func purchase(id: StringName) -> bool:
	if not BASE_PRICES.has(id):
		push_warning("UpgradeManager.purchase(): unknown upgrade id %s" % id)
		return false

	if not NetworkManager.is_authoritative():
		_request_purchase.rpc_id(1, id)
		return false

	var level: int = _levels.get(id, 0)
	var price: float = _price_for(id, level)
	if not GameState.spend_grabuge(price):
		return false

	var new_level: int = level + 1
	_set_level(id, new_level)
	if NetworkManager.is_multiplayer_session():
		_apply_purchase.rpc(id, new_level)
	return true


## Resets every upgrade back to level 0 / neutral multipliers. Called by
## game_over.gd's restart handler alongside GameState.reset() and
## WaveManager.reset(), since autoloads survive reload_current_scene().
func reset() -> void:
	_levels.clear()
	for id in UPGRADE_IDS:
		_levels[id] = 0
	player_speed_mult = 1.0
	player_jump_mult = 1.0
	crowd_speed_mult = 1.0
	crowd_health_mult = 1.0
	crowd_damage_mult = 1.0
	player_bonus_health = 0.0
	if NetworkManager.is_authoritative() and NetworkManager.is_multiplayer_session():
		_apply_reset.rpc()


func _set_level(id: StringName, new_level: int) -> void:
	_levels[id] = new_level
	_apply_level(id, new_level)
	upgrade_purchased.emit(id, new_level)


## Price to go from `level` to `level + 1`: base * PRICE_GROWTH^level, so
## price grows ~1.5x per level as suggested in the brief.
func _price_for(id: StringName, level: int) -> float:
	var base: float = BASE_PRICES[id]
	return base * pow(PRICE_GROWTH, level)


## Recomputes the live multiplier/bonus for `id` from `new_level` directly
## (1.0 + step * level, or step * level for the flat health bonus) rather
## than multiplying the previous value -- this is what keeps repeat
## purchases from compounding onto an already-multiplied number.
func _apply_level(id: StringName, new_level: int) -> void:
	match id:
		&"player_speed":
			player_speed_mult = 1.0 + PLAYER_SPEED_STEP * new_level
		&"player_jump":
			player_jump_mult = 1.0 + PLAYER_JUMP_STEP * new_level
		&"player_health":
			# Flat bonus derived from level, then test_map.gd (which owns the
			# player's HealthComponent from outside the vendored addon) is
			# responsible for applying the +20 raise AND the +20 heal for
			# this specific purchase -- see upgrade_purchased consumers.
			player_bonus_health = PLAYER_HEALTH_STEP * new_level
		&"crowd_speed":
			crowd_speed_mult = 1.0 + CROWD_SPEED_STEP * new_level
		&"crowd_health":
			crowd_health_mult = 1.0 + CROWD_HEALTH_STEP * new_level
		&"crowd_damage":
			crowd_damage_mult = 1.0 + CROWD_DAMAGE_STEP * new_level


# --------------------------------------------------------------------------
# Replication
# --------------------------------------------------------------------------

## Reliable: a dropped purchase would leave a client's shop permanently out
## of step with the server's levels and prices.
@rpc("authority", "call_remote", "reliable")
func _apply_purchase(id: StringName, new_level: int) -> void:
	if not BASE_PRICES.has(id):
		return
	_set_level(id, new_level)


@rpc("authority", "call_remote", "reliable")
func _apply_reset() -> void:
	reset()


@rpc("any_peer", "call_remote", "reliable")
func _request_purchase(id: StringName) -> void:
	if not NetworkManager.is_authoritative():
		return
	purchase(id)
