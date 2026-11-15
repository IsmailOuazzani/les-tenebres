extends Control
class_name SnapFeed

## Snapchat-style live protest group-chat feed, per agents/snap-feed-notes.md.
## Purely cosmetic/flavor -- reads GameState signals to react to real
## events, but writes nothing back and has zero gameplay effect. All copy
## is canned (scripts/snap_feed_data.gd), no AI generation at runtime.

## How often the ambient ticker fires a fresh random message when nothing
## in particular just happened.
@export var min_interval: float = 2.0
@export var max_interval: float = 5.0

## Visible message cap -- oldest entries beyond this are faded out and
## freed as new ones arrive.
@export var max_visible: int = 6

## A real gameplay event also triggers a short burst of extra reaction
## messages from fictional users, staggered a little so it reads as a
## crowd reacting rather than a single canned line.
@export var burst_min: int = 2
@export var burst_max: int = 4
@export var burst_delay_min: float = 0.15
@export var burst_delay_max: float = 0.55

## Recruiting sweeps up every unrecruited civilian in the cone in the same
## physics frame (see CrowdController._process_recruit_cone), so a single
## hold can fire crowd_count_changed many times in a row. Recruits within
## this window of each other are collapsed into one message instead of one
## per NPC -- otherwise a big sweep floods the whole feed. See
## agents/snap-feed-notes.md.
@export var recruit_batch_window: float = 0.6

const _ITEM_SIZE := Vector2(0, 0)
const _AVATAR_SIZE := Vector2(28, 28)
const _BG_SYSTEM := Color(1.0, 0.988, 0.0, 0.92) ## Snapchat yellow banner
const _BG_USER := Color(0.08, 0.08, 0.1, 0.72)
const _FADE_MIN_ALPHA := 0.3

@onready var _list: VBoxContainer = %MessageList
@onready var _title: Label = %Title
@onready var _logo: Label = %Logo

var _rng := RandomNumberGenerator.new()
var _timer: float = 0.0
var _prev_crowd_count: int = 1
var _recruit_batch_pending: bool = false
var _recruit_batch_count: int = 0


func _ready() -> void:
	_rng.randomize()
	_style_panel()
	_style_header()
	_prev_crowd_count = GameState.crowd_count
	_reset_timer()

	GameState.crowd_count_changed.connect(_on_crowd_count_changed)
	GameState.disruption_recorded.connect(_on_disruption_recorded)
	GameState.police_defeated.connect(_on_police_defeated)


func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_reset_timer()
		_spawn_ambient_message()


func _reset_timer() -> void:
	_timer = _rng.randf_range(min_interval, max_interval)


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


## -- Ambient ticker: 20% gameplay flavor / 30% chatter / 50% nonsense -- ##

func _spawn_ambient_message() -> void:
	var roll: float = _rng.randf()
	if roll < 0.2:
		_push_system(SnapFeedData.random_gameplay_flavor(_rng, GameState.grabuge_available, GameState.crowd_count))
	elif roll < 0.5:
		_push_user(SnapFeedData.random_chatter(_rng), "ordinary")
	else:
		_push_user(SnapFeedData.random_nonsense(_rng), "funny")


## -- Real gameplay events: inject immediately + trigger a reaction burst -- ##

func _on_crowd_count_changed(new_value: int) -> void:
	if new_value > _prev_crowd_count:
		_recruit_batch_count += new_value - _prev_crowd_count
		if not _recruit_batch_pending:
			_recruit_batch_pending = true
			_flush_recruit_batch()
	_prev_crowd_count = new_value


## Collapses every recruit that landed within recruit_batch_window into a
## single message (no reaction burst -- recruiting is routine, not the
## kind of standout moment a burst should sell). Runs fire-and-forget from
## the first recruit in a batch; later recruits in the same window just
## bump _recruit_batch_count and ride along.
func _flush_recruit_batch() -> void:
	await get_tree().create_timer(recruit_batch_window).timeout
	if not is_instance_valid(self):
		return
	var gained: int = _recruit_batch_count
	_recruit_batch_count = 0
	_recruit_batch_pending = false
	if gained <= 0:
		return
	if gained == 1:
		_push_system(SnapFeedData.random_recruit_message(_rng, GameState.crowd_count), "ordinary")
	else:
		_push_system(SnapFeedData.random_recruit_batch_message(_rng, gained, GameState.crowd_count), "ordinary")


func _on_disruption_recorded(_total: int) -> void:
	_push_system(SnapFeedData.random_destruction_message(_rng, int(GameState.DISRUPTION_GRABUGE_BASE)), "")
	_spawn_burst()


func _on_police_defeated(grabuge_gain: float) -> void:
	_push_system(SnapFeedData.random_police_defeat_message(_rng, int(grabuge_gain)), "")
	_spawn_burst()


func _spawn_burst() -> void:
	var count: int = _rng.randi_range(burst_min, burst_max)
	for i in count:
		await get_tree().create_timer(_rng.randf_range(burst_delay_min, burst_delay_max)).timeout
		if not is_instance_valid(self):
			return
		if _rng.randf() < 0.5:
			_push_user(SnapFeedData.random_chatter(_rng), "ordinary")
		else:
			_push_user(SnapFeedData.random_nonsense(_rng), "funny")


## -- Message construction -- ##

## `kind` ("ordinary" / "funny" / "important") selects which notification
## pop plays -- see AudioManager.play_feed_notification(). Purely an audio
## tag; an empty kind keeps the message silent.
func _push_system(text: String, kind: String = "ordinary") -> void:
	_push_item(_build_system_item(text))
	if not kind.is_empty():
		AudioManager.play_feed_notification(kind)


func _push_user(text: String, kind: String = "ordinary") -> void:
	_push_item(_build_user_item(SnapFeedData.random_username(_rng), text))
	AudioManager.play_feed_notification(kind)


func _push_item(item: Control) -> void:
	_list.add_child(item)
	_list.move_child(item, 0)
	_animate_in(item)
	_trim_overflow()
	_refresh_fade()


func _build_system_item(text: String) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = _BG_SYSTEM
	style.set_corner_radius_all(10)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", style)

	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(0.05, 0.05, 0.05))
	panel.add_child(label)
	return panel


func _build_user_item(username: String, text: String) -> PanelContainer:
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

	row.add_child(_build_avatar())

	var text_box := VBoxContainer.new()
	text_box.add_theme_constant_override("separation", 0)
	text_box.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(text_box)

	var name_label := Label.new()
	name_label.text = username
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.add_theme_color_override("font_color", SnapFeedData.random_avatar_color(_rng))
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


func _build_avatar() -> PanelContainer:
	var avatar := PanelContainer.new()
	avatar.custom_minimum_size = _AVATAR_SIZE
	var style := StyleBoxFlat.new()
	style.bg_color = SnapFeedData.random_avatar_color(_rng)
	style.set_corner_radius_all(int(_AVATAR_SIZE.x / 2.0))
	avatar.add_theme_stylebox_override("panel", style)

	var label := Label.new()
	label.text = SnapFeedData.random_avatar_emoji(_rng)
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
