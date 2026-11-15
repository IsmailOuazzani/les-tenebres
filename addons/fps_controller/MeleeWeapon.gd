extends Node3D
class_name MeleeWeapon

## Shared first-person melee swing for Croissant and Baguette.
##
## Click swings it; the hit lands when the swing reaches its downward peak
## (not instantly on click) and damages whatever is inside HitArea at that
## moment -- no hold-to-charge,
## no recruiting, just bonk. A click is ignored while a swing is already in
## progress, so mashing the button doesn't restart the animation or land
## extra hits. Baguette extends this weapon to reuse its swing, viewmodel
## setup, and client-to-server hit routing.
##
## Damage targeting mirrors police.gd/npc.gd's melee pattern: look for a
## child named "HealthComponent" (player/police/protester) and hit that, or
## fall back to calling take_damage() on the collider itself (destructible
## props, which carry their own health). No group-membership check -- same
## reach as everything else that fights in this game.
##
## Hit detection is a fixed Area3D (HitArea, a sphere in front of the
## camera) rather than a raycast -- a raycast has to be aimed exactly at a
## target's collision shape (easy to whiff by inches, e.g. a horizontal ray
## at eye height clearing a shorter target entirely), while an overlap
## check over a volume is forgiving about exactly where on the target it
## lands.
##
@export var hit_damage := 15.0
@export var swing_duration := 0.22
@export var swing_rotation_degrees := Vector3(-40, -12, 18)

@onready var visual_root: Node3D = $VisualRoot
@onready var crumb_burst: CPUParticles3D = $VisualRoot/CrumbBurst
@onready var hit_area: Area3D = $HitArea

@onready var _wielder := get_node("../../..") as NetPlayer

var _is_active: bool = false
var _rest_rotation: Vector3
var _swing_tween: Tween


func _ready() -> void:
	_rest_rotation = visual_root.rotation
	visual_root.visible = _is_active


## How far from the attacking player the server will still accept a
## client-reported melee hit. The overlap test itself runs on the attacker
## (the HitArea only exists meaningfully where the swing is simulated), so
## the server re-checks range before applying damage -- "trusted client melee
## with a server-side range check", which is proportionate for LAN co-op. See
## agents/multiplayer-notes.md.
const SERVER_HIT_RANGE: float = 4.0


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if not _is_active or (_wielder != null and not _wielder.is_alive()):
		return
	if event.is_action_pressed(&"primary_action") and not _is_swinging():
		_play_swing()


## Called by WeaponSwitcher.gd when the player equips this weapon.
func activate() -> void:
	_is_active = true
	visual_root.visible = true


## Called by WeaponSwitcher.gd when the player switches away from this
## weapon.
func deactivate() -> void:
	_is_active = false
	if _swing_tween:
		_swing_tween.kill()
	visual_root.rotation = _rest_rotation
	visual_root.visible = false


func _is_swinging() -> bool:
	return _swing_tween != null and _swing_tween.is_running()


## Quick downward-forward chop and back, mirroring the raise/shake shape
## Megaphone._play_raise_shake() uses for its own click feedback. The hit
## check fires at the bottom of the chop (via tween_callback) rather than
## on click, so it lands when the croissant is actually pointed at the
## target instead of a frame before the swing even starts.
func _play_swing() -> void:
	if _swing_tween:
		_swing_tween.kill()

	_swing_tween = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	var swing_rot := _rest_rotation + swing_rotation_degrees * (PI / 180.0)
	_swing_tween.tween_property(visual_root, "rotation", swing_rot, swing_duration * 0.4)
	_swing_tween.tween_callback(_try_hit)
	_swing_tween.tween_property(visual_root, "rotation", _rest_rotation, swing_duration * 0.6)


## Resolves the swing on the attacking client: collects everything currently
## inside HitArea, plays the local cosmetic feedback, and hands the hit list
## to the server to actually apply damage (damage is server-authoritative).
## Targets are addressed by absolute scene path, which resolves identically
## on every peer -- props are part of the statically loaded map scene and
## NPCs/police are spawned by the server's MultiplayerSpawners.
func _try_hit() -> void:
	var target_paths: Array[String] = []
	for body in hit_area.get_overlapping_bodies():
		if body.get_node_or_null("HealthComponent") == null and not body.has_method("take_damage"):
			continue
		target_paths.append(String(body.get_path()))
		if body is Node3D:
			BloodBurst.spawn(get_tree().current_scene, body.global_position + Vector3.UP * 0.9)

	if not target_paths.is_empty():
		_play_crumb_burst()

	_submit_hit(target_paths)


func _play_crumb_burst() -> void:
	crumb_burst.restart()
	crumb_burst.emitting = true


func _submit_hit(target_paths: Array[String]) -> void:
	if NetworkManager.is_authoritative():
		_apply_equipped_hit(target_paths)
	else:
		rpc_id(1, "_request_hit", target_paths)


@rpc("any_peer", "call_remote", "reliable")
func _request_hit(target_paths: Array) -> void:
	if not NetworkManager.is_authoritative():
		return
	# Only the peer that owns this weapon may swing it.
	if multiplayer.get_remote_sender_id() != get_multiplayer_authority():
		return
	_apply_equipped_hit(target_paths)


func _apply_equipped_hit(target_paths: Array) -> void:
	if _wielder != null and not _wielder.can_use_melee(name):
		return
	_apply_hit(target_paths)


## Server-side damage application. Damage targeting mirrors police.gd/npc.gd:
## hit a HealthComponent child if there is one (player/police/protester),
## otherwise call take_damage() on the body directly (destructible props).
func _apply_hit(target_paths: Array) -> void:
	var attacker_position: Vector3 = global_position
	for path in target_paths:
		var body: Node = get_node_or_null(NodePath(String(path)))
		if body == null or not is_instance_valid(body):
			continue
		if body is Node3D and body.global_position.distance_to(attacker_position) > SERVER_HIT_RANGE:
			continue
		var health: HealthComponent = body.get_node_or_null("HealthComponent")
		if health != null:
			health.take_damage(hit_damage)
		elif body.has_method("take_damage"):
			body.take_damage(hit_damage)
