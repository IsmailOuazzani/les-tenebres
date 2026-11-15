extends WorldEnvironment

const SKIES: Array[Texture2D] = [
	preload("res://assets/soviet_decay_skies/clear_summer_day.png"),
	preload("res://assets/soviet_decay_skies/thunderstorm.png"),
	preload("res://assets/soviet_decay_skies/nuclear_winter_ash.png"),
	preload("res://assets/soviet_decay_skies/blood_sky_black_sun.png"),
]
const SUN_COLORS: Array[Color] = [
	Color(1.0, 0.937, 0.835), Color(0.75, 0.82, 0.94),
	Color(0.83, 0.78, 0.71), Color(1.0, 0.66, 0.51),
]
const SUN_ENERGIES: Array[float] = [1.2, 0.5, 0.4, 0.5]
const AMBIENT_COLORS: Array[Color] = [
	Color(0.78, 0.86, 1.0), Color(0.72, 0.78, 0.89),
	Color(0.78, 0.74, 0.7), Color(0.79, 0.74, 0.78),
]

@export var sun: DirectionalLight3D
@onready var _ash: GPUParticles3D = $Ash

var _displayed_act: int = 0


func _ready() -> void:
	WaveManager.act_completed.connect(_on_act_completed)
	WaveManager.wave_started.connect(_on_wave_started)
	_apply_atmosphere(1)


func _on_act_completed(act: int) -> void:
	if act == 1:
		_apply_atmosphere(2)


func _on_wave_started(wave: int, _police_total: int) -> void:
	if wave != 1:
		return
	var act := WaveManager.current_act
	_apply_atmosphere(act)
	if act == 2:
		AudioManager.play_act_thunder()


func _apply_atmosphere(act: int) -> void:
	var index := clampi(act, 1, SKIES.size()) - 1
	if _displayed_act == index + 1:
		return
	_displayed_act = index + 1

	var panorama := environment.sky.sky_material as PanoramaSkyMaterial
	panorama.panorama = SKIES[index]
	# Aim the black sun down the north-south streets and lift it clear of roofs.
	var eclipse_orientation := Basis(Vector3.RIGHT, deg_to_rad(8.0)) * Basis(Vector3.UP, -PI / 2.0)
	environment.sky_rotation = eclipse_orientation.get_euler() if _displayed_act == 4 else Vector3.ZERO
	sun.light_color = SUN_COLORS[index]
	sun.light_energy = SUN_ENERGIES[index]
	environment.ambient_light_color = AMBIENT_COLORS[index]

	var ashfall := _displayed_act == 3
	environment.fog_enabled = ashfall
	environment.fog_light_color = Color(0.54, 0.51, 0.47)
	environment.fog_density = 0.009
	get_tree().call_group(&"act_streetlights", &"set_visible", _displayed_act >= 3)
	_ash.visible = ashfall
	if ashfall:
		_update_ash_position()
	_ash.emitting = ashfall
	set_process(ashfall)


func _process(_delta: float) -> void:
	_update_ash_position()


func _update_ash_position() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		_ash.global_position = camera.global_position + Vector3.UP * 5.0
