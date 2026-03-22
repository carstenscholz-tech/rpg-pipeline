extends Node
class_name ZoneManager
## Manages scene transitions between world zones.
## Handles fade effects, player positioning, and zone lifecycle.

signal transition_started(from_zone: String, to_zone: String)
signal transition_finished(zone_id: String)

const FADE_DURATION: float = 0.5

## Map of zone_id -> packed scene path.
var zone_scenes: Dictionary = {
	"hearthholm": "res://scenes/world/hearthholm.tscn",
	"oldroot_forest": "res://scenes/world/oldroot_forest.tscn",
}

## Currently loaded zone node.
var current_zone: Node2D = null
## Current zone identifier.
var current_zone_id: String = ""
## Whether a transition is in progress.
var _transitioning: bool = false

## Reference to the parent that holds zone nodes (set by world.gd).
var zone_container: Node2D = null
## Reference to the fade overlay (CanvasLayer > ColorRect).
var fade_overlay: ColorRect = null
## Reference to the player node.
var player: CharacterBody2D = null


func _ready() -> void:
	pass


## Load a zone by its identifier and place the player at a spawn point.
## entry_direction: the direction the player is coming FROM (e.g. "south" means
## the player enters from the south edge). If empty, uses zone default spawn.
func change_zone(zone_id: String, entry_direction: String = "") -> void:
	if _transitioning:
		return
	if zone_id == current_zone_id and current_zone != null:
		return
	if zone_id not in zone_scenes:
		push_warning("ZoneManager: Unknown zone '%s'" % zone_id)
		return

	_transitioning = true
	var old_zone_id := current_zone_id
	transition_started.emit(old_zone_id, zone_id)

	# Freeze player during transition.
	if player and player.has_method("freeze"):
		player.freeze()

	# Fade out.
	await _fade_out()

	# Remove old zone.
	if current_zone:
		current_zone.queue_free()
		current_zone = null

	# Load new zone.
	var scene_path: String = zone_scenes[zone_id]
	var scene_resource := load(scene_path) as PackedScene
	if not scene_resource:
		push_error("ZoneManager: Failed to load scene '%s'" % scene_path)
		_transitioning = false
		return

	current_zone = scene_resource.instantiate() as Node2D
	current_zone_id = zone_id

	if zone_container:
		zone_container.add_child(current_zone)
	else:
		push_error("ZoneManager: zone_container not set")
		_transitioning = false
		return

	# Position the player at the correct entry point.
	_position_player(zone_id, entry_direction)

	# Emit zone entered signal.
	EventBus.zone_entered.emit(zone_id)

	# Fade in.
	await _fade_in()

	# Unfreeze player.
	if player and player.has_method("unfreeze"):
		player.unfreeze()

	_transitioning = false
	transition_finished.emit(zone_id)


## Place the player at the correct spawn/entry position for the given zone.
func _position_player(zone_id: String, entry_direction: String) -> void:
	if not player:
		return

	# Try to find a matching entry marker in the zone scene.
	if entry_direction != "":
		var marker_name := "Entry_" + entry_direction
		var marker := _find_marker(current_zone, marker_name)
		if marker:
			player.global_position = marker.global_position
			return

	# Fall back to data-driven spawn point.
	var map_data: Dictionary = GameData.get_map(zone_id)
	if not map_data.is_empty():
		var sp: Dictionary = map_data.get("spawn_point", {})
		if sp.has("x") and sp.has("y"):
			# Map data positions are in tile coords; multiply by tile size.
			player.global_position = Vector2(
				float(sp.x) * 32.0 + 16.0,
				float(sp.y) * 32.0 + 16.0
			)
			return

	# Final fallback: center of zone.
	player.global_position = Vector2(400, 300)


## Recursively search for a Marker2D by name.
func _find_marker(node: Node, marker_name: String) -> Marker2D:
	if node is Marker2D and node.name == marker_name:
		return node as Marker2D
	for child in node.get_children():
		var found := _find_marker(child, marker_name)
		if found:
			return found
	return null


## Fade the screen to black.
func _fade_out() -> void:
	if not fade_overlay:
		return
	var tween := create_tween()
	fade_overlay.visible = true
	fade_overlay.modulate.a = 0.0
	tween.tween_property(fade_overlay, "modulate:a", 1.0, FADE_DURATION)
	await tween.finished


## Fade the screen from black.
func _fade_in() -> void:
	if not fade_overlay:
		return
	var tween := create_tween()
	tween.tween_property(fade_overlay, "modulate:a", 0.0, FADE_DURATION)
	await tween.finished
	fade_overlay.visible = false


## Called by zone transition areas when the player enters them.
func on_zone_transition(target_zone: String, entry_direction: String) -> void:
	change_zone(target_zone, entry_direction)
