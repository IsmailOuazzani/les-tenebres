extends Node

## AudioManager: centralized, event-based sound system for Protest Simulator.
##
## Registered as the `AudioManager` autoload (see project.godot [autoload]).
## Existing systems (Megaphone, CrowdController, GameState) call into this
## singleton by event name/helper function; they never touch audio nodes or
## asset paths directly. See agents/audio-notes.md for the full design doc,
## the asset manifest (source/license/attribution per clip), and the list of
## sound categories from the spec that are intentionally NOT implemented yet
## (Phases 2-4) -- those are left as commented TODOs below rather than
## silently dropped.
##
## Phase 1 ("core feedback") is fully implemented:
##   megaphone activation/static, recruitment feedback (individual + rapid
##   collective cheer), Send Mob hold-to-charge, À L'ATTAQUE, the collective
##   mob-charging roar (scaled with committed NPC count), and a basic
##   dynamic crowd-ambience layer driven by live crowd size + Grabuge.

# -- Exposed parameters (spec section 17) --
@export var master_volume: float = 1.0
@export var crowd_volume: float = 1.0
@export var voice_volume: float = 1.0
@export var sfx_volume: float = 1.0
@export var ui_volume: float = 1.0
@export var stinger_volume: float = 1.0

@export var max_simultaneous_voices: int = 10
@export var max_simultaneous_world_sfx: int = 16

## Per vision.md crowd-size design: thresholds used both for mob-roar
## layering and for the crowd-ambience density crossfade below.
@export var crowd_small_threshold: int = 10
@export var crowd_medium_threshold: int = 50
@export var crowd_large_threshold: int = 150

@export var recruitment_pitch_variation: float = 0.08
@export var recruitment_volume_variation_db: float = 3.0

## Rapid recruitment -> small collective cheer instead of N individual
## shouts, per spec section 3B.
@export var rapid_recruit_window_sec: float = 1.2
@export var rapid_recruit_count: int = 3

@export var megaphone_static_volume_db: float = -20.0
@export var megaphone_static_fade_sec: float = 0.35

@export var send_charge_retrigger_interval_sec: float = 0.45
@export var mob_charge_max_volume_db: float = -2.0

## How fast the crowd-ambience layer's target volume is approached each
## frame (just a lerp weight, not literal dB/sec).
@export var crowd_crossfade_speed: float = 1.5

# -- Sound registry (data-driven; swap files here, nothing else changes) --
# See agents/audio-notes.md for the manifest (source/license/attribution).
const SOUNDS: Dictionary = {
	"megaphone_click": preload("res://audio/megaphone/megaphone_click.wav"),
	"megaphone_static_loop": preload("res://audio/megaphone/megaphone_static_loop.ogg"),
	"charge_whistle": preload("res://audio/megaphone/charge_whistle.wav"),
	"attack_shout": preload("res://audio/megaphone/attack_shout_placeholder.wav"),
	"recruit_shout": preload("res://audio/recruitment/recruit_shout.wav"),
	"crowd_cheer_burst": preload("res://audio/crowd/cheers/crowd_cheer_burst.wav"),
	"mob_roar_burst": preload("res://audio/crowd/voices/mob_roar_burst.wav"),
	"crowd_ambience_protest": preload("res://audio/crowd/crowd_ambience_protest.ogg"),
}

## Events from the spec that are intentionally unimplemented this pass
## (Phases 2-4: barricades, vehicles, police combat, Grabuge
## fanfares/warnings, game over, feed notifications, target UI, cartoon
## physics). Logged once via push_warning the first time anything calls
## play_missing() for a given key, so gaps are visible instead of silent.
var _warned_missing: Dictionary = {}

# -- Pools --
var _voice_pool: Array[AudioStreamPlayer3D] = []
var _sfx_pool: Array[AudioStreamPlayer3D] = []

# -- Dedicated single-purpose players --
var _static_player: AudioStreamPlayer
var _charge_player: AudioStreamPlayer
var _attack_player: AudioStreamPlayer
var _crowd_ambience_player: AudioStreamPlayer

