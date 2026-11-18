extends MovementController
class_name NetPlayer

## Networked first-person player character. Root script of
## scenes/player.tscn, which instances the vendored
## addons/fps_controller/Player.tscn and adds replication and class abilities.
##
## Network ownership (see agents/multiplayer-notes.md):
##   * Movement and look        -> owning client (client-authoritative)
##   * Health, armor, death, respawn -> server
##
## Two MultiplayerSynchronizers back that split, because one synchronizer can
## only have one authority:
##   * `InputSync`  authority = owning peer. Replicates the owner's transform
##     snapshot, head pitch, animation state and recruit-held flag outward.
##   * `ServerSync` authority = 1 (the listen server). Replicates health,
##     armor and alive/dead back to everyone.
##
## Remote players are rendered from `Body` (a Quaternius character) driven by
## the replicated animation state, and their transform is **interpolated**
## toward the latest snapshot rather than snapped, so a 30 Hz transform
## stream still reads as smooth motion.
##
## In single-player there is no multiplayer peer at all: authority defaults
## to peer 1 everywhere, `is_multiplayer_authority()` is trivially true, and
## every replication path below is skipped. Existing single-player behavior
## is unchanged.

## Animation states replicated to remote peers (ints, not strings, so they
## fit in an on-change delta packet). Mapped to Quaternius clip names by
## `_ANIM_NAMES`.
enum Anim { IDLE, WALK, RUN, PUNCH_LEFT, PUNCH_RIGHT }

const _ANIM_NAMES: Array[StringName] = [
	&"Idle", &"Walk", &"Run", &"Punch_Left", &"Punch_Right",
]

## How fast a remote player's rendered transform chases its latest replicated
## snapshot (exponential smoothing factor per second). Tuned so a 30 Hz
## stream looks continuous without feeling laggy.
const INTERP_SPEED: float = 18.0
## Snapshot further than this from the rendered position is treated as a
## teleport (respawn, map reset) and snapped instead of interpolated.
const INTERP_SNAP_DISTANCE: float = 4.0

## Horizontal speed above which a remote player is animated as running
## rather than walking.
const RUN_SPEED_THRESHOLD: float = 11.0

# --- Replicated by InputSync (authority = owning client) ------------------
## Transform snapshot the owner publishes; remote peers interpolate toward it.
@export var net_position: Vector3 = Vector3.ZERO
@export var net_body_yaw: float = 0.0
@export var net_head_pitch: float = 0.0
@export var net_anim: int = Anim.IDLE
## True while the owner holds the megaphone recruit input. The server polls
## this (via `is_recruiting()`) to run shared-crowd recruitment for every
## player, local or remote -- see scripts/crowd_controller.gd.
@export var net_recruiting: bool = false

# --- Replicated by ServerSync (authority = 1, the listen server) ----------
## Replicated health. Mirrored straight into the local HealthComponent from
## the setter rather than polled in `_process`, so it keeps arriving while the
## tree is paused (the game-over screen pauses everything, and a paused node
## stops processing but synchronizers keep delivering -- found via the
## headless loopback test).
@export var net_health: float = 100.0:
	set(value):
		net_health = value
		if NetworkManager.is_client() and is_node_ready():
			health.set_replicated_health(value)
@export var net_alive: bool = true
@export var net_armor: float = 0.0:
	set(value):
		net_armor = value
		if NetworkManager.is_client() and is_node_ready():
			health.armor = value

@onready var health: HealthComponent = $HealthComponent
@onready var _head: Node3D = $Head
@onready var _camera: Camera3D = $Head/Camera
@onready var _megaphone: Megaphone = $Head/Camera/Megaphone
@onready var _body: Node3D = $Body
@onready var _collision: CollisionShape3D = $Collision

var kit: int = PlayerClass.Kit.SOLO
var _base_max_health: float
var _weapon_slot: int = 0
var _cooldowns: Dictionary[int, int] = {}

var _body_anim: AnimationPlayer
var _last_applied_anim: int = -1
## Set by scenes/test_map.gd on the server while a respawn timer is running.
var _respawning: bool = false


## Authority is derived from the node name, which the spawn function sets to
## the owning peer id -- the standard Godot pattern, and the reason the name
## has to be deterministic across peers. Recursive by default, so Head,
## the weapons, Sprint and InputSync all inherit it; ServerSync and
## HealthComponent are pushed back to the server in `_ready()`.
func _enter_tree() -> void:
	var peer_id := name.to_int()
	set_multiplayer_authority(peer_id)
	kit = NetworkManager.get_player_kit(peer_id)


