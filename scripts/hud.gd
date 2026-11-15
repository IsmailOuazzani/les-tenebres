extends CanvasLayer

## Live HUD showing crowd count, Grabuge, player health, and (per
## agents/wave-survival-notes.md) the wave/Act survival loop. Crowd/Grabuge
## are driven entirely by the GameState autoload (see
## agents/grabuge-notes.md); health instead reads directly off the bound
## player's own HealthComponent, since health isn't global state the way
## Grabuge is. Wave state comes from the WaveManager autoload.

## ## Multiplayer
##
## The HUD is strictly **local**: each peer shows its own health, its own
## weapon hotbar and its own compass. Crowd count and Grabuge come from
## GameState, which is replicated shared state, so those read identically for
## everyone (spec 4.5).
##
## The player node is no longer at a fixed scene path -- player characters are
## spawned at runtime by a MultiplayerSpawner -- so instead of `player_path`
## style exports the match scene calls `bind_player()` with the locally owned
## character as soon as it exists. See scenes/test_map.gd.

@onready var _crowd_label: Label = %CrowdLabel
@onready var _grabuge_label: Label = %GrabugeLabel
@onready var _health_bar: ProgressBar = %HealthBar
@onready var _health_label: Label = %HealthLabel
@onready var _hotbar: HBoxContainer = %Hotbar
@onready var _compass_bar: TextureRect = %CompassBar
@onready var _compass_markers: Control = %CompassMarkers
@onready var _damage_flash: ColorRect = %DamageFlash
@onready var _fps_label: Label = %FpsLabel

@onready var _wave_label: Label = %WaveLabel
@onready var _wave_banner_anchor: CenterContainer = %WaveBannerAnchor
@onready var _wave_banner_label: Label = %WaveBannerLabel
@onready var _intermission_anchor: CenterContainer = %IntermissionAnchor
@onready var _intermission_label: Label = %IntermissionLabel
@onready var _threat_anchor: CenterContainer = %ThreatAnchor
@onready var _threat_label: Label = %ThreatLabel

## Tracks the player's last-seen health so _on_player_health_changed can
## tell a hit (health went down) apart from a HUD refresh or healing.
var _last_player_health: float = -1.0
var _damage_flash_tween: Tween

## Hotbar slot panels (and their two labels), one per weapon, in
## WeaponSwitcher's slot order -- built fresh in _ready() from
## WeaponSwitcher.get_weapon_names() so adding a weapon shows up
## automatically. Labels are tracked directly rather than looked up by node
## name/path, since the panel's children are created in code with
## auto-assigned names.
var _hotbar_slots: Array[PanelContainer] = []
var _hotbar_key_labels: Array[Label] = []
var _hotbar_name_labels: Array[Label] = []

const _SLOT_SIZE := Vector2(72, 72)

## Theme variant names baked into res://themes/main_theme.tres (Kenney UI
## Pack, CC0, via https://github.com/Kingsmai/kenney-ui-pack-starter-kit).
## See agents/hud-theme-notes.md.
const _SLOT_VARIANT_INACTIVE := &"PanelContainerDefaultFlat"
const _SLOT_VARIANT_ACTIVE := &"PanelContainerPrimaryFlat"
const _HEALTH_VARIANT_OK := &"ProgressBarSuccess"
const _HEALTH_VARIANT_LOW := &"ProgressBarWarning"
const _HEALTH_VARIANT_CRITICAL := &"ProgressBarDanger"

## How long the "WAVE N CLEARED" banner and the threat warning stay on
## screen before fading out.
const _WAVE_BANNER_DURATION: float = 2.5
const _THREAT_WARNING_DURATION: float = 3.0

var _wave_banner_tween: Tween
var _threat_tween: Tween


var _bound_player: Node3D = null


func _ready() -> void:
	GameState.crowd_count_changed.connect(_on_crowd_count_changed)
	GameState.grabuge_changed.connect(_on_grabuge_changed)

	_on_crowd_count_changed(GameState.crowd_count)
	_on_grabuge_changed(GameState.grabuge_available, GameState.grabuge_total_earned)


## True once `bind_player()` has run. Polled by the match scene, which can
## only bind after the player-spawn handshake completes.
func is_bound() -> bool:
	return _bound_player != null and is_instance_valid(_bound_player)


