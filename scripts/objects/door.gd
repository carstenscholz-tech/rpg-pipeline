extends Area2D
class_name BuildingDoor
## A door that transitions the player to a building interior or another zone.

## Display name of the building (shown as notification on approach).
@export var building_name: String = "Building"
## Target scene path for the interior, or zone_id for zone transition.
@export var target_scene: String = ""
## Whether this is a zone transition (true) or interior transition (false).
@export var is_zone_transition: bool = false
## Entry direction when transitioning zones.
@export var entry_direction: String = ""
## Spawn point name inside the target scene.
@export var spawn_point_name: String = "DoorSpawn"

var _player_in_range: bool = false
var _label_shown: bool = false


func _ready() -> void:
	add_to_group("interactables")
	add_to_group("doors")

	connect("body_entered", _on_body_entered)
	connect("body_exited", _on_body_exited)


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_range = true
		if not _label_shown:
			EventBus.show_notification.emit("Press [E] to enter %s" % building_name)
			_label_shown = true


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_range = false
		_label_shown = false


func interact(_player: CharacterBody2D) -> void:
	if target_scene == "":
		EventBus.show_notification.emit("The door to %s is locked." % building_name)
		return

	if is_zone_transition:
		# Use ZoneManager for zone transitions.
		var zone_mgr := _find_zone_manager()
		if zone_mgr:
			zone_mgr.on_zone_transition(target_scene, entry_direction)
		else:
			push_warning("Door: Could not find ZoneManager for zone transition")
	else:
		# Interior transition (load scene directly).
		EventBus.show_notification.emit("Entering %s..." % building_name)
		# Interior scenes would be handled by a separate interior manager.
		# For now, emit a signal that other systems can listen to.
		EventBus.zone_entered.emit(target_scene)


func is_player_in_range() -> bool:
	return _player_in_range


func _find_zone_manager() -> Node:
	var world := get_tree().get_first_node_in_group("world")
	if world:
		var zm = world.get_node_or_null("ZoneManager")
		if zm and zm.has_method("on_zone_transition"):
			return zm
	return null
