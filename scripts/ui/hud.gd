extends CanvasLayer
class_name HUD
## In-game heads-up display showing health, mana, XP, gold, minimap, quick slots, and target info.

@onready var health_bar: ProgressBar = %HealthBar
@onready var health_label: Label = %HealthLabel
@onready var mana_bar: ProgressBar = %ManaBar
@onready var mana_label: Label = %ManaLabel
@onready var xp_bar: ProgressBar = %XPBar
@onready var xp_label: Label = %XPLabel
@onready var level_label: Label = %LevelLabel
@onready var gold_label: Label = %GoldLabel
@onready var quick_slots_container: HBoxContainer = %QuickSlots
@onready var target_panel: PanelContainer = %TargetPanel
@onready var target_name_label: Label = %TargetName
@onready var target_hp_bar: ProgressBar = %TargetHPBar
@onready var target_hp_label: Label = %TargetHPLabel

var quick_slot_items: Array[String] = ["", "", "", "", ""]


func _ready() -> void:
	target_panel.visible = false
	_connect_signals()
	_setup_quick_slots()
	# Initialize display from current PlayerData state
	call_deferred("_sync_from_player_data")


func _connect_signals() -> void:
	PlayerData.hp_changed.connect(_on_hp_changed)
	PlayerData.mp_changed.connect(_on_mp_changed)
	PlayerData.xp_gained.connect(_on_xp_gained)
	PlayerData.level_changed.connect(_on_level_changed)
	PlayerData.stats_changed.connect(_on_stats_changed)
	EventBus.target_changed.connect(_on_target_changed)
	EventBus.target_cleared.connect(_on_target_cleared)


func _sync_from_player_data() -> void:
	_on_hp_changed(PlayerData.current_hp, PlayerData.max_hp)
	_on_mp_changed(PlayerData.current_mp, PlayerData.max_mp)
	_update_xp_display()
	level_label.text = "Lv. %d" % PlayerData.level
	gold_label.text = str(PlayerData.gold)


func _setup_quick_slots() -> void:
	for i in range(5):
		var slot: PanelContainer = quick_slots_container.get_child(i) as PanelContainer
		if slot:
			var key_label: Label = slot.get_node("KeyLabel") as Label
			if key_label:
				key_label.text = str(i + 1)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		var key: int = event.physical_keycode
		if key >= KEY_1 and key <= KEY_5:
			var slot_index: int = key - KEY_1
			_use_quick_slot(slot_index)


func _use_quick_slot(index: int) -> void:
	if index < 0 or index >= quick_slot_items.size():
		return
	var item_id: String = quick_slot_items[index]
	if item_id.is_empty():
		return
	InventoryManager.use_item(item_id)


func set_quick_slot(index: int, item_id: String) -> void:
	if index >= 0 and index < quick_slot_items.size():
		quick_slot_items[index] = item_id
		_update_quick_slot_display(index)


func _update_quick_slot_display(index: int) -> void:
	var slot: PanelContainer = quick_slots_container.get_child(index) as PanelContainer
	if not slot:
		return
	var icon: TextureRect = slot.get_node_or_null("ItemIcon") as TextureRect
	if icon:
		icon.texture = null  # Placeholder until sprite system is connected


func _on_hp_changed(current: int, maximum: int) -> void:
	health_bar.max_value = maximum
	health_bar.value = current
	health_label.text = "%d / %d" % [current, maximum]


func _on_mp_changed(current: int, maximum: int) -> void:
	mana_bar.max_value = maximum
	mana_bar.value = current
	mana_label.text = "%d / %d" % [current, maximum]


func _on_xp_gained(_amount: int) -> void:
	_update_xp_display()


func _update_xp_display() -> void:
	var next_level_xp: int = PlayerData.xp_for_next_level()
	var current_threshold: int = 0
	if PlayerData.level - 1 < PlayerData.XP_TABLE.size():
		current_threshold = PlayerData.XP_TABLE[PlayerData.level - 1]
	var xp_in_level: int = PlayerData.xp - current_threshold
	var xp_needed: int = next_level_xp - current_threshold
	xp_bar.max_value = maxi(xp_needed, 1)
	xp_bar.value = xp_in_level
	xp_label.text = "%d / %d" % [xp_in_level, xp_needed]


func _on_level_changed(new_level: int) -> void:
	level_label.text = "Lv. %d" % new_level
	_update_xp_display()
	EventBus.show_notification.emit("Level up! Now level %d" % new_level)


func _on_stats_changed() -> void:
	gold_label.text = str(PlayerData.gold)


func _on_target_changed(target_data: Dictionary) -> void:
	target_panel.visible = true
	target_name_label.text = target_data.get("name", "Unknown")
	var hp: int = target_data.get("hp", 0)
	var max_hp: int = target_data.get("max_hp", 1)
	target_hp_bar.max_value = max_hp
	target_hp_bar.value = hp
	target_hp_label.text = "%d / %d" % [hp, max_hp]


func _on_target_cleared() -> void:
	target_panel.visible = false
