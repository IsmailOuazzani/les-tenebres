extends RefCounted
class_name BloodBurst

## One-shot world-space blood splash on enemy hit, built on top of the
## MIT-licensed addons/blood_effect/node_3d.scn (see addons/blood_effect/LICENSE.txt).
## That scene is the vendor's own debug demo, not a drop-in gameplay node --
## besides a free-fly camera and a keyboard-driven control panel built in
## node_3d.gd's _ready() (never run here; spawn() nulls the script before
## adding the instance to the tree), it also ships its own test room
## (ground + 4 walls, ~18x8 units) and a duplicate WorldEnvironment/
## DirectionalLight3D baked into the .scn itself. Instancing it wholesale
## into gameplay dropped that entire room next to the player on every hit
## (the "huge box" bug) and duplicated lighting/environment, hence the
## slowdown. Fix: only the GPUParticles3D child survives -- everything else
## in the instance is freed immediately after spawning.
##
## The vendor's GPUParticles3D also ships with amount = 1 -- their demo's
## whole control panel exists to let the tester crank a live "Blood Amount"
## multiplier (up to 150x) on that one baseline particle; we don't use that
## panel, so without bumping `amount` ourselves a hit emits exactly one
## particle, easy to miss entirely mid-fight. _BURST_AMOUNT below is our own
## stand-in multiplier.

const _SCENE: PackedScene = preload("res://addons/blood_effect/node_3d.scn")
const _BURST_AMOUNT := 24

static func spawn(parent: Node, at: Vector3) -> void:
	var inst: Node3D = _SCENE.instantiate()
	inst.set_script(null)
	parent.add_child(inst)
	inst.global_position = at

	var particles: GPUParticles3D = inst.get_node("GPUParticles3D")
	for child in inst.get_children():
		if child != particles:
			child.queue_free()

	# In the vendor's own scene, GPUParticles3D sits ~4.7 units above (and
	# behind) their room's floor, positioned to rain down into it from
	# their orbiting debug camera's view. That local offset survives
	# reparenting, so without zeroing it the burst emits well above/behind
	# wherever `at` actually is.
	particles.position = Vector3.ZERO

	particles.amount = _BURST_AMOUNT
	particles.one_shot = true
	particles.emitting = false
	particles.restart()
	particles.emitting = true

	var tree: SceneTree = parent.get_tree()
	if tree:
		await tree.create_timer(particles.lifetime + 0.5).timeout
	if is_instance_valid(inst):
		inst.queue_free()
