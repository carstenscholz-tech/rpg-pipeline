extends Node
## Autoload that loads and provides access to all JSON game data.
## Content pipeline generates JSON files in data/; this script reads them at runtime.

var npcs: Dictionary = {}
var quests: Dictionary = {}
var items: Dictionary = {}
var maps: Dictionary = {}
var dialogue: Dictionary = {}
var world_bible: Dictionary = {}


func _ready() -> void:
	_load_all()


func _load_all() -> void:
	world_bible = _load_single("res://data/lore/world_bible.json")
	npcs = _load_directory("res://data/npcs/")
	quests = _load_directory("res://data/quests/")
	items = _load_directory("res://data/items/")
	maps = _load_directory("res://data/maps/")
	dialogue = _load_directory("res://data/dialogue/")
	print("GameData loaded: %d NPCs, %d quests, %d items, %d maps, %d dialogues" % [
		npcs.size(), quests.size(), items.size(), maps.size(), dialogue.size()
	])


func _load_single(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) == OK:
		return json.data if json.data is Dictionary else {}
	return {}


func _load_directory(dir_path: String) -> Dictionary:
	var result: Dictionary = {}
	var dir := DirAccess.open(dir_path)
	if not dir:
		return result
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".json"):
			var full_path := dir_path + file_name
			var data := _load_single(full_path)
			if not data.is_empty():
				# Use the first *_id field as the key, or filename
				var key: String = file_name.get_basename()
				for k in data:
					if k.ends_with("_id"):
						key = data[k]
						break
				result[key] = data
		file_name = dir.get_next()
	return result


# --- Public API ---

func get_npc(npc_id: String) -> Dictionary:
	return npcs.get(npc_id, {})


func get_quest(quest_id: String) -> Dictionary:
	return quests.get(quest_id, {})


func get_item(item_id: String) -> Dictionary:
	return items.get(item_id, {})


func get_map(zone_id: String) -> Dictionary:
	return maps.get(zone_id, {})


func get_dialogue(dialogue_id: String) -> Dictionary:
	return dialogue.get(dialogue_id, {})


func get_items_by_type(item_type: String) -> Array:
	var result: Array = []
	for item in items.values():
		if item.get("type") == item_type:
			result.append(item)
	return result


func get_npcs_in_region(region_id: String) -> Array:
	var result: Array = []
	for npc in npcs.values():
		if npc.get("region") == region_id:
			result.append(npc)
	return result


func reload() -> void:
	_load_all()
