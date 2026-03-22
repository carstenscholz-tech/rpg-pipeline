extends Node
## Handles saving and loading game state.

const SAVE_PATH: String = "user://save_data.json"

var save_data: Dictionary = {
	"player": {
		"position": {"x": 0, "y": 0},
		"zone": "lumbridge",
		"stats": {},
		"skills": {},
	},
	"inventory": [],
	"quests": {
		"active": [],
		"completed": [],
	},
	"flags": {},
}


func save_game() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(save_data, "\t"))
		EventBus.game_saved.emit()
		print("Game saved")


func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		return false
	var json := JSON.new()
	if json.parse(file.get_as_text()) == OK and json.data is Dictionary:
		save_data = json.data
		EventBus.game_loaded.emit()
		print("Game loaded")
		return true
	return false


func set_flag(flag: String, value: Variant = true) -> void:
	save_data.flags[flag] = value


func get_flag(flag: String, default: Variant = false) -> Variant:
	return save_data.flags.get(flag, default)