## Wires this HUD to the locally owned player character: health bar, weapon
## hotbar and compass. Called once per match by scenes/test_map.gd.
func bind_player(player: Node3D) -> void:
	if player == null or not is_instance_valid(player):
		return
	_bound_player = player

	var player_health: Node = player.get_node_or_null("HealthComponent")
	if player_health != null:
		player_health.health_changed.connect(_on_player_health_changed)
		_on_player_health_changed(player_health.current_health, player_health.max_health)

	var weapon_switcher: Node = player.get_node_or_null("Head/Camera/WeaponSwitcher")
	if weapon_switcher != null:
		_build_hotbar(weapon_switcher.get_weapon_names())
		weapon_switcher.weapon_switched.connect(_on_weapon_switched)
		_on_weapon_switched(weapon_switcher.get_active_index())

	_compass_bar.parent = player
	# CompassBar's own _ready() runs before ours (children ready bottom-up),
	# so it already saw `parent` as null and disabled its _physics_process --
	# re-enable it now that `parent` is set.
	_compass_bar.set_physics_process(true)
	_compass_markers.player = player

	# The run starts (scenes/test_map.gd -> WaveManager.start_run()) before
	# the local character exists, and on a client the wave arrives as
	# replicated state -- either way this binding happens after the first
	# wave_started signal. Connect for future transitions, then sync the
	# label by hand from WaveManager's current state.
	WaveManager.wave_started.connect(_on_wave_started)
	WaveManager.wave_completed.connect(_on_wave_completed)
	WaveManager.intermission_started.connect(_on_intermission_started)
	WaveManager.intermission_finished.connect(_on_intermission_finished)
	WaveManager.threat_warning.connect(_on_threat_warning)
	_sync_wave_label_from_current_state()


func _process(_delta: float) -> void:
	_fps_label.text = "%d FPS" % Engine.get_frames_per_second()
	_update_wave_timer()


func _on_crowd_count_changed(value: int) -> void:
	_crowd_label.text = "Protesters: %d" % value


## Grabuge is now an unbounded spendable currency, not a capped meter (see
## agents/wave-survival-notes.md), so a ProgressBar reading toward some max
## no longer makes sense -- just show both numbers as a plain readout: the
## spendable balance (what upgrades cost) prominently, and the lifetime
## total (what civilian spawn scaling reads) as a smaller aside.
func _on_grabuge_changed(available: float, total_earned: float) -> void:
	_grabuge_label.text = "⚡ %d  (earned %d)" % [round(available), round(total_earned)]


func _on_player_health_changed(current: float, max_value: float) -> void:
	_health_bar.max_value = max_value
	_health_bar.value = current
	_health_label.text = "Health: %d" % round(current)
	var ratio: float = current / max_value if max_value > 0.0 else 0.0
	if ratio <= 0.3:
		_health_bar.theme_type_variation = _HEALTH_VARIANT_CRITICAL
	elif ratio <= 0.6:
		_health_bar.theme_type_variation = _HEALTH_VARIANT_LOW
	else:
		_health_bar.theme_type_variation = _HEALTH_VARIANT_OK

	if _last_player_health >= 0.0 and current < _last_player_health:
		_flash_damage()
	_last_player_health = current


## Red screen-edge flash on taking damage (see scripts/damage_flash.gdshader).
func _flash_damage() -> void:
	var material: ShaderMaterial = _damage_flash.material
	if _damage_flash_tween:
		_damage_flash_tween.kill()
	material.set_shader_parameter("intensity", 0.6)
	_damage_flash_tween = create_tween()
	_damage_flash_tween.tween_property(material, "shader_parameter/intensity", 0.0, 0.35)


## Creates one square slot panel per weapon (key number + name, e.g. "1" /
## "Megaphone") under the Hotbar HBoxContainer. Each slot is a PanelContainer
## with its own StyleBoxFlat so the active slot's border/background can be
## swapped independently in _on_weapon_switched().
func _build_hotbar(weapon_names: Array[String]) -> void:
	for slot in _hotbar_slots:
		slot.queue_free()
	_hotbar_slots.clear()
	_hotbar_key_labels.clear()
	_hotbar_name_labels.clear()

	for i in weapon_names.size():
		var panel := PanelContainer.new()
		panel.custom_minimum_size = _SLOT_SIZE
		panel.theme_type_variation = _SLOT_VARIANT_INACTIVE

		var box := VBoxContainer.new()
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		box.add_theme_constant_override("separation", 2)
		panel.add_child(box)

		var key_label := Label.new()
		key_label.text = str(i + 1)
		key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		key_label.add_theme_font_size_override("font_size", 12)
		box.add_child(key_label)

		var name_label := Label.new()
		name_label.text = weapon_names[i]
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_label.add_theme_font_size_override("font_size", 13)
		box.add_child(name_label)

		_hotbar.add_child(panel)
		_hotbar_slots.append(panel)
		_hotbar_key_labels.append(key_label)
		_hotbar_name_labels.append(name_label)