func _ready() -> void:
	add_to_group(PlayerRegistry.GROUP)

	# Server owns health, armor and the alive/dead flag regardless of who drives
	# movement.
	$ServerSync.set_multiplayer_authority(1)
	health.set_multiplayer_authority(1)

	extra_jumps = 1 if kit == PlayerClass.Kit.SCOUT else 0
	_megaphone.can_send = can_send_mob()
	_megaphone.can_recruit = can_recruit()
	for ability in PlayerClass.abilities(kit):
		if PlayerClass.ability_slot(ability) != 0:
			continue
		if PlayerClass.ability_is_left_click(ability):
			_megaphone.left_ability = ability
		else:
			_megaphone.right_ability = ability

	net_position = position
	net_body_yaw = rotation.y
	_base_max_health = health.max_health
	health.max_health += UpgradeManager.player_bonus_health
	if NetworkManager.is_authoritative():
		health.current_health = health.max_health
		net_health = health.max_health

	if is_multiplayer_authority():
		_setup_local()
	else:
		_setup_remote()

	health.health_changed.connect(_on_health_changed)
	health.armor_changed.connect(_on_armor_changed)
	if NetworkManager.is_client():
		health.armor = net_armor


## Local player: first-person. Its own third-person body is hidden so it
## doesn't fill the camera, and the megaphone routes its commands through
## this script.
func _setup_local() -> void:
	_camera.current = true
	_body.visible = false
	_megaphone.send_mob_triggered.connect(_on_send_mob_triggered)


## Remote player: a visible 3D character with no camera, no input handling
## and no first-person viewmodels. WeaponSwitcher deactivates the weapons
## on remote players and disabling Head also disables its children.
func _setup_remote() -> void:
	_camera.current = false
	var character := PlayerClass.outfit(kit).instantiate() as Node3D
	character.name = "Character"
	character.rotation.y = PI
	_body.add_child(character)
	_body_anim = character.get_node_or_null("AnimationPlayer")
	_body.visible = true
	$Head.process_mode = Node.PROCESS_MODE_DISABLED
	$Sprint.process_mode = Node.PROCESS_MODE_DISABLED


## Freezes/unfreezes this character's own input and movement, used by
## scripts/pause_menu.gd for the local-only pause that a networked session
## needs (see agents/multiplayer-notes.md's "nothing pauses the tree in a
## networked session" rule -- get_tree().paused would freeze every player,
## not just the one who opened the menu). PROCESS_MODE_DISABLED propagates to
## every child (Head, Sprint, weapons, WeaponSwitcher), so this
## also stops their _unhandled_input/_physics_process the same way
## _setup_remote() already does for a remote-owned character above.
func set_input_locked(locked: bool) -> void:
	if locked:
		_megaphone.cancel_actions()
		net_recruiting = false
	process_mode = Node.PROCESS_MODE_DISABLED if locked else Node.PROCESS_MODE_INHERIT


func _physics_process(delta: float) -> void:
	if is_multiplayer_authority():
		if net_alive:
			# The vendored controller reads Input and runs move_and_slide().
			super._physics_process(delta)
		else:
			velocity = Vector3.ZERO
		_publish_snapshot()
	else:
		_interpolate_snapshot(delta)

	_update_body_animation()


## Owner -> wire. Writes the snapshot properties InputSync replicates. Note
## the owner publishes its *own* authoritative transform; it never reads
## net_position back.
func _publish_snapshot() -> void:
	net_position = position
	net_body_yaw = rotation.y
	net_head_pitch = _head.rotation.x
	net_recruiting = _megaphone.is_recruiting_held()
	net_anim = _compute_anim()


## Wire -> remote render. Exponential smoothing toward the latest snapshot
## (client-side interpolation), with a snap guard for teleports. Remote
## players run no physics at all -- their bodies are positioned, not
## simulated, so only the owning client's simulation can ever disagree with
## itself.
func _interpolate_snapshot(delta: float) -> void:
	var weight: float = clamp(delta * INTERP_SPEED, 0.0, 1.0)
	if position.distance_to(net_position) > INTERP_SNAP_DISTANCE:
		position = net_position
	else:
		position = position.lerp(net_position, weight)
	rotation.y = lerp_angle(rotation.y, net_body_yaw, weight)
	_head.rotation.x = lerp_angle(_head.rotation.x, net_head_pitch, weight)
	velocity = Vector3.ZERO


