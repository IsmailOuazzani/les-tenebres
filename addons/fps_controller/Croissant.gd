extends Node3D
class_name Croissant

## First-person croissant melee weapon.
##
## Click swings it; the hit lands when the swing reaches its downward peak
## (not instantly on click) and damages whatever is inside HitArea at that
## moment -- no hold-to-charge,
## no recruiting, just bonk. A click is ignored while a swing is already in
## progress, so mashing the button doesn't restart the animation or land
## extra hits. Switching between this and Megaphone is owned by
## WeaponSwitcher.gd (see WeaponSwitcher.gd), which calls
## activate()/deactivate() below; Croissant never decides when it's equipped
## on its own.
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
## The model here is a placeholder (bent primitive meshes, same spirit as
## npc.gd's capsule+sphere civilians) -- swap VisualRoot/CroissantModel for a
## real asset (e.g. Kenney's CC0 Food Kit) whenever one's on hand.

@export var hit_damage := 15.0
@export var swing_duration := 0.22

@onready var visual_root: Node3D = $VisualRoot
@onready var crumb_burst: CPUParticles3D = $VisualRoot/CrumbBurst
@onready var hit_area: Area3D = $HitArea

var _is_active: bool = false
var _rest_rotation: Vector3
var _swing_tween: Tween


func _ready() -> void:
	_rest_rotation = visual_root.rotation
	visual_root.visible = _is_active


func _unhandled_input(event: InputEvent) -> void:
	if not _is_active:
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

	_swing_tween = create_tween()
	var swing_rot := _rest_rotation + Vector3(deg_to_rad(-40), deg_to_rad(-12), deg_to_rad(18))
	_swing_tween.tween_property(visual_root, "rotation", swing_rot, swing_duration * 0.4)
	_swing_tween.tween_callback(_try_hit)
	_swing_tween.tween_property(visual_root, "rotation", _rest_rotation, swing_duration * 0.6)


## Damages everything currently inside HitArea. Damage targeting mirrors
## police.gd/npc.gd: hit a HealthComponent child if there is one
## (player/police/protester), otherwise call take_damage() on the body
## directly (destructible props).
func _try_hit() -> void:
	var hit_any := false
	for body in hit_area.get_overlapping_bodies():
		var health: HealthComponent = body.get_node_or_null("HealthComponent")
		if health:
			health.take_damage(hit_damage)
			hit_any = true
		elif body.has_method("take_damage"):
			body.take_damage(hit_damage)
			hit_any = true

	if hit_any:
		crumb_burst.restart()
		crumb_burst.emitting = true
