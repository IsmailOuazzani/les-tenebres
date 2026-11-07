extends Node

# Rotating soundtrack. Scans res://assets/audio/music/ at runtime and plays
# the tracks found there in shuffled order, looping back around when the
# playlist runs out. That folder is gitignored (not committed to this public
# repo) — see agents/soundtrack-notes.md for how to (re)populate it locally.

const MUSIC_DIR := "res://assets/audio/music/"

@onready var player: AudioStreamPlayer = AudioStreamPlayer.new()

var playlist: Array[String] = []
var playlist_index := 0


func _ready() -> void:
	add_child(player)
	player.bus = "Master"
	player.finished.connect(_on_track_finished)
	_build_playlist()
	if not playlist.is_empty():
		_play_index(0)


func _build_playlist() -> void:
	playlist.clear()
	var dir := DirAccess.open(MUSIC_DIR)
	if dir == null:
		push_warning("MusicPlayer: no music folder found at %s (expected if you haven't run the yt-dlp download step locally)" % MUSIC_DIR)
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and _is_audio_file(file_name):
			playlist.append(MUSIC_DIR + file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	playlist.shuffle()


func _is_audio_file(file_name: String) -> bool:
	var lower := file_name.to_lower()
	return lower.ends_with(".opus") or lower.ends_with(".ogg") or lower.ends_with(".mp3") or lower.ends_with(".wav")


func _play_index(index: int) -> void:
	playlist_index = index
	var stream: AudioStream = load(playlist[playlist_index])
	player.stream = stream
	player.play()


func _on_track_finished() -> void:
	if playlist.is_empty():
		return
	playlist_index += 1
	if playlist_index >= playlist.size():
		playlist.shuffle()
		playlist_index = 0
	_play_index(playlist_index)