var _static_tween: Tween
var _send_charging: bool = false
var _send_retrigger_timer: float = 0.0

var _recruit_timestamps: Array[float] = []

var _crowd_controller: Node = null
var _crowd_ambience_target_db: float = -80.0


func _ready() -> void:
	_build_pools()
	_build_dedicated_players()
	GameState.disruption_recorded.connect(_on_disruption_recorded)


func _process(delta: float) -> void:
	_update_send_charge_retrigger(delta)
	_update_crowd_ambience(delta)


# ---------------------------------------------------------------------------
# Megaphone activation (spec 3A)
# ---------------------------------------------------------------------------

func start_megaphone_recruit() -> void:
	_play_one_shot_2d("megaphone_click", "SFX")
	_static_player.volume_db = -80.0
	if not _static_player.playing:
		_static_player.play()
	_tween_static_to(megaphone_static_volume_db)


func stop_megaphone_recruit() -> void:
	_tween_static_to(-80.0, func(): _static_player.stop())


func _tween_static_to(target_db: float, on_done: Callable = Callable()) -> void:
	if _static_tween:
		_static_tween.kill()
	_static_tween = create_tween()
	_static_tween.tween_property(_static_player, "volume_db", target_db, megaphone_static_fade_sec)
	if on_done.is_valid():
		_static_tween.tween_callback(on_done)


# ---------------------------------------------------------------------------
# Civilian recruitment (spec 3B)
# ---------------------------------------------------------------------------

## Called by CrowdController.npc_recruited (see scripts/crowd_controller.gd).
## Aggregates rapid recruitment into one collective cheer instead of N
## overlapping individual shouts.
func play_recruit_feedback(position: Vector3) -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	_recruit_timestamps.append(now)
	_recruit_timestamps = _recruit_timestamps.filter(func(t): return now - t <= rapid_recruit_window_sec)

	if _recruit_timestamps.size() >= rapid_recruit_count:
		_recruit_timestamps.clear()
		_play_one_shot_3d("crowd_cheer_burst", position, "Crowd", 1.0, 0.05)
		return

	_play_one_shot_3d("recruit_shout", position, "Voices", recruitment_volume_variation_db, recruitment_pitch_variation)


# ---------------------------------------------------------------------------
# Send Mob charge (spec 3C)
# ---------------------------------------------------------------------------

func start_send_charge() -> void:
	_send_charging = true
	_send_retrigger_timer = 0.0
	_update_send_charge(0.0)


## `percentage` is the live 0-1 commit ramp from Megaphone._current_send_percentage().
func update_send_charge(percentage: float) -> void:
	if not _send_charging:
		return
	_update_send_charge(percentage)


func stop_send_charge() -> void:
	_send_charging = false
	if _charge_player.playing:
		var t := create_tween()
		t.tween_property(_charge_player, "volume_db", -80.0, 0.1)
		t.tween_callback(_charge_player.stop)


func _update_send_charge(percentage: float) -> void:
	_charge_player.volume_db = lerp(-24.0, mob_charge_max_volume_db, percentage)
	_charge_player.pitch_scale = lerp(0.85, 1.6, percentage)


## Re-triggers the whistle one-shot on an interval that shortens as charge
## rises, so a single short sample reads as "building intensity" rather
## than one static loop -- per spec 3C's "increase pitch/intensity... do not
## repeatedly restart the sample" tension, resolved here by spacing retriggers
## far enough apart that they read as rhythm, not stutter.
func _update_send_charge_retrigger(delta: float) -> void:
	if not _send_charging:
		return
	_send_retrigger_timer -= delta
	if _send_retrigger_timer > 0.0:
		return
	var percentage: float = inverse_lerp(-24.0, mob_charge_max_volume_db, _charge_player.volume_db)
	var interval: float = lerp(send_charge_retrigger_interval_sec, send_charge_retrigger_interval_sec * 0.35, percentage)
	_send_retrigger_timer = interval
	if not _charge_player.playing:
		_charge_player.play()
	else:
		_charge_player.seek(0.0)


