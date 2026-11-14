extends SceneTree

## Debug: verify AudioManager autoload wiring + Phase 1 event calls run
## without error. Run via `task run-headless`-style invocation:
##   Godot --headless --script res://scripts/_debug_verify_audio.gd
## Not part of gameplay; delete once Phase 1 audio is verified stable.

var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run()
	return false


func _run() -> void:
	var audio_mgr: Node = get_root().get_node_or_null("AudioManager")
	print("AudioManager autoload present: ", audio_mgr != null)
	if audio_mgr == null:
		quit(1)
		return

	print("Bus count: ", AudioServer.bus_count)
	for i in range(AudioServer.bus_count):
		print("  bus ", i, " = ", AudioServer.get_bus_name(i))

	print("-- triggering events --")
	audio_mgr.start_megaphone_recruit()
	audio_mgr.play_recruit_feedback(Vector3.ZERO)
	audio_mgr.play_recruit_feedback(Vector3.ZERO)
	audio_mgr.play_recruit_feedback(Vector3.ZERO)
	audio_mgr.start_send_charge()
	audio_mgr.update_send_charge(0.5)
	audio_mgr.stop_send_charge()
	audio_mgr.play_attack_command()
	audio_mgr.play_mob_roar(3)
	audio_mgr.play_mob_roar(30)
	audio_mgr.play_mob_roar(200)
	audio_mgr.stop_megaphone_recruit()
	print("-- no errors thrown --")
	quit(0)
