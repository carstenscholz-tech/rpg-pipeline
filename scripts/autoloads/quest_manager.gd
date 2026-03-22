extends Node
## Quest tracking system. Loads quest data, tracks active/completed quests, and progress.

# --- Signals ---
signal quest_accepted(quest_id: String)
signal quest_step_progressed(quest_id: String, step_id: int, progress: int, required: int)
signal quest_step_completed(quest_id: String, step_id: int)
signal quest_completed(quest_id: String)
signal quest_failed(quest_id: String)
signal quest_log_updated()

# --- Data ---
var quest_definitions: Dictionary = {}  # quest_id -> full quest data from JSON

# --- Tracking ---
# active_quests[quest_id] = { "current_step": int, "step_progress": { step_id: int }, "started_at": String }
var active_quests: Dictionary = {}
var completed_quests: Array[String] = []
var failed_quests: Array[String] = []


func _ready() -> void:
	_load_quest_definitions()
	# Connect to EventBus for automatic quest tracking
	EventBus.enemy_defeated.connect(_on_enemy_defeated)
	EventBus.item_added.connect(_on_item_added)
	EventBus.npc_interacted.connect(_on_npc_interacted)
	EventBus.zone_entered.connect(_on_zone_entered)


func _load_quest_definitions() -> void:
	var dir_path := "res://data/quests/"
	var dir := DirAccess.open(dir_path)
	if not dir:
		push_warning("QuestManager: No quests directory at %s" % dir_path)
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
					var quest_id: String = data.get("quest_id", file_name.get_basename())
					quest_definitions[quest_id] = data
		file_name = dir.get_next()
	print("QuestManager: Loaded %d quest definitions" % quest_definitions.size())


# --- Quest Management ---

func can_accept_quest(quest_id: String) -> bool:
	## Check if the player meets all prerequisites for this quest.
	if not quest_definitions.has(quest_id):
		return false
	if quest_id in active_quests:
		return false
	if quest_id in completed_quests:
		return false

	var quest_data: Dictionary = quest_definitions[quest_id]

	# Check level requirement
	var level_req: int = quest_data.get("level_requirement", 1)
	if PlayerData.level < level_req:
		return false

	# Check prerequisite quests
	var prereqs: Array = quest_data.get("prerequisites", [])
	for prereq_id in prereqs:
		if prereq_id not in completed_quests:
			return false

	return true


func accept_quest(quest_id: String) -> bool:
	if not can_accept_quest(quest_id):
		return false

	active_quests[quest_id] = {
		"current_step": 1,
		"step_progress": {},
		"started_at": Time.get_datetime_string_from_system(),
	}

	quest_accepted.emit(quest_id)
	EventBus.quest_started.emit(quest_id)
	quest_log_updated.emit()

	var quest_data: Dictionary = quest_definitions[quest_id]
	EventBus.show_notification.emit("Quest started: %s" % quest_data.get("title", quest_id))
	print("QuestManager: Accepted quest '%s'" % quest_id)
	return true


func get_current_step(quest_id: String) -> Dictionary:
	## Returns the current step data for an active quest.
	if quest_id not in active_quests:
		return {}
	if not quest_definitions.has(quest_id):
		return {}

	var tracking: Dictionary = active_quests[quest_id]
	var current_step_id: int = tracking["current_step"]
	var steps: Array = quest_definitions[quest_id].get("steps", [])

	for step in steps:
		if step.get("step_id") == current_step_id:
			return step
	return {}


func advance_step(quest_id: String) -> void:
	## Move to the next step, or complete the quest if no steps remain.
	if quest_id not in active_quests:
		return

	var tracking: Dictionary = active_quests[quest_id]
	var steps: Array = quest_definitions[quest_id].get("steps", [])
	var current_step_id: int = tracking["current_step"]

	quest_step_completed.emit(quest_id, current_step_id)
	EventBus.quest_step_completed.emit(quest_id, current_step_id)

	# Find next step
	var next_step_id: int = current_step_id + 1
	var has_next: bool = false
	for step in steps:
		if step.get("step_id") == next_step_id:
			has_next = true
			break

	if has_next:
		tracking["current_step"] = next_step_id
		quest_log_updated.emit()
	else:
		_complete_quest(quest_id)


func update_step_progress(quest_id: String, step_id: int, amount: int = 1) -> void:
	## Increment progress for a counting step (defeat_enemies, collect_items).
	if quest_id not in active_quests:
		return

	var tracking: Dictionary = active_quests[quest_id]
	if tracking["current_step"] != step_id:
		return

	var step_key := str(step_id)
	if step_key not in tracking["step_progress"]:
		tracking["step_progress"][step_key] = 0
	tracking["step_progress"][step_key] += amount

	var step_data: Dictionary = get_current_step(quest_id)
	var required: int = step_data.get("count", 1)
	var current: int = tracking["step_progress"][step_key]

	quest_step_progressed.emit(quest_id, step_id, current, required)
	EventBus.quest_updated.emit(quest_id)
	quest_log_updated.emit()

	if current >= required:
		advance_step(quest_id)


