extends Control
class_name CharacterCreation
## Character creation screen with name input, class selection, preview, and stats.
## Uses PlayerData autoload for class definitions and initialization.

@onready var name_input: LineEdit = %NameInput
@onready var class_list: ItemList = %ClassList
@onready var class_preview: TextureRect = %ClassPreview
@onready var class_name_label: Label = %ClassName
@onready var class_desc_label: RichTextLabel = %ClassDescription
@onready var stats_container: VBoxContainer = %StatsContainer
@onready var confirm_btn: Button = %ConfirmButton
@onready var back_btn: Button = %BackButton
@onready var error_label: Label = %ErrorLabel

const GAME_SCENE: String = "res://scenes/main.tscn"
const MAIN_MENU_SCENE: String = "res://scenes/ui/main_menu.tscn"

var class_entries: Array[Dictionary] = []  # ordered list of class data
var selected_class_index: int = -1

# Fallback class definitions if data files not found
const FALLBACK_CLASSES: Array[Dictionary] = [
	{
		"class_id": "knight",
		"name": "Knight",
		"description": "A stalwart defender clad in heavy armor. Knights excel at taking hits and protecting allies with sword and shield.",
		"base_stats": {"hp": 50, "mp": 10, "strength": 8, "dexterity": 4, "intelligence": 3, "wisdom": 3, "constitution": 8, "luck": 4},
	},
	{
		"class_id": "ranger",
		"name": "Ranger",
		"description": "A swift hunter at home in the wilderness. Rangers strike from range with deadly accuracy and can track any foe.",
		"base_stats": {"hp": 35, "mp": 20, "strength": 5, "dexterity": 9, "intelligence": 4, "wisdom": 5, "constitution": 5, "luck": 7},
	},
	{
		"class_id": "mage",
		"name": "Mage",
		"description": "A scholar of the arcane arts wielding devastating elemental magic. Fragile but overwhelmingly powerful at range.",
		"base_stats": {"hp": 25, "mp": 50, "strength": 2, "dexterity": 4, "intelligence": 10, "wisdom": 7, "constitution": 3, "luck": 4},
	},
	{
		"class_id": "rogue",
		"name": "Rogue",
		"description": "A cunning shadow-dancer who strikes from the darkness. Rogues deal massive burst damage and can pick any lock.",
		"base_stats": {"hp": 30, "mp": 15, "strength": 5, "dexterity": 10, "intelligence": 4, "wisdom": 3, "constitution": 4, "luck": 9},
	},
	{
		"class_id": "cleric",
		"name": "Cleric",
		"description": "A divine healer who channels the power of the Aether. Clerics keep their party alive and can smite undead foes.",
		"base_stats": {"hp": 40, "mp": 40, "strength": 4, "dexterity": 3, "intelligence": 6, "wisdom": 10, "constitution": 5, "luck": 5},
	},
]


func _ready() -> void:
	_load_class_data()
	_populate_class_list()
	_connect_signals()
	error_label.text = ""
	confirm_btn.disabled = true
	_clear_class_preview()


func _load_class_data() -> void:
	class_entries.clear()

	# Use PlayerData's loaded class definitions if available
	if not PlayerData.class_definitions.is_empty():
		# Map warrior -> knight for display, add missing classes from fallback
		var existing_ids: Array[String] = []
		for class_id in PlayerData.class_definitions:
			var data: Dictionary = PlayerData.class_definitions[class_id]
			var entry: Dictionary = data.duplicate(true)
			# Map warrior to knight for the creation screen
			if class_id == "warrior":
				entry["class_id"] = "knight"
				entry["name"] = "Knight"
			class_entries.append(entry)
			existing_ids.append(entry.get("class_id", class_id))

		# Fill missing classes from fallback
		for fallback in FALLBACK_CLASSES:
			if fallback["class_id"] not in existing_ids:
				class_entries.append(fallback)
	else:
		class_entries.assign(FALLBACK_CLASSES)

	# Sort consistently: knight, ranger, mage, rogue, cleric
	var order: Array[String] = ["knight", "ranger", "mage", "rogue", "cleric"]
	class_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_idx: int = order.find(a.get("class_id", ""))
		var b_idx: int = order.find(b.get("class_id", ""))
		if a_idx == -1: a_idx = 99
		if b_idx == -1: b_idx = 99
		return a_idx < b_idx
	)


func _populate_class_list() -> void:
	class_list.clear()
	for cls in class_entries:
		class_list.add_item(cls.get("name", "Unknown"))