func _compute_anim() -> int:
	var horizontal_speed: float = Vector2(velocity.x, velocity.z).length()
	if horizontal_speed <= 0.2:
		return Anim.IDLE
	if horizontal_speed >= RUN_SPEED_THRESHOLD:
		return Anim.RUN
	return Anim.WALK


## Drives the third-person body clip from `net_anim`. Runs on every peer
## (including the owner, whose own body is hidden but still animated, so a
## future third-person/spectator view needs no extra wiring).
func _update_body_animation() -> void:
	if _body_anim == null:
		return
	if net_anim == _last_applied_anim:
		return
	_last_applied_anim = net_anim
	var clip: StringName = _ANIM_NAMES[clampi(net_anim, 0, _ANIM_NAMES.size() - 1)]
	if _body_anim.has_animation(clip):
		_body_anim.play(clip)


# --------------------------------------------------------------------------
# Gameplay command routing (client -> server)
# --------------------------------------------------------------------------

## The megaphone fires this locally on the owning client. Crowd commands are
## server-authoritative and apply to the single shared crowd, so the command
## is forwarded to the server's CrowdController rather than applied locally.
## Targets are addressed by absolute scene path: destructible props live in
## the statically-loaded map scene and police are spawned by the server's
## MultiplayerSpawner, so the same path resolves on every peer.
func _on_send_mob_triggered(percentage: float, target: Node3D, point: Vector3) -> void:
	if not can_issue_mob_order():
		return
	var crowd: Node = get_tree().get_first_node_in_group(&"crowd_controller")
	if crowd == null:
		return
	var target_path: String = ""
	if target != null and is_instance_valid(target):
		target_path = String(target.get_path())

	if NetworkManager.is_authoritative():
		crowd.apply_send_mob(percentage, target_path, point)
	else:
		crowd.rpc_id(1, "request_send_mob", percentage, target_path, point)


## True while this player holds the recruit input. Polled server-side by
## CrowdController for every player in the session.
func is_recruiting() -> bool:
	return net_alive and net_recruiting and can_recruit() and _weapon_slot == 0


## Radius of this player's megaphone recruitment circle, read server-side.
func get_recruit_radius() -> float:
	return _megaphone.recruit_radius


func can_send_mob() -> bool:
	return kit == PlayerClass.Kit.SOLO or kit == PlayerClass.Kit.MENEUR


func can_recruit() -> bool:
	return kit == PlayerClass.Kit.SOLO or kit == PlayerClass.Kit.SCOUT


func can_issue_mob_order() -> bool:
	return can_send_mob() and is_alive() and _weapon_slot == 0


func can_use_melee(weapon_name: StringName) -> bool:
	if not is_alive() or _weapon_slot == 0:
		return false
	match kit:
		PlayerClass.Kit.SCOUT: return weapon_name == &"Baguette"
		PlayerClass.Kit.MENEUR: return weapon_name == &"Croissant"
		PlayerClass.Kit.MEDIC: return weapon_name == &"ProtestSign"
	return (weapon_name == &"Croissant" and _weapon_slot == 1) \
		or (weapon_name == &"Baguette" and _weapon_slot == 2)


func publish_weapon_slot(slot: int) -> void:
	_weapon_slot = slot
	if NetworkManager.is_client():
		_receive_weapon_slot.rpc_id(1, slot)


@rpc("any_peer", "call_remote", "reliable")
func _receive_weapon_slot(slot: int) -> void:
	if NetworkManager.is_host() and multiplayer.get_remote_sender_id() == get_multiplayer_authority():
		_weapon_slot = clampi(slot, 0, 1)


func get_cooldown_seconds(ability: int) -> int:
	var remaining: int = _cooldowns.get(ability, 0) - Time.get_ticks_msec()
	return ceili(maxi(0, remaining) / 1000.0)


func use_class_ability(ability: int) -> void:
	if not is_multiplayer_authority() or not is_alive() or get_cooldown_seconds(ability) > 0:
		return
	var direction := -_camera.global_basis.z if ability == PlayerClass.Ability.CROISSANT_SHOT else Vector3.ZERO
	if NetworkManager.is_host():
		_activate_ability(ability, direction)
	elif NetworkManager.is_client():
		_request_ability.rpc_id(1, ability, direction)


