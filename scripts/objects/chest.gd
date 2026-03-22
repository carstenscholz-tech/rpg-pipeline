extends StaticBody2D
class_name LootChest
## Interactive loot chest that can be opened once. Contents defined in data.

signal chest_opened(chest_id: String)

## Unique identifier for save state tracking.
@export var chest_id: String = ""
## Items contained in the chest: Array of {item_id: String, quantity: int}.
@export var contents: Array = []
## Whether this chest requires a lockpick or key.
@export var locked: bool = false
## Lock difficulty level (0 = unlocked).
@export var lock_level: int = 0

## Whether the chest has already been opened.
var is_open: bool = false
## Whether the player is in interaction range.
var _player_in_range: bool = false

@onready var sprite: Sprite2D = $Sprite2D
@onready var interaction_area: Area2D = $InteractionArea
@onready var collision_shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	add_to_group("interactables")

	# Check if this chest was already opened in save data.
	if chest_id != "":
		is_open = SaveManager.get_flag("chest_opened_" + chest_id, false)
		if is_open:
			_show_open_state()

	if interaction_area:
		interaction_area.connect("body_entered", _on_body_entered)
		interaction_area.connect("body_exited", _on_body_exited)


func interact(_player: CharacterBody2D) -> void:
	if is_open:
		EventBus.show_notification.emit("This chest is empty.")
		return

	if locked:
		# Check if player has the required key or lockpick skill.
		# For now, just notify.
		EventBus.show_notification.emit("This chest is locked. (Lock level: %d)" % lock_level)
		return

	open_chest()


func open_chest() -> void:
	if is_open:
		return

	is_open = true

	# Mark as opened in save data.
	if chest_id != "":
		SaveManager.set_flag("chest_opened_" + chest_id, true)

	# Grant items to the player.
	for item_entry in contents:
		var item_id: String = item_entry.get("item_id", "")
		var quantity: int = int(item_entry.get("quantity", 1))
		if item_id != "":
			EventBus.item_added.emit(item_id, quantity)
			var item_data: Dictionary = GameData.get_item(item_id)
			var item_name: String = item_data.get("name", item_id)
			EventBus.show_notification.emit("Found: %s x%d" % [item_name, quantity])

	# Play open animation.
	_show_open_state()
	chest_opened.emit(chest_id)


func _show_open_state() -> void:
	# Visual change for opened chest.
	# When actual sprites exist, this would swap the texture or play an animation.
	if sprite:
		sprite.modulate = Color(0.6, 0.6, 0.6, 1.0)


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_range = true


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_range = false


func is_player_in_range() -> bool:
	return _player_in_range
