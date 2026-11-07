extends Node
class_name CrowdController

## Centralized crowd controller, per vision.md / agents/crowd-swarm-notes.md.
##
## Owns the list of recruited NPCs and issues crowd-level commands (recruit,
## charge, regroup). Individual NPCs (scripts/npc.gd) only do local steering
## (seek + separation) -- all strategic decisions (who gets recruited, where
## the crowd scatters to) live here.
##
## Recruitment is driven by the megaphone's influence cone: while the player
## holds the recruit input, every unrecruited civilian inside the cone (per
## Megaphone.is_point_within_cone) gets recruited. This controller polls the
## cone each physics frame; it never reaches into NPC internals beyond the
## small recruit()/enter_charge()/enter_regroup() contract on scripts/npc.gd.

@export var player_path: NodePath
@export var npc_spawner_path: NodePath

## How far from the player to even bother checking civilians against the
## cone. Should comfortably cover the megaphone's max range so no
## recruitable civilian is skipped; kept independent of the cone's own range
## so this stays correct even if cone_range is tuned later.
@export var recruit_check_radius: float = 25.0

## Charging: how far (meters) a charging NPC's assigned destination can land
## from the commanded point, so the mob spreads around the target instead of
## stacking on one tile (vision.md: "NPCs should spread around the
## destination rather than stacking on one point").
@export var charge_spread_radius: float = 3.0
@export var charge_reaction_delay_max: float = 0.4

## Regrouping: how far from the player a regrouping NPC's destination can
## land, so the crowd doesn't try to literally occupy the player's exact
## position.
@export var regroup_spread_radius: float = 2.0

var recruited: Array[Node3D] = []

var _player: Node3D
var _npc_spawner: Node
var _megaphone: Node


func _ready() -> void:
	_player = get_node_or_null(player_path)
	_npc_spawner = get_node_or_null(npc_spawner_path)

	if _player == null:
		push_warning("CrowdController: player_path did not resolve, FOLLOW/REGROUP will do nothing.")
	if _npc_spawner == null:
		push_warning("CrowdController: npc_spawner_path did not resolve, nothing to recruit.")


func _physics_process(_delta: float) -> void:
	if _megaphone == null:
		# The active Camera3D isn't guaranteed to be registered with the
		# viewport yet at _ready() (observed headless -- get_camera_3d()
		# returns null for the first frame or so), so resolve lazily here
		# instead of failing once and giving up.
		_megaphone = _find_megaphone()
		if _megaphone != null:
			_megaphone.attack_command_triggered.connect(_on_attack_command)
			_megaphone.regroup_triggered.connect(_on_regroup)
		else:
			return

	if _npc_spawner == null or _player == null:
		return
	if not _megaphone.is_recruiting_held():
		return

	var player_pos: Vector3 = _player.global_position
	for npc in _npc_spawner.spawned_npcs:
		if npc in recruited:
			continue
		if npc.global_position.distance_to(player_pos) > recruit_check_radius:
			continue
		if _megaphone.is_point_within_cone(npc.global_position):
			_recruit(npc)


## Local neighbor search for an NPC's separation steering. O(n) over the
## recruited list -- fine at the NPC counts this prototype targets; if/when
## crowd size grows much further this is the spot to swap in a spatial grid
## (see agents/crowd-swarm-notes.md), nothing in npc.gd would need to change.
func get_neighbors(npc: Node3D, radius: float) -> Array:
	var neighbors: Array = []
	for other in recruited:
		if other == npc:
			continue
		if npc.global_position.distance_to(other.global_position) <= radius:
			neighbors.append(other)
	return neighbors


func _recruit(npc: Node3D) -> void:
	recruited.append(npc)
	npc.recruit(_player, self)
	GameState.recruit_npc()


func _on_attack_command(target_position: Vector3) -> void:
	for npc in recruited:
		var destination: Vector3 = _scatter_point(target_position, charge_spread_radius)
		var delay: float = randf_range(0.0, charge_reaction_delay_max)
		npc.enter_charge(destination, delay)


func _on_regroup() -> void:
	if _player == null:
		return
	for npc in recruited:
		var destination: Vector3 = _scatter_point(_player.global_position, regroup_spread_radius)
		npc.enter_regroup(destination)


## Picks a random point within `radius` of `center`, per vision.md's
## "generate distributed destination positions inside an area around the
## selected point" -- deliberately simple (uniform disc) for this first
## pass. Exists as a single seam to swap in per-destination-type point
## generators later (bus/plaza/road/barricade) without touching callers.
func _scatter_point(center: Vector3, radius: float) -> Vector3:
	var angle: float = randf() * TAU
	var dist: float = sqrt(randf()) * radius
	return center + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)


func _find_megaphone() -> Node:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return null
	return cam.get_node_or_null("Megaphone")
