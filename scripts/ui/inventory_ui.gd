extends CanvasLayer
class_name InventoryUI
## Inventory panel with 28-slot grid, equipment panel, stats, drag-and-drop, and context menu.
## Uses InventoryManager autoload for all data operations.

@onready var inventory_panel: PanelContainer = %InventoryPanel
@onready var equipment_panel: PanelContainer = %EquipmentPanel
@onready var grid_container: GridContainer = %InventoryGrid
@onready var stats_label: Label = %StatsLabel
@onready var context_menu: PopupMenu = %ContextMenu
@onready var tooltip_panel: PanelContainer = %TooltipPanel
@onready var tooltip_name: Label = %TooltipName
@onready var tooltip_desc: Label = %TooltipDesc
@onready var tooltip_stats: Label = %TooltipStats

# Equipment slot references
@onready var equip_head: PanelContainer = %EquipHead
@onready var equip_body: PanelContainer = %EquipBody
@onready var equip_legs: PanelContainer = %EquipLegs
@onready var equip_feet: PanelContainer = %EquipFeet
@onready var equip_weapon: PanelContainer = %EquipWeapon
@onready var equip_shield: PanelContainer = %EquipShield
@onready var equip_ring: PanelContainer = %EquipRing
@onready var equip_amulet: PanelContainer = %EquipAmulet

const SLOT_COUNT: int = 28
const COLUMNS: int = 7

var is_open: bool = false
var inventory_slots: Array[PanelContainer] = []
var dragging: bool = false
var drag_source_index: int = -1
var context_slot_index: int = -1

# Equipment slot mapping
var equip_slot_map: Dictionary = {}


func _ready() -> void:
	inventory_panel.visible = false
	tooltip_panel.visible = false
	_setup_slots()
	_setup_equipment_slots()
	_setup_context_menu()
	_connect_signals()


func _connect_signals() -> void:
	InventoryManager.inventory_changed.connect(_refresh_all)
	EventBus.inventory_updated.connect(_refresh_all)
	context_menu.id_pressed.connect(_on_context_menu_pressed)


func _setup_slots() -> void:
	for child in grid_container.get_children():
		child.queue_free()
	inventory_slots.clear()
	for i in range(SLOT_COUNT):
		var slot := _create_inventory_slot(i)
		grid_container.add_child(slot)
		inventory_slots.append(slot)


func _create_inventory_slot(index: int) -> PanelContainer:
	var slot := PanelContainer.new()
	slot.custom_minimum_size = Vector2(32, 32)
	slot.mouse_filter = Control.MOUSE_FILTER_STOP

	var stylebox := StyleBoxFlat.new()
	stylebox.bg_color = Color(0.12, 0.12, 0.16, 0.9)
	stylebox.border_color = Color(0.4, 0.4, 0.5)
	stylebox.set_border_width_all(1)
	slot.add_theme_stylebox_override("panel", stylebox)

	var icon := TextureRect.new()
	icon.name = "ItemIcon"
	icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(icon)

	var qty_label := Label.new()
	qty_label.name = "QuantityLabel"
	qty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	qty_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	qty_label.add_theme_font_size_override("font_size", 8)
	qty_label.add_theme_color_override("font_color", Color.YELLOW)
	qty_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(qty_label)

	slot.gui_input.connect(_on_slot_input.bind(index))
	slot.mouse_entered.connect(_on_slot_hover.bind(index))
	slot.mouse_exited.connect(_on_slot_exit)

	return slot


func _setup_equipment_slots() -> void:
	equip_slot_map = {
		"head": equip_head,
		"body": equip_body,
		"legs": equip_legs,
		"feet": equip_feet,
		"weapon": equip_weapon,
		"shield": equip_shield,
		"ring": equip_ring,
		"amulet": equip_amulet,
	}


func _setup_context_menu() -> void:
	context_menu.clear()
	context_menu.add_item("Use", 0)
	context_menu.add_item("Equip", 1)
	context_menu.add_item("Drop", 2)
	context_menu.add_item("Examine", 3)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory"):
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
	inventory_panel.visible = true
	_refresh_all()


func close() -> void:
	is_open = false
	inventory_panel.visible = false
	tooltip_panel.visible = false
	dragging = false
	drag_source_index = -1


func _on_slot_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if dragging:
				_complete_drag(index)
			else:
				_start_drag(index)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_show_context_menu(index, event.global_position)


func _start_drag(index: int) -> void:
	var slot_data: Variant = InventoryManager.get_bag_slot(index)
	if slot_data == null:
		return
	dragging = true
	drag_source_index = index
	# Highlight the source slot
	var slot: PanelContainer = inventory_slots[index]
	var stylebox := StyleBoxFlat.new()
	stylebox.bg_color = Color(0.2, 0.2, 0.1, 0.9)
	stylebox.border_color = Color.GOLD
	stylebox.set_border_width_all(2)
	slot.add_theme_stylebox_override("panel", stylebox)