@rpc("any_peer", "call_remote", "reliable")
func _request_ability(ability: int, direction: Vector3) -> void:
	if NetworkManager.is_host() and multiplayer.get_remote_sender_id() == get_multiplayer_authority():
		_activate_ability(ability, direction)


func _activate_ability(ability: int, direction: Vector3) -> void:
	if not is_alive() or ability not in PlayerClass.abilities(kit):
		return
	if _weapon_slot != PlayerClass.ability_slot(ability) or get_cooldown_seconds(ability) > 0:
		return
	var abilities := get_tree().get_first_node_in_group(&"class_abilities") as ClassAbilities
	if abilities == null:
		return
	var cooldown_msec := abilities.activate(self, ability, direction)
	if cooldown_msec <= 0:
		return
	_cooldowns[ability] = Time.get_ticks_msec() + cooldown_msec
	if not is_multiplayer_authority():
		_receive_cooldown.rpc_id(get_multiplayer_authority(), ability, cooldown_msec)


@rpc("any_peer", "call_remote", "reliable")
func _receive_cooldown(ability: int, cooldown_msec: int) -> void:
	if _sent_by_server() and is_multiplayer_authority():
		_cooldowns[ability] = Time.get_ticks_msec() + cooldown_msec


## The host tracks upgraded max health for every teammate so Heal can use
## the same authoritative cap for local and remote players.
func apply_health_upgrade() -> void:
	health.max_health = _base_max_health + UpgradeManager.player_bonus_health
	if NetworkManager.is_authoritative():
		health.heal(UpgradeManager.PLAYER_HEALTH_STEP)
	else:
		health.set_replicated_health(net_health)


func get_shot_origin() -> Vector3:
	return _camera.global_position if is_multiplayer_authority() else net_position + _head.position


# --------------------------------------------------------------------------
# Health / armor / death / respawn (server-authoritative)
# --------------------------------------------------------------------------

func is_alive() -> bool:
	return net_alive


func is_respawning() -> bool:
	return _respawning


## Server-side: HealthComponent changed. Mirrors the value into the
## replicated property so clients (and the owner's HUD) see it.
func _on_health_changed(current: float, _max_value: float) -> void:
	if NetworkManager.is_authoritative():
		net_health = current


func _on_armor_changed(current: float) -> void:
	if NetworkManager.is_authoritative():
		net_armor = current


## True when the RPC currently being handled came from the listen server (or
## is a local call on the server itself).
func _sent_by_server() -> bool:
	var sender: int = multiplayer.get_remote_sender_id()
	return sender == 1 or (sender == 0 and NetworkManager.is_authoritative())


## Server-side: take this player out of play (hidden, no collision, no
## input-driven movement) while the respawn timer runs.
func server_set_down() -> void:
	net_alive = false
	_respawning = true
	_apply_down_state.rpc()


## Server-side: put the player back in play at `spawn_position` with full
## health. The teleport is applied on every peer (including the owner, whose
## client-authoritative position would otherwise immediately overwrite it).
func server_respawn(spawn_position: Vector3) -> void:
	_respawning = false
	net_alive = true
	health.revive()
	net_health = health.current_health
	_apply_respawn.rpc(spawn_position)


## Hides the third-person body and drops the collider. Deliberately does NOT
## touch the root node's `visible`, which would also deactivate the local
## player's Camera3D and black out their screen while they wait to respawn.
##
## NOTE the `any_peer` + explicit sender check instead of `authority`: this
## node's multiplayer authority is the *owning client* (movement is
## client-authoritative), but death and respawn are server decisions. An
## `@rpc("authority")` method here would be rejected on arrival, because the
## receiving peer would expect the sender to be the character's owner rather
## than the server.
@rpc("any_peer", "call_local", "reliable")
func _apply_down_state() -> void:
	if not _sent_by_server():
		return
	net_alive = false
	net_recruiting = false
	_megaphone.cancel_actions()
	_body.visible = false
	_collision.disabled = true
	velocity = Vector3.ZERO


@rpc("any_peer", "call_local", "reliable")
func _apply_respawn(spawn_position: Vector3) -> void:
	if not _sent_by_server():
		return
	net_alive = true
	_body.visible = not is_multiplayer_authority()
	_collision.disabled = false
	_air_jumps_used = 0
	position = spawn_position
	net_position = spawn_position
	velocity = Vector3.ZERO
