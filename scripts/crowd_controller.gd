extends Node
class_name CrowdController

## Centralized crowd controller, per vision.md / agents/crowd-swarm-notes.md.
##
## Owns the list of recruited NPCs and issues crowd-level commands (recruit,
## charge). Individual NPCs (scripts/npc.gd) only do local steering (seek +
## separation) -- all strategic decisions (who gets recruited, where the
## crowd scatters to) live here.
##
## ## Multiplayer
##
## The crowd simulation is **server-authoritative** and there is exactly
## **one shared protest crowd** for the whole session (spec 4.2: no personal
## squads, no player-owned protesters). This node runs its simulation only on
## the listen server (or in single-player); on a client it exists purely as
## the RPC endpoint that forwards that peer's crowd commands to the server.
##
## Recruitment is driven by the megaphone's ground-circle range: while *any*
## player holds the recruit input, every unrecruited civilian inside that
## player's radius gets recruited into the shared crowd. The server polls each
## player's replicated `net_recruiting` flag (see scripts/player.gd), so a
## remote player's megaphone recruits exactly like the host's. A civilian can
## only be recruited once -- `recruited` membership is the guard.
##
## Crowd commands follow **last valid command wins** (spec 4.3): a newer
## `apply_send_mob()` from any player simply reassigns its slice of the crowd
## and overwrites `_attack_target`. There is deliberately no command queue, no
## squad ownership and no per-player priority.

@export var npc_spawner_path: NodePath

## Charging: how far (meters) a charging NPC's assigned destination can land
## from the commanded point, so the mob spreads around the target instead of
## stacking on one tile (vision.md: "NPCs should spread around the
## destination rather than stacking on one point").
@export var charge_spread_radius: float = 3.0
@export var charge_reaction_delay_max: float = 0.4

## -- Destructible props (PoC) --
## How close an attacking NPC needs to be to the active attack target to
## contribute damage. Kept comfortably >= charge_spread_radius (plus a
## margin for the target's own footprint) so NPCs that arrive at their
## scattered charge destination are actually still in range to hit it --
## otherwise most of the mob lands just outside attack_range and never
## deals damage.
@export var attack_range: float = 4.0
## Per vision.md's "Cause chaos" -- each attacking NPC in range does this
## much damage per second to the active target.
@export var attack_damage_per_second: float = 1.0

var recruited: Array[Node3D] = []

## Rotating cursor into `recruited`, per agents/mob-selector-notes.md: a
## partial-percentage send takes its slice starting here (wrapping around
## the list like a ring) and advances this by however many NPCs it just
## took, so repeated same-percentage sends keep rotating through different
## NPCs instead of always drawing the same slice.
var _send_pointer: int = 0

var _npc_spawner: Node
var _attack_target: Node3D = null

## Base (pre-upgrade) value of attack_damage_per_second, captured once in
## _ready() so _apply_crowd_damage_mult() always derives from the same
## starting point rather than multiplying the current live value -- see
## agents/wave-survival-notes.md ("don't compound multipliers").
var _base_attack_damage_per_second: float = 0.0


func _ready() -> void:
	_npc_spawner = get_node_or_null(npc_spawner_path)
	# Lets the player's Megaphone route its Send Mob command here by group
	# instead of an exported NodePath -- Megaphone lives nested inside
	# scenes/player.tscn, which is spawned at runtime and so has no editor
	# path to a sibling-of-Players node.
	add_to_group(&"crowd_controller")

	# There are two crowd damage paths per the integration contract: this one
	# (Send Mob vs. a targeted destructible/cop) and npc.gd's own
	# damage_per_second (protester melee vs. cops). crowd_damage_mult applies
	# to both; npc.gd applies it to itself.
	_base_attack_damage_per_second = attack_damage_per_second
	_apply_crowd_damage_mult()
	UpgradeManager.upgrade_purchased.connect(_on_upgrade_purchased)

	if _npc_spawner == null:
		push_warning("CrowdController: npc_spawner_path did not resolve, nothing to recruit.")


func _physics_process(delta: float) -> void:
	# Clients run no crowd simulation at all -- NPC transforms and states
	# arrive as replicated state (see scripts/npc.gd).
	if not NetworkManager.is_authoritative():
		return

	_prune_recruited()
	GameState.set_live_crowd_count(recruited.size())
	_process_attack_target_damage(delta)
	_process_recruitment()