func _on_weapon_switched(active_index: int) -> void:
	for i in _hotbar_slots.size():
		var active: bool = i == active_index
		_hotbar_slots[i].theme_type_variation = _SLOT_VARIANT_ACTIVE if active else _SLOT_VARIANT_INACTIVE
		_hotbar_key_labels[i].add_theme_font_size_override("font_size", 14 if active else 12)


## -- Wave survival HUD (agents/wave-survival-notes.md) --

## Called once from _ready() since WaveManager (an autoload) already
## started wave 1 before this HUD existed to catch the signal -- just read
## its current public state directly instead of waiting for an event.
func _sync_wave_label_from_current_state() -> void:
	_wave_banner_anchor.visible = false
	_threat_anchor.visible = false
	if WaveManager.state == WaveManager.State.INTERMISSION:
		_on_intermission_started(WaveManager.current_wave, WaveManager.wave_duration)
	else:
		_intermission_anchor.visible = false
		_wave_label.text = "Wave %d" % WaveManager.current_wave


## Ticks the visible "Wave N - MM:SS" / "Next wave in MM:SS" readout every
## frame off WaveManager's own wave_time_left -- cheaper than a dedicated
## Timer node, and keeps the HUD a pure read-only reflection of WaveManager.
func _update_wave_timer() -> void:
	var time_left: int = int(ceil(max(WaveManager.wave_time_left, 0.0)))
	var minutes: int = time_left / 60
	var seconds: int = time_left % 60

	match WaveManager.state:
		WaveManager.State.ACTIVE:
			_wave_label.text = "Wave %d  %d:%02d" % [WaveManager.current_wave, minutes, seconds]
		WaveManager.State.INTERMISSION:
			_intermission_label.text = _format_intermission_text(minutes, seconds)


func _format_intermission_text(minutes: int, seconds: int) -> String:
	var preview: Dictionary = WaveManager.get_next_wave_preview()
	var threat: String = "ASSAULT" if preview.get("assault", false) else "normal"
	return "Next: Wave %d (%s, ~%d police) in %d:%02d" % [
		preview.get("wave", WaveManager.current_wave + 1),
		threat,
		preview.get("police", 0),
		minutes,
		seconds,
	]


func _on_wave_started(wave_number: int, _police_total: int) -> void:
	_intermission_anchor.visible = false
	_wave_label.text = "Wave %d" % wave_number


func _on_wave_completed(wave_number: int) -> void:
	_wave_banner_label.text = "WAVE %d CLEARED" % wave_number
	_show_banner_once(_wave_banner_anchor, _wave_banner_tween, _WAVE_BANNER_DURATION)


func _on_intermission_started(next_wave_number: int, _duration: float) -> void:
	_intermission_anchor.visible = true
	_intermission_label.text = _format_intermission_text(0, 0)
	# Unused param kept for signal-shape clarity -- preview text pulls the
	# live countdown from WaveManager.wave_time_left every frame instead
	# (see _update_wave_timer()), since the countdown doesn't actually
	# start running until begin_intermission_countdown() is called by the
	# upgrade station (see agents/wave-survival-notes.md).
	_wave_label.text = "Wave %d cleared" % (next_wave_number - 1)


func _on_intermission_finished() -> void:
	_intermission_anchor.visible = false


func _on_threat_warning(message: String) -> void:
	_threat_label.text = message
	_show_banner_once(_threat_anchor, _threat_tween, _THREAT_WARNING_DURATION)


## Shared show-then-fade-then-hide helper for the wave-cleared banner and
## the threat warning -- both are "flash a message, then go away" UI with
## no persistent state once they expire.
func _show_banner_once(anchor: CanvasItem, tween: Tween, duration: float) -> void:
	if tween != null and is_instance_valid(tween):
		tween.kill()
	anchor.visible = true
	anchor.modulate.a = 1.0
	var new_tween: Tween = create_tween()
	new_tween.tween_interval(duration)
	new_tween.tween_property(anchor, "modulate:a", 0.0, 0.4)
	new_tween.tween_callback(func() -> void: anchor.visible = false)
	if anchor == _wave_banner_anchor:
		_wave_banner_tween = new_tween
	elif anchor == _threat_anchor:
		_threat_tween = new_tween