func get_step_progress(quest_id: String, step_id: int) -> int:
	if quest_id not in active_quests:
		return 0
	var step_key := str(step_id)
	return active_quests[quest_id]["step_progress"].get(step_key, 0)


func _complete_quest(quest_id: String) -> void:
	if quest_id not in active_quests:
		return

	active_quests.erase(quest_id)
	completed_quests.append(quest_id)

	# Grant rewards
	var quest_data: Dictionary = quest_definitions[quest_id]
	var rewards: Dictionary = quest_data.get("rewards", {})

	# XP rewards
	var xp_rewards: Dictionary = rewards.get("xp", {})
	var total_xp: int = 0
	for xp_val in xp_rewards.values():
		total_xp += int(xp_val)
	if total_xp > 0:
		PlayerData.add_xp(total_xp)

	# Gold reward
	var gold_reward: int = rewards.get("gold", 0)
	if gold_reward > 0:
		PlayerData.add_gold(gold_reward)

	# Item rewards
	var item_rewards: Array = rewards.get("items", [])
	for item_entry in item_rewards:
		var item_id: String = item_entry.get("item_id", "")
		var quantity: int = item_entry.get("quantity", 1)
		if item_id != "":
			InventoryManager.add_item(item_id, quantity)

	quest_completed.emit(quest_id)
	EventBus.quest_completed.emit(quest_id)
	quest_log_updated.emit()

	EventBus.show_notification.emit("Quest complete: %s" % quest_data.get("title", quest_id))
	print("QuestManager: Completed quest '%s'" % quest_id)


func fail_quest(quest_id: String) -> void:
	if quest_id not in active_quests:
		return
	active_quests.erase(quest_id)
	failed_quests.append(quest_id)
	quest_failed.emit(quest_id)
	quest_log_updated.emit()


# --- Queries ---

func is_quest_active(quest_id: String) -> bool:
	return quest_id in active_quests


func is_quest_complete(quest_id: String) -> bool:
	return quest_id in completed_quests


func get_active_quest_ids() -> Array[String]:
	var result: Array[String] = []
	for quest_id in active_quests:
		result.append(quest_id)
	return result


func get_quest_data(quest_id: String) -> Dictionary:
	return quest_definitions.get(quest_id, {})


func get_quest_title(quest_id: String) -> String:
	return quest_definitions.get(quest_id, {}).get("title", quest_id)


# --- Automatic Progress Tracking ---

func _on_enemy_defeated(enemy_id: String) -> void:
	for quest_id in active_quests:
		var step: Dictionary = get_current_step(quest_id)
		if step.get("type") == "defeat_enemies":
			if step.get("enemy_type", "") == enemy_id or step.get("enemy_type", "") == "":
				update_step_progress(quest_id, step["step_id"])


func _on_item_added(item_id: String, _quantity: int) -> void:
	for quest_id in active_quests:
		var step: Dictionary = get_current_step(quest_id)
		if step.get("type") == "collect_items":
			if step.get("required_item", "") == item_id:
				# Count total in inventory
				var total: int = InventoryManager.count_item(item_id)
				var required: int = step.get("count", 1)
				var tracking: Dictionary = active_quests[quest_id]
				tracking["step_progress"][str(step["step_id"])] = mini(total, required)
				quest_step_progressed.emit(quest_id, step["step_id"], mini(total, required), required)
				EventBus.quest_updated.emit(quest_id)
				quest_log_updated.emit()
				if total >= required:
					advance_step(quest_id)


func _on_npc_interacted(npc_id: String) -> void:
	for quest_id in active_quests.keys():
		var step: Dictionary = get_current_step(quest_id)
		if step.get("type") == "talk_to_npc":
			if step.get("target_npc", "") == npc_id:
				advance_step(quest_id)


func _on_zone_entered(zone_id: String) -> void:
	for quest_id in active_quests.keys():
		var step: Dictionary = get_current_step(quest_id)
		if step.get("type") == "go_to_location":
			if step.get("target_zone", "") == zone_id:
				advance_step(quest_id)


# --- Serialization ---

func serialize() -> Dictionary:
	return {
		"active_quests": active_quests.duplicate(true),
		"completed_quests": completed_quests.duplicate(),
		"failed_quests": failed_quests.duplicate(),
	}


func deserialize(data: Dictionary) -> void:
	active_quests = data.get("active_quests", {})
	completed_quests.clear()
	for q in data.get("completed_quests", []):
		completed_quests.append(q)
	failed_quests.clear()
	for q in data.get("failed_quests", []):
		failed_quests.append(q)
	quest_log_updated.emit()


func reset() -> void:
	active_quests.clear()
	completed_quests.clear()
	failed_quests.clear()
	quest_log_updated.emit()
