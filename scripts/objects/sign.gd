extends StaticBody2D
class_name ReadableSign
## A sign the player can read by pressing interact.

## The text displayed when the player reads the sign.
@export_multiline var sign_text: String = "..."
## Optional sign title/header.
@export var sign_title: String = ""

var _player_in_range: bool = false

@onready var sprite: Sprite2D = $Sprite2D
@onready var interaction_area: Area2D = $InteractionArea


func _ready() -> void:
	add_to_group("interactables")

	if interaction_area:
		interaction_area.connect("body_entered", _on_body_entered)
		interaction_area.connect("body_exited", _on_body_exited)


func interact(_player: CharacterBody2D) -> void:
	# Build a dialogue-like data structure so the dialogue system can show it.
	var text_to_show := ""
	if sign_title != "":
		text_to_show = "[%s]\n%s" % [sign_title, sign_text]
	else:
		text_to_show = sign_text

	# Use the dialogue system to display sign text.
	var sign_dialogue: Dictionary = {
		"speaker": sign_title if sign_title != "" else "Sign",
		"nodes": {
			"start": {
				"text": text_to_show,
				"choices": []
			}
		},
		"start_node": "start"
	}
	EventBus.start_dialogue.emit("sign", sign_dialogue)


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_range = true


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_range = false


func is_player_in_range() -> bool:
	return _player_in_range
