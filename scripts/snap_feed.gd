extends Control
class_name SnapFeed

## Snapchat-style protest group chat. Gameplay events supply the subject and
## the local HUD controls which exchanges to show and how to pace them.

@export var max_visible: int = 6

## Recruits can arrive together on the host or over several state updates
## on clients. Collect them before deciding whether the sweep merits a post.
const _RECRUIT_BATCH_WINDOW := 0.6
const _MIN_RECRUIT_BATCH := 5
const _THREAD_INTERVAL := 5.0
const _REPLY_DELAY := 1.4

const _AVATAR_SIZE := Vector2(28, 28)
const _BG_USER := Color(0.08, 0.08, 0.1, 0.72)
const _FADE_MIN_ALPHA := 0.3

@onready var _list: VBoxContainer = %MessageList
@onready var _title: Label = %Title
@onready var _logo: Label = %Logo

var _rng := RandomNumberGenerator.new()
var _last_prop_thread: Dictionary = {}
var _prev_crowd_count: int
var _recruit_batch_count: int = 0
var _recruit_batch_wait: float = 0.0
var _thread_wait: float = 0.0
var _reply_wait: float = 0.0
var _reply: Array = []
var _callback: Array = []
var _callback_ready: bool = false


func _ready() -> void:
	_rng.randomize()
	_style_panel()
	_style_header()
	_prev_crowd_count = GameState.crowd_count

	GameState.crowd_count_changed.connect(_on_crowd_count_changed)
	GameState.disruption_recorded.connect(_on_disruption_recorded)
	GameState.first_megacop_spawned.connect(_on_first_megacop_spawned)
	WaveManager.intermission_countdown_started.connect(_on_intermission_countdown_started)
	WaveManager.act_completed.connect(_on_act_completed)


func _process(delta: float) -> void:
	_thread_wait = maxf(_thread_wait - delta, 0.0)

	if _reply_wait > 0.0:
		_reply_wait -= delta
		if _reply_wait <= 0.0:
			_push_user(_reply)
			_reply = []

	if _callback_ready and _thread_wait <= 0.0:
		_push_user(_callback)
		_clear_callback()
		_thread_wait = _THREAD_INTERVAL

	if _recruit_batch_wait > 0.0:
		_recruit_batch_wait -= delta
		if _recruit_batch_wait <= 0.0:
			_flush_recruit_batch()


func _style_panel() -> void:
	var panel: PanelContainer = $Panel
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.03, 0.05, 0.55)
	style.set_corner_radius_all(14)
	style.set_border_width_all(2)
	style.border_color = Color(1.0, 0.988, 0.0, 0.55)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(300, 0)


func _style_header() -> void:
	_logo.add_theme_font_size_override("font_size", 20)
	_title.add_theme_font_size_override("font_size", 15)
	_title.add_theme_color_override("font_color", Color(1.0, 0.988, 0.0))


func _on_crowd_count_changed(new_value: int) -> void:
	var gained := new_value - _prev_crowd_count
	_prev_crowd_count = new_value
	if gained <= 0:
		return
	if _recruit_batch_wait <= 0.0:
		_recruit_batch_wait = _RECRUIT_BATCH_WINDOW
	_recruit_batch_count += gained


func _flush_recruit_batch() -> void:
	var gained := _recruit_batch_count
	_recruit_batch_count = 0
	if gained < _MIN_RECRUIT_BATCH or _thread_wait > 0.0:
		return

	var thread: Array = _pick_thread(SnapFeedData.RECRUIT_THREADS)
	var opener: Array = thread[0]
	_start_thread([[opener[0], opener[1] % gained], thread[1]])


func _on_disruption_recorded(_total: int, feed_topic: StringName) -> void:
	if _thread_wait > 0.0 or not SnapFeedData.PROP_THREADS.has(feed_topic):
		return
	var threads: Array = SnapFeedData.PROP_THREADS[feed_topic]
	var index := _rng.randi_range(0, threads.size() - 1)
	if index == _last_prop_thread.get(feed_topic, -1):
		index = (index + 1) % threads.size()
	_last_prop_thread[feed_topic] = index
	_start_thread(threads[index])


