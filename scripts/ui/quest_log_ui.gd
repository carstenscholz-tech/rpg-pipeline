extends CanvasLayer
class_name QuestLogUI
## Quest log panel with active/completed tabs and quest detail view.
## Uses QuestManager autoload for all data.

@onready var quest_panel: PanelContainer = %QuestPanel
@onready var quest_list: ItemList = %QuestList
@onready var quest_title_label: Label = %QuestTitle
@onready var quest_desc_label: RichTextLabel = %QuestDescription
@onready var objectives_container: VBoxContainer = %ObjectivesContainer
@onready var rewards_label: Label = %RewardsLabel
@onready var tab_active: Button = %TabActive
@onready var tab_completed: Button = %TabCompleted

var is_open: bool = false
var showing_completed: bool = false
var current_quest_ids: Array[String] = []


func _ready() -> void:
	quest_panel.visible = false
	_connect_signals()
	_clear_detail()


func _connect_signals() -> void:
	QuestManager.quest_log_updated.connect(_on_quest_log_updated)
	tab_active.pressed.connect(_show_active_tab)
	tab_completed.pressed.connect(_show_completed_tab)
	quest_list.item_selected.connect(_on_quest_selected)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("quest_log"):
		toggle()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel") and is_open:
		close()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	if is_open:
		close()
	else:
		open()


func open() -> void:
	is_open = true
	quest_panel.visible = true
	_refresh_list()


func close() -> void:
	is_open = false
	quest_panel.visible = false


func _show_active_tab() -> void:
	showing_completed = false
	tab_active.disabled = true
	tab_completed.disabled = false
	_refresh_list()


func _show_completed_tab() -> void:
	showing_completed = true
	tab_active.disabled = false
	tab_completed.disabled = true
	_refresh_list()


func _refresh_list() -> void:
	quest_list.clear()
	current_quest_ids.clear()

	if showing_completed:
		for quest_id in QuestManager.completed_quests:
			var title: String = QuestManager.get_quest_title(quest_id)
			quest_list.add_item(title)
			current_quest_ids.append(quest_id)
	else:
		for quest_id in QuestManager.active_quests:
			var title: String = QuestManager.get_quest_title(quest_id)
			quest_list.add_item(title)
			current_quest_ids.append(quest_id)

	if current_quest_ids.is_empty():
		_clear_detail()
	elif quest_list.item_count > 0:
		quest_list.select(0)
		_on_quest_selected(0)


func _on_quest_selected(index: int) -> void:
	if index < 0 or index >= current_quest_ids.size():
		_clear_detail()
		return

	var quest_id: String = current_quest_ids[index]
	var quest_data: Dictionary = QuestManager.get_quest_data(quest_id)
	if quest_data.is_empty():
		_clear_detail()
		return

	var current_step: int = -1
	if not showing_completed and QuestManager.active_quests.has(quest_id):
		current_step = QuestManager.active_quests[quest_id].get("current_step", 1)

	_display_quest_detail(quest_id, quest_data, current_step)


func _display_quest_detail(quest_id: String, quest_data: Dictionary, current_step: int) -> void:
	quest_title_label.text = quest_data.get("title", quest_id)
	quest_desc_label.text = quest_data.get("description", "No description available.")

	# Clear objectives
	for child in objectives_container.get_children():
		child.queue_free()

	# Build objectives list
	var steps: Array = quest_data.get("steps", [])
	for step in steps:
		var step_id: int = step.get("step_id", 0)
		var step_desc: String = step.get("description", "???")
		var count: int = step.get("count", 0)

		var objective := HBoxContainer.new()

		var checkbox := Label.new()
		checkbox.add_theme_font_size_override("font_size", 10)

		var is_complete: bool = showing_completed or step_id < current_step
		var is_current: bool = not showing_completed and step_id == current_step

		if is_complete:
			checkbox.text = "[X]"
			checkbox.add_theme_color_override("font_color", Color.GREEN)
		elif is_current:
			checkbox.text = "[ ]"
			checkbox.add_theme_color_override("font_color", Color.YELLOW)
		else:
			checkbox.text = "[ ]"
			checkbox.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))

		var desc_label := Label.new()
		desc_label.add_theme_font_size_override("font_size", 10)
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		# Show progress for counting steps
		if is_current and count > 1:
			var progress: int = QuestManager.get_step_progress(quest_id, step_id)
			desc_label.text = "%s (%d/%d)" % [step_desc, progress, count]
		else:
			desc_label.text = step_desc

		if is_complete:
			desc_label.add_theme_color_override("font_color", Color(0.6, 0.8, 0.6))
		elif is_current:
			desc_label.add_theme_color_override("font_color", Color.WHITE)
		else:
			desc_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))

		objective.add_child(checkbox)
		objective.add_child(desc_label)
		objectives_container.add_child(objective)

	# Rewards
	var rewards: Dictionary = quest_data.get("rewards", {})
	var rewards_text: String = "Rewards:\n"
	var gold: int = rewards.get("gold", 0)
	if gold > 0:
		rewards_text += "  Gold: %d\n" % gold
	var xp_rewards: Dictionary = rewards.get("xp", {})
	for skill_id in xp_rewards:
		rewards_text += "  %s XP: %d\n" % [skill_id.capitalize(), int(xp_rewards[skill_id])]
	var item_rewards: Array = rewards.get("items", [])
	for item_reward in item_rewards:
		var item_def: Dictionary = InventoryManager.get_item_def(item_reward.get("item_id", ""))
		var item_name: String = item_def.get("name", item_reward.get("item_id", "???"))
		var qty: int = item_reward.get("quantity", 1)
		rewards_text += "  %s x%d\n" % [item_name, qty]
	rewards_label.text = rewards_text.strip_edges()


func _clear_detail() -> void:
	quest_title_label.text = "No quest selected"
	quest_desc_label.text = ""
	for child in objectives_container.get_children():
		child.queue_free()
	rewards_label.text = ""


func _on_quest_log_updated() -> void:
	if is_open:
		_refresh_list()