## Shared-crowd recruitment across every player in the session. Each player
## contributes their own megaphone circle; a civilian inside any of them
## joins the one collective crowd.
func _process_recruitment() -> void:
	if _npc_spawner == null:
		return

	var recruiters: Array[Node3D] = []
	for player in PlayerRegistry.all(self):
		if player.has_method(&"is_recruiting") and player.is_recruiting():
			recruiters.append(player)
	if recruiters.is_empty():
		return

	for npc in _npc_spawner.spawned_npcs:
		if not is_instance_valid(npc):
			continue
		if npc in recruited:
			continue
		for player in recruiters:
			var radius: float = player.get_recruit_radius()
			var delta_xz := Vector2(
				npc.global_position.x - player.global_position.x,
				npc.global_position.z - player.global_position.z
			)
			if delta_xz.length() <= radius:
				_recruit(npc)
				break


func _on_upgrade_purchased(id: StringName, _new_level: int) -> void:
	if id == &"crowd_damage":
		_apply_crowd_damage_mult()


func _apply_crowd_damage_mult() -> void:
	attack_damage_per_second = _base_attack_damage_per_second * UpgradeManager.crowd_damage_mult


## Ticks damage on the active attack target (if any) from every recruited
## NPC currently within `attack_range` of it -- per vision.md's "Cause
## chaos: Protesters interact with the target." Deliberately simple for the
## PoC: doesn't check that an NPC was actually *sent* to this target (vs.
## just wandering past it in FOLLOW), since in practice only charging NPCs
## end up near a freshly-commanded target.
func _process_attack_target_damage(delta: float) -> void:
	if _attack_target == null:
		return
	if not is_instance_valid(_attack_target):
		_attack_target = null
		return

	var target_pos: Vector3 = _attack_target.global_position
	for npc in recruited:
		if npc.global_position.distance_to(target_pos) <= attack_range:
			_attack_target.take_damage(attack_damage_per_second * delta)


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


## Live headcount of currently-recruited NPCs. Server-side only -- clients
## read GameState.live_crowd_count, the replicated mirror of this.
func get_recruited_count() -> int:
	return recruited.size()


## Drops freed NPCs out of the recruited list. NPCs can be despawned by the
## server (death, distance despawn) between frames, and on the server the
## despawn is a plain queue_free() that the MultiplayerSpawner mirrors to
## clients -- so this list is the one place that needs sweeping.
func _prune_recruited() -> void:
	var changed: bool = false
	for i in range(recruited.size() - 1, -1, -1):
		if not is_instance_valid(recruited[i]):
			recruited.remove_at(i)
			changed = true
	if changed and not recruited.is_empty():
		_send_pointer = _send_pointer % recruited.size()
	elif changed:
		_send_pointer = 0


func _recruit(npc: Node3D) -> void:
	recruited.append(npc)
	npc.recruit(self)
	GameState.recruit_npc()
	_recruit_feedback(npc.global_position)
	if NetworkManager.is_multiplayer_session():
		_recruit_feedback.rpc(npc.global_position)


## Cosmetic only (positional recruit sting). Unreliable: losing one is
## inaudible, and replaying it late would be worse than dropping it.
@rpc("authority", "call_remote", "unreliable")
func _recruit_feedback(at_position: Vector3) -> void:
	AudioManager.play_recruit_feedback(at_position)


## Called by an NPC's own death handler (scripts/npc.gd's _on_died()) once a
## cop kills it, so `recruited` and the ring-slice pointer don't end up
## pointing at a freed node. Doesn't touch GameState's crowd_count -- that's
## a separate "ever recruited" counter, not a live headcount.
func remove_recruit(npc: Node3D) -> void:
	recruited.erase(npc)
	if recruited.is_empty():
		_send_pointer = 0
	else:
		_send_pointer = _send_pointer % recruited.size()


# --------------------------------------------------------------------------
# Crowd commands (client -> server)
# --------------------------------------------------------------------------

