extends Node
class_name QuestTracker
## Tracks active and completed quests, checks step completion.

var active_quests: Dictionary = {}  # quest_id -> {data, current_step}
var completed_quests: Array[String] = []


func _ready() -> void:
	EventBus.enemy_defeated.connect(_on_enemy_defeated)
	EventBus.item_added.connect(_on_item_added)
	EventBus.npc_interacted.connect(_on_npc_interacted)
	EventBus.zone_entered.connect(_on_zone_entered)


func start_quest(quest_id: String) -> bool:
	if quest_id in active_quests or quest_id in completed_quests:
		return false

	var quest_data: Dictionary = GameData.get_quest(quest_id)
	if quest_data.is_empty():
		push_warning("Unknown quest: " + quest_id)
		return false

	# Check prerequisites
	for prereq in quest_data.get("prerequisites", []):
		if prereq not in completed_quests:
			EventBus.show_notification.emit("Prerequisite not met: " + prereq)
			return false

	active_quests[quest_id] = {
		"data": quest_data,
		"current_step": 0,
		"step_progress": {},
	}

	SaveManager.set_flag("quest_active_" + quest_id, true)
	EventBus.quest_started.emit(quest_id)
	EventBus.show_notification.emit("Quest started: " + quest_data.get("title", quest_id))
	return true


func get_current_step(quest_id: String) -> Dictionary:
	if quest_id not in active_quests:
		return {}
	var quest: Dictionary = active_quests[quest_id]
	var steps: Array = quest.data.get("steps", [])
	var idx: int = quest.current_step
	if idx < steps.size():
		return steps[idx]
	return {}


func advance_step(quest_id: String) -> void:
	if quest_id not in active_quests:
		return

	var quest: Dictionary = active_quests[quest_id]
	quest.current_step += 1
	var steps: Array = quest.data.get("steps", [])

	EventBus.quest_step_completed.emit(quest_id, quest.current_step)

	if quest.current_step >= steps.size():
		complete_quest(quest_id)
	else:
		EventBus.quest_updated.emit(quest_id)


func complete_quest(quest_id: String) -> void:
	if quest_id not in active_quests:
		return

	var quest_data: Dictionary = active_quests[quest_id].data

	# Grant rewards
	var rewards: Dictionary = quest_data.get("rewards", {})
	for skill_id in rewards.get("xp", {}):
		var amount: int = int(rewards.xp[skill_id])
		EventBus.xp_gained.emit(skill_id, amount)

	var gold: int = int(rewards.get("gold", 0))
	if gold > 0:
		EventBus.show_notification.emit("Received %d gold" % gold)

	# Move to completed
	active_quests.erase(quest_id)
	completed_quests.append(quest_id)
	SaveManager.set_flag("quest_active_" + quest_id, false)
	SaveManager.set_flag("quest_complete_" + quest_id, true)

	EventBus.quest_completed.emit(quest_id)
	EventBus.show_notification.emit("Quest complete: " + quest_data.get("title", quest_id))


# --- Event handlers for step auto-completion ---

func _on_enemy_defeated(enemy_id: String) -> void:
	_check_step_type("defeat_enemies", "enemy_type", enemy_id)


func _on_item_added(item_id: String, _quantity: int) -> void:
	_check_step_type("collect_items", "required_item", item_id)


func _on_npc_interacted(npc_id: String) -> void:
	_check_step_type("talk_to_npc", "target_npc", npc_id)


func _on_zone_entered(zone_id: String) -> void:
	_check_step_type("go_to_location", "target_zone", zone_id)


func _check_step_type(step_type: String, field: String, value: String) -> void:
	for quest_id in active_quests:
		var step: Dictionary = get_current_step(quest_id)
		if step.get("type") == step_type and step.get(field) == value:
			var count_needed: int = step.get("count", 1)
			var progress_key: String = quest_id + "_" + str(step.get("step_id", 0))
			var progress: Dictionary = active_quests[quest_id].step_progress
			progress[progress_key] = progress.get(progress_key, 0) + 1

			if progress[progress_key] >= count_needed:
				advance_step(quest_id)