func _on_first_megacop_spawned() -> void:
	# This only happens once per run. Give it the slot even if a routine
	# exchange was already underway.
	_start_thread(_pick_thread(SnapFeedData.MEGACOP_THREADS))


func _pick_thread(threads: Array) -> Array:
	return threads[_rng.randi_range(0, threads.size() - 1)]


func _on_intermission_countdown_started() -> void:
	_callback_ready = not _callback.is_empty()


func _on_act_completed(_act: int) -> void:
	_clear_callback()


func _clear_callback() -> void:
	_callback = []
	_callback_ready = false


func _start_thread(thread: Array) -> void:
	_push_user(thread[0])
	_reply = thread[1]
	_reply_wait = _REPLY_DELAY
	_thread_wait = _THREAD_INTERVAL
	if thread.size() == 3 and _callback.is_empty():
		_callback = thread[2]


func _push_user(post: Array) -> void:
	var username: String = post[0]
	var message: String = post[1]
	var profile: Dictionary = SnapFeedData.PROFILES[username]
	_push_item(_build_user_item(username, message, profile))
	AudioManager.play_feed_notification("ordinary")


func _push_item(item: Control) -> void:
	_list.add_child(item)
	_list.move_child(item, 0)
	_animate_in(item)
	_trim_overflow()
	_refresh_fade()


func _build_user_item(username: String, text: String, profile: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = _BG_USER
	style.set_corner_radius_all(10)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	panel.add_child(row)

	row.add_child(_build_avatar(profile))

	var text_box := VBoxContainer.new()
	text_box.add_theme_constant_override("separation", 0)
	text_box.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(text_box)

	var name_label := Label.new()
	name_label.text = username
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.add_theme_color_override("font_color", profile["color"])
	text_box.add_child(name_label)

	var msg_label := Label.new()
	msg_label.text = text
	msg_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg_label.add_theme_font_size_override("font_size", 13)
	msg_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	text_box.add_child(msg_label)

	var timestamp := Label.new()
	timestamp.text = Time.get_time_string_from_system().substr(0, 5)
	timestamp.add_theme_font_size_override("font_size", 10)
	timestamp.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 0.7))
	timestamp.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	row.add_child(timestamp)

	return panel


func _build_avatar(profile: Dictionary) -> PanelContainer:
	var avatar := PanelContainer.new()
	avatar.custom_minimum_size = _AVATAR_SIZE
	var style := StyleBoxFlat.new()
	style.bg_color = profile["color"]
	style.set_corner_radius_all(int(_AVATAR_SIZE.x / 2.0))
	avatar.add_theme_stylebox_override("panel", style)

	var label := Label.new()
	label.text = profile["emoji"]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 14)
	avatar.add_child(label)
	return avatar


## -- Animation / lifecycle -- ##

## Only slides the item in -- fade-in to its target opacity is handled by
## _refresh_fade() right after, so the two don't fight over modulate:a.
func _animate_in(item: Control) -> void:
	item.modulate.a = 0.0
	item.position.x = -24.0
	var tween := create_tween()
	tween.tween_property(item, "position:x", 0.0, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Oldest entries (bottom of the list, since new ones are inserted at the
## top) are freed once the visible count exceeds max_visible. By the time
## an item reaches the bottom it's already been dimmed near-transparent by
## _refresh_fade()'s gradient on prior pushes, so dropping it here (instead
## of a separate fade-then-free tween) reads as the same "fade out" effect
## without a second tween fighting _refresh_fade() over modulate:a.
func _trim_overflow() -> void:
	var children := _list.get_children()
	while children.size() > max_visible:
		var oldest: Node = children[children.size() - 1]
		children.remove_at(children.size() - 1)
		oldest.queue_free()


## Gives older (further down) messages a dimmer look, per the spec's
## "older messages fade out" -- a static alpha gradient rather than a
## continuous per-frame fade, recomputed each time the list changes.
func _refresh_fade() -> void:
	var children := _list.get_children()
	var count: int = children.size()
	if count <= 1:
		return
	for i in count:
		var target_alpha: float = lerp(1.0, _FADE_MIN_ALPHA, float(i) / float(count - 1))
		var item: Control = children[i]
		var tween := create_tween()
		tween.tween_property(item, "modulate:a", target_alpha, 0.3)