func _connect_signals() -> void:
	class_list.item_selected.connect(_on_class_selected)
	confirm_btn.pressed.connect(_on_confirm)
	back_btn.pressed.connect(_on_back)
	name_input.text_changed.connect(_on_name_changed)


func _on_class_selected(index: int) -> void:
	if index < 0 or index >= class_entries.size():
		return

	selected_class_index = index
	var cls: Dictionary = class_entries[index]

	class_name_label.text = cls.get("name", "Unknown")
	class_desc_label.text = cls.get("description", "No description available.")

	# Load preview sprite
	var class_id: String = cls.get("class_id", "")
	var sprite_path: String = "res://assets/sprites/classes/%s_preview.png" % class_id
	if ResourceLoader.exists(sprite_path):
		class_preview.texture = load(sprite_path)
	else:
		class_preview.texture = null

	_display_stats(cls.get("base_stats", {}))
	_validate_form()


func _display_stats(stats: Dictionary) -> void:
	for child in stats_container.get_children():
		child.queue_free()

	var stat_order: Array[String] = ["hp", "mp", "strength", "dexterity", "intelligence", "wisdom", "constitution", "luck"]
	var stat_colors: Dictionary = {
		"hp": Color(0.9, 0.3, 0.3),
		"mp": Color(0.3, 0.5, 0.9),
		"strength": Color(0.9, 0.6, 0.3),
		"dexterity": Color(0.3, 0.9, 0.5),
		"intelligence": Color(0.6, 0.3, 0.9),
		"wisdom": Color(0.3, 0.8, 0.8),
		"constitution": Color(0.8, 0.8, 0.3),
		"luck": Color(0.9, 0.7, 0.9),
	}

	for stat_name in stat_order:
		if not stats.has(stat_name):
			continue
		var value: int = int(stats[stat_name])
		var row := HBoxContainer.new()

		var label := Label.new()
		label.text = stat_name.to_upper().left(3) + ":"
		label.add_theme_font_size_override("font_size", 10)
		label.custom_minimum_size.x = 36
		label.add_theme_color_override("font_color", stat_colors.get(stat_name, Color.WHITE))
		row.add_child(label)

		var bar := ProgressBar.new()
		bar.min_value = 0
		bar.max_value = 60
		bar.value = value
		bar.custom_minimum_size = Vector2(80, 10)
		bar.show_percentage = false
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var bar_bg := StyleBoxFlat.new()
		bar_bg.bg_color = Color(0.1, 0.1, 0.15)
		bar.add_theme_stylebox_override("background", bar_bg)
		var bar_fill := StyleBoxFlat.new()
		bar_fill.bg_color = stat_colors.get(stat_name, Color.WHITE) * 0.8
		bar.add_theme_stylebox_override("fill", bar_fill)
		row.add_child(bar)

		var val_label := Label.new()
		val_label.text = str(value)
		val_label.add_theme_font_size_override("font_size", 10)
		val_label.custom_minimum_size.x = 24
		val_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(val_label)

		stats_container.add_child(row)


func _on_name_changed(_new_text: String) -> void:
	_validate_form()


func _validate_form() -> void:
	error_label.text = ""
	var name_text: String = name_input.text.strip_edges()

	if name_text.is_empty():
		confirm_btn.disabled = true
		return
	if name_text.length() < 2:
		error_label.text = "Name must be at least 2 characters."
		confirm_btn.disabled = true
		return
	if name_text.length() > 16:
		error_label.text = "Name must be 16 characters or less."
		confirm_btn.disabled = true
		return
	if selected_class_index < 0:
		error_label.text = "Select a class."
		confirm_btn.disabled = true
		return
	confirm_btn.disabled = false


func _on_confirm() -> void:
	var char_name: String = name_input.text.strip_edges()
	var cls: Dictionary = class_entries[selected_class_index]
	var class_id: String = cls.get("class_id", "knight")

	# If the UI shows "knight" but the data file is "warrior", use warrior for PlayerData
	var actual_class_id: String = class_id
	if class_id == "knight" and PlayerData.class_definitions.has("warrior"):
		actual_class_id = "warrior"

	PlayerData.initialize(char_name, actual_class_id)
	InventoryManager.reset()

	# Add starter equipment
	var starter_equip: Array = cls.get("starter_equipment", [])
	for item_id in starter_equip:
		InventoryManager.add_item(item_id)

	EventBus.character_created.emit(char_name, class_id)
	get_tree().change_scene_to_file(GAME_SCENE)


func _on_back() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _clear_class_preview() -> void:
	class_name_label.text = "Select a class"
	class_desc_label.text = ""
	class_preview.texture = null
	for child in stats_container.get_children():
		child.queue_free()