func _complete_drag(target_index: int) -> void:
	if not dragging or drag_source_index < 0:
		dragging = false
		return
	InventoryManager.swap_bag_slots(drag_source_index, target_index)
	dragging = false
	drag_source_index = -1
	_refresh_all()


func _show_context_menu(index: int, pos: Vector2) -> void:
	var slot_data: Variant = InventoryManager.get_bag_slot(index)
	if slot_data == null:
		return
	context_slot_index = index
	context_menu.position = Vector2i(int(pos.x), int(pos.y))
	context_menu.popup()


func _on_context_menu_pressed(id: int) -> void:
	if context_slot_index < 0:
		return
	var slot_data: Variant = InventoryManager.get_bag_slot(context_slot_index)
	if slot_data == null:
		context_slot_index = -1
		return

	var item_id: String = slot_data["item_id"]

	match id:
		0:  # Use
			InventoryManager.use_item(item_id)
		1:  # Equip
			InventoryManager.equip_item(item_id)
		2:  # Drop
			InventoryManager.drop_item(item_id)
			EventBus.show_notification.emit("Dropped item.")
		3:  # Examine
			var item_def: Dictionary = InventoryManager.get_item_def(item_id)
			var desc: String = item_def.get("description", "No description.")
			EventBus.show_notification.emit(desc)
	context_slot_index = -1


func _on_slot_hover(index: int) -> void:
	var slot_data: Variant = InventoryManager.get_bag_slot(index)
	if slot_data == null:
		tooltip_panel.visible = false
		return

	var item_id: String = slot_data["item_id"]
	var item_def: Dictionary = InventoryManager.get_item_def(item_id)
	if item_def.is_empty():
		tooltip_panel.visible = false
		return

	tooltip_name.text = item_def.get("name", "Unknown")
	tooltip_desc.text = item_def.get("description", "")

	var stats: Dictionary = item_def.get("stats", {})
	var stats_text: String = ""
	for key in stats:
		if stats[key] != null and stats[key] != 0:
			stats_text += "%s: %s\n" % [key.capitalize().replace("_", " "), str(stats[key])]
	var value: int = item_def.get("value", 0)
	if value > 0:
		stats_text += "Value: %d gold" % value
	tooltip_stats.text = stats_text.strip_edges()
	tooltip_panel.visible = true

	# Position tooltip near mouse
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	tooltip_panel.global_position = mouse_pos + Vector2(12, 12)


func _on_slot_exit() -> void:
	tooltip_panel.visible = false


func _refresh_all() -> void:
	if not is_open:
		return
	_refresh_inventory()
	_refresh_equipment()
	_update_stats_display()


func _refresh_inventory() -> void:
	for i in range(SLOT_COUNT):
		var slot: PanelContainer = inventory_slots[i]
		var icon: TextureRect = slot.get_node("ItemIcon") as TextureRect
		var qty_label: Label = slot.get_node("QuantityLabel") as Label

		# Reset slot style
		var stylebox := StyleBoxFlat.new()
		stylebox.bg_color = Color(0.12, 0.12, 0.16, 0.9)
		stylebox.border_color = Color(0.4, 0.4, 0.5)
		stylebox.set_border_width_all(1)
		slot.add_theme_stylebox_override("panel", stylebox)

		var slot_data: Variant = InventoryManager.get_bag_slot(i)
		if slot_data != null:
			var item_id: String = slot_data["item_id"]
			var quantity: int = slot_data["quantity"]
			# Try to load item sprite
			var item_def: Dictionary = InventoryManager.get_item_def(item_id)
			var sprite_id: String = item_def.get("sprite_id", item_id)
			var tex_path: String = "res://assets/sprites/items/%s.png" % sprite_id
			if ResourceLoader.exists(tex_path):
				icon.texture = load(tex_path)
			else:
				icon.texture = null
			qty_label.text = str(quantity) if quantity > 1 else ""
		else:
			icon.texture = null
			qty_label.text = ""


func _refresh_equipment() -> void:
	for slot_name in equip_slot_map:
		var panel: PanelContainer = equip_slot_map[slot_name]
		if not panel:
			continue
		var label: Label = panel.get_node_or_null("SlotLabel") as Label
		var icon: TextureRect = panel.get_node_or_null("ItemIcon") as TextureRect
		var item_id: String = InventoryManager.get_equipped_item(slot_name)
		if icon:
			if not item_id.is_empty():
				var item_def: Dictionary = InventoryManager.get_item_def(item_id)
				var sprite_id: String = item_def.get("sprite_id", item_id)
				var tex_path: String = "res://assets/sprites/items/%s.png" % sprite_id
				if ResourceLoader.exists(tex_path):
					icon.texture = load(tex_path)
				else:
					icon.texture = null
				if label:
					label.text = item_def.get("name", slot_name.capitalize())
			else:
				icon.texture = null
				if label:
					label.text = slot_name.capitalize()


func _update_stats_display() -> void:
	var equip_stats: Dictionary = InventoryManager.get_equipment_stats()
	stats_label.text = "ATK: %d\nDEF: %d\nMAG: %d" % [
		PlayerData.attack,
		PlayerData.defense,
		PlayerData.magic_attack,
	]
