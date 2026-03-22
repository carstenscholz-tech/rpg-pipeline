extends Node2D
## Scene script for Hearthholm starter town.
## Handles zone transition triggers and local scene setup.


func _ready() -> void:
	# Place signs at key locations.
	_setup_signs()


## Called when a body enters the north gate transition zone.
func _on_north_gate_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		var zone_mgr := _get_zone_manager()
		if zone_mgr:
			zone_mgr.on_zone_transition("oldroot_forest", "south")


## Called when a body enters the south gate transition zone.
func _on_south_gate_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		# South leads to Millbrook Farm (not yet implemented).
		EventBus.show_notification.emit("The road south leads to Millbrook Farm. (Coming soon)")


## Called when a body enters the east gate transition zone.
func _on_east_gate_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		# East leads to Goblin Warrens.
		EventBus.show_notification.emit("The eastern path leads to the Goblin Warrens. You feel uneasy. (Coming soon)")


func _get_zone_manager() -> Node:
	var world := get_tree().get_first_node_in_group("world")
	if world:
		var zm = world.get_node_or_null("ZoneManager")
		if zm and zm.has_method("on_zone_transition"):
			return zm
	return null


func _setup_signs() -> void:
	var signs_container := get_node_or_null("Signs")
	if not signs_container:
		return

	# Town square sign.
	_create_sign(signs_container, Vector2(1520, 1200),
		"Town Square", "Welcome to Hearthholm!\nThe Adventurers Guild Hall is to the north.\nThe Sleeping Gryphon Inn is to the west.")

	# North gate sign.
	_create_sign(signs_container, Vector2(1488, 128),
		"North Gate", "CAUTION: Oldroot Forest beyond this gate.\nDangerous creatures reported. Level 3+ recommended.")

	# Guild hall sign.
	_create_sign(signs_container, Vector2(1424, 656),
		"Adventurers Guild", "Adventurers Guild Hall\nNew recruits welcome! Speak to Guildmaster Rowan.")

	# Blacksmith sign.
	_create_sign(signs_container, Vector2(928, 976),
		"Ironbark's Arms", "Thorgrim Ironbark - Master Smith\nWeapons, Armor, and Repairs")

	# General store sign.
	_create_sign(signs_container, Vector2(1824, 976),
		"Marta's General Store", "Marta's General Store\nSupplies for every adventure!")

	# Inn sign.
	_create_sign(signs_container, Vector2(672, 1456),
		"The Sleeping Gryphon", "The Sleeping Gryphon Inn\nFine food, warm beds, cold ale.")

	# Training yard sign.
	_create_sign(signs_container, Vector2(464, 1776),
		"Training Yard", "Combat Training Yard\nSpeak to Kira for lessons.")

	# Shrine sign.
	_create_sign(signs_container, Vector2(1504, 1600),
		"Shrine of the Ancients", "Shrine of the Ancients\nHealing and blessings available.\nBrother Aldwin presides.")


func _create_sign(parent: Node2D, pos: Vector2, title: String, text: String) -> void:
	var sign_scene := load("res://scenes/objects/sign.tscn") as PackedScene
	if not sign_scene:
		return
	var sign_instance := sign_scene.instantiate()
	sign_instance.position = pos
	if "sign_title" in sign_instance:
		sign_instance.sign_title = title
	if "sign_text" in sign_instance:
		sign_instance.sign_text = text
	parent.add_child(sign_instance)
