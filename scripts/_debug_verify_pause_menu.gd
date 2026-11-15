extends SceneTree

## One-off check for the pause-menu feature: boots the real test_map in
## single-player, confirms PauseMenu is actually in the live tree (not just
## parsed), opens/closes it via the real Escape action, and checks
## get_upgrades()'s new current_value field. Run:
##   godot --path . --headless --script res://scripts/_debug_verify_pause_menu.gd

var _booted: bool = false
var _elapsed: float = 0.0
var _phase: int = 0


func _initialize() -> void:
	pass


func _boot() -> void:
	root.get_node("NetworkManager").begin_single_player_session()
	root.add_child(load("res://scenes/test_map.tscn").instantiate())


func _process(delta: float) -> bool:
	if not _booted:
		_booted = true
		_boot()
		return false

	_elapsed += delta
	if _elapsed > 20.0:
		print("!!! ABORT: stalled in phase ", _phase)
		return true

	match _phase:
		0:
			if _elapsed > 0.5:
				print("mouse mode right after boot (test_map sets CAPTURED in _ready): ", Input.get_mouse_mode())
				var pause_menu: Node = root.get_node_or_null("TestMap/PauseMenu")
				print("PauseMenu node present: ", pause_menu != null)
				print("PauseMenu process_mode (3=ALWAYS): ", pause_menu.process_mode if pause_menu else "n/a")
				print("PauseMenu visible before open: ", pause_menu.visible if pause_menu else "n/a")
				print("tree paused before open: ", paused)

				# Simulate the real Escape keypress rather than calling a
				# private method directly, so this also proves the input
				# action wiring (ui_cancel -> _unhandled_input) actually works.
				var ev := InputEventAction.new()
				ev.action = &"ui_cancel"
				ev.pressed = true
				Input.parse_input_event(ev)
				_phase = 1
		1:
			# Give the input event a frame to propagate.
			if _elapsed > 0.6:
				var pause_menu: Node = root.get_node_or_null("TestMap/PauseMenu")
				print("PauseMenu visible after Escape: ", pause_menu.visible)
				print("tree paused after open (single-player, expect true): ", paused)
				print("mouse mode after open (expect VISIBLE=0): ", Input.get_mouse_mode())

				print("\n--- upgrade current_value readout ---")
				var um: Node = root.get_node("UpgradeManager") if root.has_node("UpgradeManager") else Engine.get_singleton("UpgradeManager")
				_phase = 2
				return false
		2:
			# UpgradeManager is an autoload singleton; access it the same way
			# gameplay scripts do (bare global name resolves at parse time, but
			# this harness has no static type to call it on, so look it up by
			# node path under root instead).
			var um: Node = root.get_node_or_null("UpgradeManager")
			root.get_node("GameState").add_grabuge(500.0)
			for upgrade in um.get_upgrades():
				print(upgrade["id"], " level=", upgrade["level"], " current=", upgrade["current_value"])
			um.purchase(&"player_speed")
			um.purchase(&"player_speed")
			for upgrade in um.get_upgrades():
				if upgrade["id"] == &"player_speed":
					print("after 2 purchases -> ", upgrade["current_value"])

			# Now close the pause menu the same way the Resume button does.
			var pause_menu: Node = root.get_node_or_null("TestMap/PauseMenu")
			pause_menu.close()
			print("\nPauseMenu visible after close: ", pause_menu.visible)
			print("tree paused after close (expect false): ", paused)
			print("mouse mode after close (expect CAPTURED=2, headless has no display so this may stay VISIBLE): ", Input.get_mouse_mode())

			print("\n--- set_input_locked on the local player ---")
			var player: Node = root.get_node_or_null("TestMap/Players/1")
			print("player found: ", player != null)
			print("process_mode before lock (0=INHERIT): ", player.process_mode)
			player.set_input_locked(true)
			print("process_mode after lock (3=DISABLED): ", player.process_mode)
			player.set_input_locked(false)
			print("process_mode after unlock (0=INHERIT): ", player.process_mode)

			print("\n--- upgrade screen still builds cards with the new label ---")
			var shop: Node = root.get_node_or_null("TestMap/UpgradeScreen")
			shop.open(2)
			print("shop visible: ", shop.visible)
			shop.close()
			return true
	return false