# ---------------------------------------------------------------------------
# À L'ATTAQUE + mob roar (spec 3D, 3E)
# ---------------------------------------------------------------------------

## NOTE: `attack_shout_placeholder.wav` is a generic male shout, NOT a French
## recording of "À L'ATTAQUE !" -- per the spec's own fallback instructions,
## a real voice line needs to be recorded; this is a clearly-labeled stand-in
## so the event/ducking/mixing pipeline is ready to swap it in later.
func play_attack_command() -> void:
	_duck_crowd_bus()
	_attack_player.play()


## `committed_count` is the number of NPCs this Send Mob command actually
## sent (CrowdController's post-ring-slice count), per spec 3E's "scale with
## the number of protesters actually receiving the command." Layers multiple
## slightly-varied copies of one scream clip rather than linear volume
## scaling, capped by max_simultaneous_voices.
func play_mob_roar(committed_count: int) -> void:
	if committed_count <= 0:
		return
	var layers: int
	if committed_count <= crowd_small_threshold:
		layers = 1
	elif committed_count <= crowd_medium_threshold:
		layers = 3
	elif committed_count <= crowd_large_threshold:
		layers = 5
	else:
		layers = 8
	layers = mini(layers, max_simultaneous_voices)

	var player_pos: Vector3 = Vector3.ZERO
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		player_pos = cam.global_transform.origin

	for i in range(layers):
		var offset := Vector3(randf_range(-2.0, 2.0), 0.0, randf_range(-2.0, 2.0))
		_play_one_shot_3d("mob_roar_burst", player_pos + offset, "Voices", 2.0, 0.12)


## Softens the Crowd bus briefly so the (Critical-priority) attack voice
## always reads over ambient crowd noise, per spec section 14.
func _duck_crowd_bus() -> void:
	var idx := AudioServer.get_bus_index("Crowd")
	if idx < 0:
		return
	var original_db: float = AudioServer.get_bus_volume_db(idx)
	AudioServer.set_bus_volume_db(idx, original_db - 8.0)
	var t := create_tween()
	t.tween_interval(0.5)
	t.tween_method(func(db: float): AudioServer.set_bus_volume_db(idx, db), original_db - 8.0, original_db, 0.4)


# ---------------------------------------------------------------------------
# Basic dynamic crowd layer (spec 4, Layer A -- Phase 1 scope only)
# ---------------------------------------------------------------------------

func _update_crowd_ambience(delta: float) -> void:
	if _crowd_controller == null:
		_crowd_controller = get_tree().get_first_node_in_group(&"crowd_controller")
		if _crowd_controller == null:
			return

	var count: int = _crowd_controller.get_recruited_count()
	var grabuge_ratio: float = GameState.grabuge / GameState.GRABUGE_MAX

	# Independent axes per spec 9C's worked examples: size drives how loud/
	# dense the layer can get; Grabuge drives how much of that ceiling is
	# actually reached right now.
	var size_ratio: float = clamp(float(count) / float(crowd_large_threshold), 0.0, 1.0)
	var presence: float = size_ratio * lerp(0.3, 1.0, grabuge_ratio)

	_crowd_ambience_target_db = lerp(-80.0, -6.0, presence) if count > 0 else -80.0
	_crowd_ambience_player.volume_db = lerp(
		_crowd_ambience_player.volume_db, _crowd_ambience_target_db, clamp(crowd_crossfade_speed * delta, 0.0, 1.0))

	if _crowd_ambience_player.volume_db > -79.0 and not _crowd_ambience_player.playing:
		_crowd_ambience_player.play()
	elif _crowd_ambience_player.volume_db <= -79.0 and _crowd_ambience_player.playing:
		_crowd_ambience_player.stop()


# ---------------------------------------------------------------------------
# Disruption feedback -- the one Phase-2 hook wired early since
# GameState.disruption_recorded already exists and the cheer asset is
# already on hand; everything else in Phase 2-4 is left as play_missing().
# ---------------------------------------------------------------------------

