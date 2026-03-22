extends Node
## Dialogue system manager. Loads dialogue trees, tracks state, evaluates conditions.

# --- Signals ---
signal dialogue_started(npc_id: String)
signal dialogue_text_shown(speaker: String, text: String)
signal dialogue_choices_shown(choices: Array)
signal dialogue_ended()
signal dialogue_action_triggered(action: String, params: Array)

# --- Dialogue Data ---
var dialogue_data: Dictionary = {}  # dialogue_id -> full dialogue JSON

# --- Current Dialogue State ---
var is_active: bool = false
var current_npc_id: String = ""
var current_dialogue_id: String = ""
var current_tree_id: String = "default"
var current_node_id: String = ""
var current_text: String = ""
var current_choices: Array = []

# --- History (for preventing repeated dialogues, etc.) ---
var dialogue_history: Dictionary = {}  # npc_id -> Array of visited node ids


func _ready() -> void:
	_load_dialogue_data()


func _load_dialogue_data() -> void:
	var dir_path := "res://data/dialogue/"
	var dir := DirAccess.open(dir_path)
	if not dir:
		push_warning("DialogueManager: No dialogue directory at %s" % dir_path)
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".json"):
			var full_path := dir_path + file_name
			var file := FileAccess.open(full_path, FileAccess.READ)
			if file:
				var json := JSON.new()
				if json.parse(file.get_as_text()) == OK and json.data is Dictionary:
					var data: Dictionary = json.data
					var dialogue_id: String = data.get("dialogue_id", file_name.get_basename())
					dialogue_data[dialogue_id] = data
		file_name = dir.get_next()
	print("DialogueManager: Loaded %d dialogue files" % dialogue_data.size())


# --- Starting / Ending Dialogue ---

func start_dialogue(npc_id: String, tree_id: String = "default") -> bool:
	## Begin a dialogue with the specified NPC. Returns false if no dialogue found.
	# Find dialogue data for this NPC
	var dlg_data: Dictionary = _find_dialogue_for_npc(npc_id)
	if dlg_data.is_empty():
		push_warning("DialogueManager: No dialogue data for NPC '%s'" % npc_id)
		return false

	var trees: Dictionary = dlg_data.get("trees", {})
	if not trees.has(tree_id):
		push_warning("DialogueManager: Tree '%s' not found for NPC '%s'" % [tree_id, npc_id])
		return false

	var tree: Dictionary = trees[tree_id]
	var entry_node: String = tree.get("entry", "greeting")

	is_active = true
	current_npc_id = npc_id
	current_dialogue_id = dlg_data.get("dialogue_id", "")
	current_tree_id = tree_id
	current_node_id = ""

	GameManager.change_state(GameManager.GameState.DIALOGUE)
	dialogue_started.emit(npc_id)
	EventBus.start_dialogue.emit(npc_id, dlg_data)
	EventBus.npc_interacted.emit(npc_id)

	# Navigate to the entry node
	_go_to_node(entry_node)
	return true


func end_dialogue() -> void:
	if not is_active:
		return

	is_active = false
	current_npc_id = ""
	current_dialogue_id = ""
	current_tree_id = "default"
	current_node_id = ""
	current_text = ""
	current_choices.clear()

	GameManager.change_state(GameManager.GameState.PLAYING)
	dialogue_ended.emit()
	EventBus.dialogue_ended.emit()


# --- Navigation ---

func _go_to_node(node_id: String) -> void:
	var dlg_data: Dictionary = dialogue_data.get(current_dialogue_id, {})
	var trees: Dictionary = dlg_data.get("trees", {})
	var tree: Dictionary = trees.get(current_tree_id, {})
	var nodes: Dictionary = tree.get("nodes", {})

	if not nodes.has(node_id):
		push_warning("DialogueManager: Node '%s' not found in tree '%s'" % [node_id, current_tree_id])
		end_dialogue()
		return

	current_node_id = node_id
	var node_data: Dictionary = nodes[node_id]

	# Track visit history
	if current_npc_id not in dialogue_history:
		dialogue_history[current_npc_id] = []
	if node_id not in dialogue_history[current_npc_id]:
		dialogue_history[current_npc_id].append(node_id)

	# Get NPC name for display
	var npc_name: String = _get_npc_display_name(current_npc_id)

	# Show text
	current_text = node_data.get("text", "")
	dialogue_text_shown.emit(npc_name, current_text)

	# Gather available choices (filter by conditions)
	current_choices.clear()
	var responses: Array = node_data.get("responses", [])

	for response in responses:
		var condition: Variant = response.get("condition")
		if condition == null or condition == "" or _evaluate_condition(str(condition)):
			current_choices.append({
				"text": response.get("text", "..."),
				"next": response.get("next", "end"),
				"condition": condition,
			})

	if current_choices.is_empty():
		# No responses means end of dialogue (or auto-close after text)
		# Show text, then close on next input
		current_choices.append({
			"text": "[Continue]",
			"next": "__end__",
		})

	dialogue_choices_shown.emit(current_choices)


