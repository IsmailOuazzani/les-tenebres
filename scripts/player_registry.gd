class_name PlayerRegistry

## Static lookups over the live player characters, keyed off the &"player"
## group that scripts/player.gd joins in `_ready()`.
##
## Single-player and multiplayer both go through here, so gameplay systems
## (crowd recruitment, police targeting, spawner anchoring) never need to
## know how many players exist or which peer owns them -- they just ask for
## "all players" or "the nearest player". Replaces the old single
## `player_path` NodePath exports those systems used when there was exactly
## one player node at a fixed scene path.
##
## Deliberately a static utility rather than another autoload: it owns no
## state, it just wraps `get_tree().get_nodes_in_group()`.

const GROUP: StringName = &"player"


## Every player character currently in the tree, local and remote, alive or
## respawning. `node` is any node in the tree (used only to reach SceneTree).
static func all(node: Node) -> Array[Node3D]:
	var result: Array[Node3D] = []
	if node == null or not node.is_inside_tree():
		return result
	for player in node.get_tree().get_nodes_in_group(GROUP):
		if is_instance_valid(player) and player is Node3D:
			result.append(player)
	return result


## Players that are currently valid targets: in the tree and not waiting out
## a respawn. Police targeting and "nearest player" anchoring use this so a
## dead player stops drawing aggro.
static func alive(node: Node) -> Array[Node3D]:
	var result: Array[Node3D] = []
	for player in all(node):
		if player.has_method(&"is_alive") and not player.is_alive():
			continue
		result.append(player)
	return result


## The player character this peer owns (multiplayer authority), or null if it
## has not spawned yet. In single-player this is simply the only player.
static func local(node: Node) -> Node3D:
	for player in all(node):
		if player.is_multiplayer_authority():
			return player
	return null


## Nearest living player to `position`, or null if nobody is alive.
static func nearest(node: Node, position: Vector3) -> Node3D:
	var best: Node3D = null
	var best_dist: float = INF
	for player in alive(node):
		var dist: float = player.global_position.distance_squared_to(position)
		if dist < best_dist:
			best_dist = dist
			best = player
	return best


## A living player to anchor spawning around, picked at random so police and
## civilians don't all trickle in around the same peer. Falls back to null
## when every player is down.
static func random_alive(node: Node) -> Node3D:
	var candidates: Array[Node3D] = alive(node)
	if candidates.is_empty():
		return null
	return candidates[randi() % candidates.size()]
