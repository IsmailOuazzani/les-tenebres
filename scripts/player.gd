extends MovementController
class_name NetPlayer

## Networked first-person player character. Root script of
## scenes/player.tscn, which instances the vendored
## addons/fps_controller/Player.tscn and adds the replication nodes -- so the
## addon's movement/look/weapon code stays untouched apart from the
## `is_multiplayer_authority()` input guards.
##
## Network ownership (see agents/multiplayer-notes.md):
##   * Movement and look        -> owning client (client-authoritative)
##   * Health, death, respawn   -> server
##
## Two MultiplayerSynchronizers back that split, because one synchronizer can
## only have one authority:
##   * `InputSync`  authority = owning peer. Replicates the owner's transform
##     snapshot, head pitch, animation state and recruit-held flag outward.
##   * `ServerSync` authority = 1 (the listen server). Replicates health and
##     alive/dead back to everyone.
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

@onready var health: HealthComponent = $HealthComponent
@onready var _head: Node3D = $Head
@onready var _camera: Camera3D = $Head/Camera
@onready var _megaphone: Megaphone = $Head/Camera/Megaphone
@onready var _croissant: Croissant = $Head/Camera/Croissant
@onready var _body: Node3D = $Body
@onready var _collision: CollisionShape3D = $Collision

var _body_anim: AnimationPlayer
var _last_applied_anim: int = -1
## Set by scenes/test_map.gd on the server while a respawn timer is running.
var _respawning: bool = false


## Authority is derived from the node name, which the spawn function sets to
## the owning peer id -- the standard Godot pattern, and the reason the name
## has to be deterministic across peers. Recursive by default, so Head,
## Megaphone, Croissant, Sprint and InputSync all inherit it; ServerSync and
## HealthComponent are pushed back to the server in `_ready()`.
func _enter_tree() -> void:
	set_multiplayer_authority(name.to_int())


func _ready() -> void:
	add_to_group(PlayerRegistry.GROUP)

	# Server owns health and the alive/dead flag regardless of who drives
	# movement.
	$ServerSync.set_multiplayer_authority(1)
	health.set_multiplayer_authority(1)

	_body_anim = _body.get_node_or_null("Character/AnimationPlayer")
	net_position = position
	net_body_yaw = rotation.y
	net_health = health.max_health

	if is_multiplayer_authority():
		_setup_local()
	else:
		_setup_remote()

	health.health_changed.connect(_on_health_changed)


## Local player: first-person. Its own third-person body is hidden so it
## doesn't fill the camera, and the megaphone routes its commands through
## this script.
func _setup_local() -> void:
	_camera.current = true
	_body.visible = false
	_megaphone.send_mob_triggered.connect(_on_send_mob_triggered)


## Remote player: a visible 3D character with no camera, no input handling
## and no first-person viewmodel/HUD overlay of its own. The weapon nodes are
## deactivated (which hides their CanvasLayer HUD, invisible to Node3D
## visibility) and then frozen so their `_unhandled_input` never fires.
func _setup_remote() -> void:
	_camera.current = false
	_body.visible = true
	_megaphone.deactivate()
	_croissant.deactivate()
	_megaphone.process_mode = Node.PROCESS_MODE_DISABLED
	_croissant.process_mode = Node.PROCESS_MODE_DISABLED
	$Head.process_mode = Node.PROCESS_MODE_DISABLED
	$Sprint.process_mode = Node.PROCESS_MODE_DISABLED
	$Head/Camera/WeaponSwitcher.process_mode = Node.PROCESS_MODE_DISABLED


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
	return net_alive and net_recruiting


## Radius of this player's megaphone recruitment circle, read server-side.
func get_recruit_radius() -> float:
	return _megaphone.recruit_radius


# --------------------------------------------------------------------------
# Health / death / respawn (server-authoritative)
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
	position = spawn_position
	net_position = spawn_position
	velocity = Vector3.ZERO