func _on_disruption_recorded(_total: int) -> void:
	var cam := get_viewport().get_camera_3d()
	var pos: Vector3 = cam.global_transform.origin if cam != null else Vector3.ZERO
	_play_one_shot_3d("crowd_cheer_burst", pos, "Crowd", 1.0, 0.08)


# ---------------------------------------------------------------------------
# Unimplemented-event reporting (spec section 2: "clearly identified
# missing assets rather than silently skipping the feature")
# ---------------------------------------------------------------------------

## Call sites for Phase 2-4 events that don't have assets/integration yet
## should call this instead of silently doing nothing. Not currently called
## anywhere (no Phase 2-4 integration points exist yet) -- kept here as the
## seam those phases should use. See agents/audio-notes.md for the full list
## (barricades, vehicles, police combat, cartoon physics, Grabuge
## gain/warning/collapse, game over, feed notifications, target UI).
func play_missing(event_key: String) -> void:
	if _warned_missing.has(event_key):
		return
	_warned_missing[event_key] = true
	push_warning("AudioManager: '%s' has no asset/integration yet (see agents/audio-notes.md)" % event_key)


# ---------------------------------------------------------------------------
# Pooling helpers
# ---------------------------------------------------------------------------

func _build_pools() -> void:
	for i in range(max_simultaneous_voices):
		var p := AudioStreamPlayer3D.new()
		p.bus = "Voices"
		p.max_distance = 40.0
		add_child(p)
		_voice_pool.append(p)
	for i in range(max_simultaneous_world_sfx):
		var p := AudioStreamPlayer3D.new()
		p.bus = "SFX"
		p.max_distance = 40.0
		add_child(p)
		_sfx_pool.append(p)


func _build_dedicated_players() -> void:
	_static_player = AudioStreamPlayer.new()
	_static_player.bus = "SFX"
	_static_player.stream = SOUNDS["megaphone_static_loop"]
	(_static_player.stream as AudioStreamOggVorbis).loop = true
	add_child(_static_player)

	_charge_player = AudioStreamPlayer.new()
	_charge_player.bus = "SFX"
	_charge_player.stream = SOUNDS["charge_whistle"]
	add_child(_charge_player)

	_attack_player = AudioStreamPlayer.new()
	_attack_player.bus = "Voices"
	_attack_player.stream = SOUNDS["attack_shout"]
	add_child(_attack_player)

	_crowd_ambience_player = AudioStreamPlayer.new()
	_crowd_ambience_player.bus = "Crowd"
	_crowd_ambience_player.stream = SOUNDS["crowd_ambience_protest"]
	(_crowd_ambience_player.stream as AudioStreamOggVorbis).loop = true
	_crowd_ambience_player.volume_db = -80.0
	add_child(_crowd_ambience_player)


func _play_one_shot_2d(sound_key: String, bus: String) -> void:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	p.stream = SOUNDS[sound_key]
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


func _play_one_shot_3d(sound_key: String, position: Vector3, bus: String, volume_variation_db: float, pitch_variation: float) -> void:
	var pool: Array[AudioStreamPlayer3D] = _voice_pool if bus == "Voices" else _sfx_pool
	var player: AudioStreamPlayer3D = _acquire_pooled(pool)
	if player == null:
		return
	player.bus = bus
	player.stream = SOUNDS[sound_key]
	player.global_position = position
	player.volume_db = randf_range(-volume_variation_db, volume_variation_db)
	player.pitch_scale = 1.0 + randf_range(-pitch_variation, pitch_variation)
	player.play()


## Round-robins through `pool`, preferring an idle player; if all are busy,
## steals the first one rather than growing the pool -- enforces the
## concurrency cap from spec section 15 instead of spawning new nodes.
func _acquire_pooled(pool: Array[AudioStreamPlayer3D]) -> AudioStreamPlayer3D:
	for p in pool:
		if not p.playing:
			return p
	return pool[0] if not pool.is_empty() else null
