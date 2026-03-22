extends Node
class_name DialogueSystem
## Manages dialogue tree traversal and NPC conversations.

var current_npc_id: String = ""
var current_tree: Dictionary = {}
var current_node_id: String = ""


func _ready() -> void:
	EventBus.start_dialogue.connect(start)
	EventBus.dialogue_choice_made.connect(advance)


func start(npc_id: String, dialogue_data: Dictionary) -> void:
	current_npc_id = npc_id
	var trees: Dictionary = dialogue_data.get("trees", {})
	current_tree = trees.get("default", {})

	if current_tree.is_empty():
		push_warning("No dialogue tree for: " + npc_id)
		return

	current_node_id = current_tree.get("entry", "greeting")
	_display_current_node()


func advance(choice_next: String) -> void:
	if choice_next == "end" or choice_next.is_empty():
		end_dialogue()
		return

	current_node_id = choice_next
	_display_current_node()


func end_dialogue() -> void:
	current_npc_id = ""
	current_tree = {}
	current_node_id = ""
	EventBus.dialogue_ended.emit()


func _display_current_node() -> void:
	var nodes: Dictionary = current_tree.get("nodes", {})
	var node: Dictionary = nodes.get(current_node_id, {})

	if node.is_empty():
		end_dialogue()
		return

	var text: String = node.get("text", "...")
	var responses: Array = node.get("responses", [])

	# Filter responses by conditions
	var available_responses: Array = []
	for response in responses:
		if _check_condition(response.get("condition")):
			available_responses.append(response)

	# If no responses, this is a terminal node
	if available_responses.is_empty():
		end_dialogue()
		return

	# Emit signal for the UI layer to display
	EventBus.dialogue_node_displayed.emit(current_npc_id, text, available_responses)


func get_current_text() -> String:
	var nodes: Dictionary = current_tree.get("nodes", {})
	var node: Dictionary = nodes.get(current_node_id, {})
	return node.get("text", "")


func get_current_responses() -> Array:
	var nodes: Dictionary = current_tree.get("nodes", {})
	var node: Dictionary = nodes.get(current_node_id, {})
	var responses: Array = node.get("responses", [])
	var available: Array = []
	for r in responses:
		if _check_condition(r.get("condition")):
			available.append(r)
	return available


func _check_condition(condition: Variant) -> bool:
	if condition == null or (condition is String and condition.is_empty()):
		return true

	var cond_str: String = str(condition)
	var parts: PackedStringArray = cond_str.split(":")
	if parts.size() < 2:
		return true

	var cond_type: String = parts[0]
	var cond_value: String = parts[1]

	match cond_type:
		"quest_active":
			return SaveManager.get_flag("quest_active_" + cond_value, false)
		"quest_complete":
			return SaveManager.get_flag("quest_complete_" + cond_value, false)
		"has_item":
			# Requires inventory reference — check via save data
			return SaveManager.get_flag("has_item_" + cond_value, false)
		"level_min":
			return SaveManager.get_flag("player_level", 1) >= int(cond_value)
		_:
			return true
