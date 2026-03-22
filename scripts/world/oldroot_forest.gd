extends Node2D
## Scene script for the Oldroot Forest zone.
## Handles zone transitions, chest spawning, and local setup.


func _ready() -> void:
	_setup_chests()
	_setup_signs()


## South exit leads back to Hearthholm.
func _on_south_exit_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		var zone_mgr := _get_zone_manager()
		if zone_mgr:
			zone_mgr.on_zone_transition("hearthholm", "north")


## East exit leads to Goblin Warrens (not yet implemented).
func _on_east_exit_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		EventBus.show_notification.emit("The path leads deeper into goblin territory. (Coming soon)")


## North exit is blocked for now.
func _on_north_exit_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		EventBus.show_notification.emit("The forest grows impossibly dense. You cannot pass. (Level 10+ area)")


func _get_zone_manager() -> ZoneManager:
	var world := get_tree().get_first_node_in_group("world")
	if world:
		var zm := world.get_node_or_null("ZoneManager")
		if zm is ZoneManager:
			return zm as ZoneManager
	return null


func _setup_chests() -> void:
	var objects := get_node_or_null("Objects")
	if not objects:
		return

	var chest_scene := load("res://scenes/objects/chest.tscn") as PackedScene
	if not chest_scene:
		return

	# Load chest data from the map JSON.
	var map_data: Dictionary = GameData.get_map("oldroot_forest")
	var chests: Array = map_data.get("loot_chests", [])

	for i in range(chests.size()):
		var chest_data: Dictionary = chests[i]
		var chest_instance := chest_scene.instantiate()
		var pos: Array = chest_data.get("position", [0, 0])
		chest_instance.position = Vector2(float(pos[0]) * 32.0 + 16.0, float(pos[1]) * 32.0 + 16.0)

		if "chest_id" in chest_instance:
			chest_instance.chest_id = "oldroot_chest_%d" % i
		if "contents" in chest_instance:
			chest_instance.contents = chest_data.get("contents", [])
		if "locked" in chest_instance:
			chest_instance.locked = chest_data.get("locked", false)
		if "lock_level" in chest_instance:
			chest_instance.lock_level = int(chest_data.get("lock_level", 0))

		objects.add_child(chest_instance)


func _setup_signs() -> void:
	var signs := get_node_or_null("Signs")
	if not signs:
		return

	var sign_scene := load("res://scenes/objects/sign.tscn") as PackedScene
	if not sign_scene:
		return

	# Warning sign at south entrance.
	var sign1 := sign_scene.instantiate()
	sign1.position = Vector2(2064, 3968)
	if "sign_title" in sign1:
		sign1.sign_title = "Warning"
	if "sign_text" in sign1:
		sign1.sign_text = "Oldroot Forest\nDangerous creatures ahead.\nStay on the marked paths."
	signs.add_child(sign1)

	# Sign near Theron's campsite.
	var sign2 := sign_scene.instantiate()
	sign2.position = Vector2(1888, 2272)
	if "sign_title" in sign2:
		sign2.sign_title = "Ranger's Camp"
	if "sign_text" in sign2:
		sign2.sign_text = "Ranger Theron's Campsite\nSafe area. Seek him for guidance."
	signs.add_child(sign2)

	# Sign near goblin territory.
	var sign3 := sign_scene.instantiate()
	sign3.position = Vector2(2880, 2400)
	if "sign_title" in sign3:
		sign3.sign_title = "Danger"
	if "sign_text" in sign3:
		sign3.sign_text = "GOBLIN TERRITORY\nTurn back unless you are prepared for battle!"
	signs.add_child(sign3)