## Client -> server crowd command. Reliable: a Send Mob order is a discrete
## gameplay event, and silently dropping one would read as the game ignoring
## the player.
##
## `target_path` is the absolute scene path of the aimed-at destructible (or
## "" for a move-to-point order). Paths are used rather than object ids
## because node ids are per-process: props live in the statically loaded map
## scene and police/NPCs are spawned by the server's MultiplayerSpawners, so
## the same path resolves on every peer.
@rpc("any_peer", "call_remote", "reliable")
func request_send_mob(percentage: float, target_path: String, point: Vector3) -> void:
	if not NetworkManager.is_authoritative():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if not NetworkManager.players.has(sender):
		return
	apply_send_mob(percentage, target_path, point)


## Single handler for the unified Send Mob command, per
## agents/mob-selector-notes.md: `target_path` resolving to a
## "destructible"-group interactable means attack that object; empty (the
## yellow-ball fallback) means march to `point` instead. Either way,
## `percentage` of `recruited` is selected via the rotating ring slice below
## and reassigned -- NPCs not selected keep doing whatever they were already
## doing.
##
## Last valid command wins (spec 4.3), no matter which player issued it: this
## just overwrites `_attack_target` and reassigns its slice.
func apply_send_mob(percentage: float, target_path: String, point: Vector3) -> void:
	if not NetworkManager.is_authoritative():
		return
	if recruited.is_empty():
		return

	var count: int = clampi(roundi(percentage * recruited.size()), 0, recruited.size())
	if count <= 0:
		return
	var selected: Array = _take_ring_slice(count)
	_mob_roar(count)
	if NetworkManager.is_multiplayer_session():
		_mob_roar.rpc(count)

	var target: Node3D = null
	if target_path != "":
		var resolved: Node = get_node_or_null(NodePath(target_path))
		if resolved is Node3D and resolved.is_in_group(&"destructible"):
			target = resolved

	if target != null:
		_attack_target = target
		if not _attack_target.destroyed.is_connected(_on_attack_target_destroyed):
			_attack_target.destroyed.connect(_on_attack_target_destroyed, CONNECT_ONE_SHOT)

		# Live-track the target instead of a one-shot position snapshot --
		# per direct feedback, a cop that moves after being targeted was
		# otherwise never caught because protesters charged toward where it
		# *used* to be. See NPC.enter_charge_at_target().
		for npc in selected:
			var offset: Vector3 = _scatter_point(Vector3.ZERO, charge_spread_radius)
			var delay: float = randf_range(0.0, charge_reaction_delay_max)
			npc.enter_charge_at_target(target, offset, delay)
		return

	for npc in selected:
		var destination: Vector3 = _scatter_point(point, charge_spread_radius)
		var delay: float = randf_range(0.0, charge_reaction_delay_max)
		npc.enter_charge(destination, delay)


## Cosmetic crowd roar, scaled by how many protesters were committed. Local
## on every peer so all players hear the same command land.
@rpc("authority", "call_remote", "unreliable")
func _mob_roar(count: int) -> void:
	AudioManager.play_mob_roar(count)


## Takes `count` NPCs from `recruited` starting at `_send_pointer`, treating
## the list as a ring (wraps past the end back to index 0), then advances
## `_send_pointer` by `count` so the *next* send starts exactly where this
## one left off -- per agents/mob-selector-notes.md's worked example, this
## is what makes three consecutive 50% sends rotate [0,N/2) -> [N/2,N) ->
## [0,N/2) instead of always re-picking the same slice.
func _take_ring_slice(count: int) -> Array:
	var total: int = recruited.size()
	var slice: Array = []
	for i in range(count):
		slice.append(recruited[(_send_pointer + i) % total])
	_send_pointer = (_send_pointer + count) % total
	return slice


## Clears the active attack target once it's destroyed, so recruited NPCs
## stop dealing damage to a freed node and a new Send Mob command is needed
## to pick the next target.
func _on_attack_target_destroyed() -> void:
	_attack_target = null


## Picks a random point within `radius` of `center`, per vision.md's
## "generate distributed destination positions inside an area around the
## selected point" -- deliberately simple (uniform disc) for this first
## pass. Exists as a single seam to swap in per-destination-type point
## generators later (bus/plaza/road/barricade) without touching callers.
func _scatter_point(center: Vector3, radius: float) -> Vector3:
	var angle: float = randf() * TAU
	var dist: float = sqrt(randf()) * radius
	return center + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
