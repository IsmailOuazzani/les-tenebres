@tool
extends EditorPlugin

## Only CompassBar is vendored here (Compass2D/Compass3D from upstream were
## dropped since this project only needs the HUD bar) -- see
## agents/compass-hud-notes.md.
var icon = preload("res://addons/compass/icon.png")
var compassbar = preload("res://addons/compass/entities/compassbar.gd")


func _enter_tree():
	add_custom_type("CompassBar", "TextureRect", compassbar, icon)


func _exit_tree():
	remove_custom_type("CompassBar")