func select_choice(choice_index: int) -> void:
	## Called when the player picks a dialogue choice.
	if not is_active:
		return
	if choice_index < 0 or choice_index >= current_choices.size():
		return

	var choice: Dictionary = current_choices[choice_index]
	var next_node: String = choice.get("next", "end")

	EventBus.dialogue_choice_made.emit(current_node_id)

	# Check for special actions in choice text
	_check_for_actions(choice.get("text", ""))

	if next_node == "__end__" or next_node == "end":
		# Check if the end node has text
		var dlg_data: Dictionary = dialogue_data.get(current_dialogue_id, {})
		var trees: Dictionary = dlg_data.get("trees", {})
		var tree: Dictionary = trees.get(current_tree_id, {})
		var nodes: Dictionary = tree.get("nodes", {})

		if next_node == "end" and nodes.has("end"):
			# Show the end node text, then close
			_go_to_node("end")
			# After showing end node, the empty responses will auto-add [Continue] -> __end__
		else:
			end_dialogue()
	else:
		_go_to_node(next_node)


func _check_for_actions(choice_text: String) -> void:
	## Parse choice text for special actions like [Accept: Quest Name].
	if choice_text.begins_with("[Accept:"):
		var quest_hint := choice_text.trim_prefix("[Accept:").trim_suffix("]").strip_edges()
		dialogue_action_triggered.emit("accept_quest", [quest_hint])
	elif choice_text.begins_with("[Sign"):
		dialogue_action_triggered.emit("sign", [])
	elif choice_text.begins_with("[Give"):
		dialogue_action_triggered.emit("give_item", [choice_text])


# --- Condition Evaluation ---

func _evaluate_condition(condition: String) -> bool:
	## Evaluate a condition string. Supported formats:
	## "quest_active:quest_id" - quest is currently active
	## "quest_complete:quest_id" - quest has been completed
	## "has_item:item_id" - player has the item
	## "has_item:item_id:count" - player has at least count of the item
	## "level>=X" - player level is at least X
	## "flag:flag_name" - a save flag is set
	## "not:condition" - negation of another condition
	if condition == "" or condition == "null":
		return true

	# Negation
	if condition.begins_with("not:"):
		return not _evaluate_condition(condition.substr(4))

	# Quest active
	if condition.begins_with("quest_active:"):
		var quest_id := condition.substr(13)
		return QuestManager.is_quest_active(quest_id)

	# Quest complete
	if condition.begins_with("quest_complete:"):
		var quest_id := condition.substr(15)
		return QuestManager.is_quest_complete(quest_id)

	# Has item
	if condition.begins_with("has_item:"):
		var parts := condition.substr(9).split(":")
		var item_id := parts[0]
		var count: int = 1
		if parts.size() > 1:
			count = int(parts[1])
		return InventoryManager.count_item(item_id) >= count

	# Level check
	if condition.begins_with("level"):
		# Parse "level>=X" or "level>X" or "level==X"
		var regex := RegEx.new()
		regex.compile("^level\\s*(>=|>|==|<=|<)\\s*(\\d+)$")
		var result := regex.search(condition)
		if result:
			var op: String = result.get_string(1)
			var value: int = int(result.get_string(2))
			match op:
				">=": return PlayerData.level >= value
				">": return PlayerData.level > value
				"==": return PlayerData.level == value
				"<=": return PlayerData.level <= value
				"<": return PlayerData.level < value

	# Flag check
	if condition.begins_with("flag:"):
		var flag_name := condition.substr(5)
		return SaveManager.get_flag(flag_name) == true

	push_warning("DialogueManager: Unknown condition format: '%s'" % condition)
	return false


# --- Helpers ---

func _find_dialogue_for_npc(npc_id: String) -> Dictionary:
	## Search dialogue_data for an entry matching this NPC.
	# First try direct dialogue_id match with npc suffix
	var dialogue_id := npc_id + "_dialogue"
	if dialogue_data.has(dialogue_id):
		return dialogue_data[dialogue_id]

	# Search by npc_id field
	for dlg_id in dialogue_data:
		var dlg: Dictionary = dialogue_data[dlg_id]
		if dlg.get("npc_id", "") == npc_id:
			return dlg

	return {}


func _get_npc_display_name(npc_id: String) -> String:
	## Get the display name for an NPC from GameData.
	var npc_data: Dictionary = GameData.get_npc(npc_id)
	if npc_data.has("name"):
		return npc_data["name"]
	# Fallback: capitalize the ID
	return npc_id.replace("_", " ").capitalize()


func has_visited_node(npc_id: String, node_id: String) -> bool:
	if npc_id not in dialogue_history:
		return false
	return node_id in dialogue_history[npc_id]


# --- Serialization is handled through dialogue_history only ---
# Dialogue state is transient (not saved mid-conversation)

func get_history() -> Dictionary:
	return dialogue_history.duplicate(true)


func set_history(data: Dictionary) -> void:
	dialogue_history = data.duplicate(true)
