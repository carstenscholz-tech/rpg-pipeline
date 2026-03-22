extends Node
## Inventory system. Manages bag slots, equipment, stacking, and item operations.

# --- Signals ---
signal inventory_changed()
signal item_added(item_id: String, quantity: int)
signal item_removed(item_id: String, quantity: int)
signal item_equipped(item_id: String, slot: String)
signal item_unequipped(item_id: String, slot: String)
signal item_used(item_id: String)
signal inventory_full()

# --- Constants ---
const MAX_BAG_SLOTS: int = 28
const MAX_STACK_CONSUMABLE: int = 99
const MAX_STACK_MATERIAL: int = 999

# --- Equipment Slot Names ---
enum EquipSlot {
	HEAD,
	BODY,
	LEGS,
	FEET,
	WEAPON,
	SHIELD,
	RING,
	AMULET,
}

const EQUIP_SLOT_NAMES: Dictionary = {
	EquipSlot.HEAD: "head",
	EquipSlot.BODY: "body",
	EquipSlot.LEGS: "legs",
	EquipSlot.FEET: "feet",
	EquipSlot.WEAPON: "weapon",
	EquipSlot.SHIELD: "shield",
	EquipSlot.RING: "ring",
	EquipSlot.AMULET: "amulet",
}

# --- Item Definitions (loaded from GameData) ---
var item_definitions: Dictionary = {}

# --- Bag: Array of { "item_id": String, "quantity": int } or null for empty slots ---
var bag: Array = []

# --- Equipment: slot_name -> item_id (or "" if empty) ---
var equipment: Dictionary = {
	"head": "",
	"body": "",
	"legs": "",
	"feet": "",
	"weapon": "",
	"shield": "",
	"ring": "",
	"amulet": "",
}


func _ready() -> void:
	_initialize_bag()
	# Defer item loading until GameData is ready
	call_deferred("_load_item_definitions")


func _initialize_bag() -> void:
	bag.clear()
	for i in range(MAX_BAG_SLOTS):
		bag.append(null)


func _load_item_definitions() -> void:
	## Build a flat item_id -> item_data lookup from all item data files.
	item_definitions.clear()

	# Pull from GameData which loads data/items/*.json
	for file_key in GameData.items:
		var file_data: Dictionary = GameData.items[file_key]
		# Items files have an "items" array
		if file_data.has("items"):
			var items_array: Array = file_data["items"]
			for item_data in items_array:
				var item_id: String = item_data.get("item_id", "")
				if item_id != "":
					item_definitions[item_id] = item_data
		else:
			# Single item entry
			var item_id: String = file_data.get("item_id", file_key)
			item_definitions[item_id] = file_data

	print("InventoryManager: Indexed %d item definitions" % item_definitions.size())


func get_item_def(item_id: String) -> Dictionary:
	## Get the static definition for an item by ID.
	return item_definitions.get(item_id, {})


# --- Max Stack Size ---

func get_max_stack(item_id: String) -> int:
	var def: Dictionary = get_item_def(item_id)
	if not def.get("stackable", false):
		return 1
	var item_type: String = def.get("type", "")
	match item_type:
		"consumable", "tool":
			return MAX_STACK_CONSUMABLE
		"material":
			return MAX_STACK_MATERIAL
		_:
			return 1


# --- Adding Items ---

func add_item(item_id: String, quantity: int = 1) -> int:
	## Add items to the bag. Returns the number of items that could NOT be added (overflow).
	var remaining: int = quantity
	var max_stack: int = get_max_stack(item_id)

	# First, try to stack with existing slots
	if max_stack > 1:
		for i in range(MAX_BAG_SLOTS):
			if remaining <= 0:
				break
			if bag[i] != null and bag[i]["item_id"] == item_id:
				var space: int = max_stack - bag[i]["quantity"]
				if space > 0:
					var to_add: int = mini(remaining, space)
					bag[i]["quantity"] += to_add
					remaining -= to_add

	# Then, fill empty slots
	for i in range(MAX_BAG_SLOTS):
		if remaining <= 0:
			break
		if bag[i] == null:
			var to_add: int = mini(remaining, max_stack)
			bag[i] = {"item_id": item_id, "quantity": to_add}
			remaining -= to_add

	var added: int = quantity - remaining
	if added > 0:
		item_added.emit(item_id, added)
		EventBus.item_added.emit(item_id, added)
		inventory_changed.emit()
		EventBus.inventory_updated.emit()

	if remaining > 0:
		inventory_full.emit()
		EventBus.show_notification.emit("Inventory full! %d item(s) lost." % remaining)

	return remaining


func remove_item(item_id: String, quantity: int = 1) -> bool:
	## Remove items from the bag. Returns true if successful.
	if count_item(item_id) < quantity:
		return false

	var remaining: int = quantity

	# Remove from bag slots (start from end to keep ordering consistent)
	for i in range(MAX_BAG_SLOTS - 1, -1, -1):
		if remaining <= 0:
			break
		if bag[i] != null and bag[i]["item_id"] == item_id:
			var to_remove: int = mini(remaining, bag[i]["quantity"])
			bag[i]["quantity"] -= to_remove
			remaining -= to_remove
			if bag[i]["quantity"] <= 0:
				bag[i] = null

	if remaining <= 0:
		item_removed.emit(item_id, quantity)
		EventBus.item_removed.emit(item_id, quantity)
		inventory_changed.emit()
		EventBus.inventory_updated.emit()
		return true

	return false


func remove_item_at_slot(slot_index: int, quantity: int = 1) -> bool:
	if slot_index < 0 or slot_index >= MAX_BAG_SLOTS:
		return false
	if bag[slot_index] == null:
		return false

	var item_id: String = bag[slot_index]["item_id"]
	var current_qty: int = bag[slot_index]["quantity"]
	var to_remove: int = mini(quantity, current_qty)

	bag[slot_index]["quantity"] -= to_remove
	if bag[slot_index]["quantity"] <= 0:
		bag[slot_index] = null

	item_removed.emit(item_id, to_remove)
	EventBus.item_removed.emit(item_id, to_remove)
	inventory_changed.emit()
	EventBus.inventory_updated.emit()
	return true


# --- Counting ---

func count_item(item_id: String) -> int:
	var total: int = 0
	for slot in bag:
		if slot != null and slot["item_id"] == item_id:
			total += slot["quantity"]
	return total


func has_item(item_id: String, quantity: int = 1) -> bool:
	return count_item(item_id) >= quantity


func get_free_slots() -> int:
	var count: int = 0
	for slot in bag:
		if slot == null:
			count += 1
	return count


func is_bag_full() -> bool:
	return get_free_slots() == 0


# --- Equipment ---

func equip_item(item_id: String) -> bool:
	## Equip an item from the bag. Returns true if successful.
	if not has_item(item_id):
		return false

	var def: Dictionary = get_item_def(item_id)
	if def.is_empty():
		return false

	# Determine the equipment slot
	var slot_name: String = _get_equip_slot_for_item(def)
	if slot_name == "":
		EventBus.show_notification.emit("This item cannot be equipped.")
		return false

	# Check level requirement
	var level_req: int = def.get("level_requirement", 0)
	if PlayerData.level < level_req:
		EventBus.show_notification.emit("Requires level %d to equip." % level_req)
		return false

	# Unequip current item in that slot (put back in bag)
	if equipment[slot_name] != "":
		var old_item: String = equipment[slot_name]
		equipment[slot_name] = ""
		var overflow := add_item(old_item)
		if overflow > 0:
			# Can't fit old item back, abort
			equipment[slot_name] = old_item
			EventBus.show_notification.emit("No room to unequip current item.")
			return false
		item_unequipped.emit(old_item, slot_name)

	# Remove new item from bag and equip
	remove_item(item_id)
	equipment[slot_name] = item_id

	item_equipped.emit(item_id, slot_name)
	inventory_changed.emit()
	PlayerData.recalculate()
	return true


func unequip_slot(slot_name: String) -> bool:
	## Unequip an item from a slot and put it in the bag.
	if not equipment.has(slot_name):
		return false
	if equipment[slot_name] == "":
		return false
	if is_bag_full():
		EventBus.show_notification.emit("Inventory full. Cannot unequip.")
		return false

	var item_id: String = equipment[slot_name]
	equipment[slot_name] = ""
	add_item(item_id)

	item_unequipped.emit(item_id, slot_name)
	inventory_changed.emit()
	PlayerData.recalculate()
	return true


func get_equipped_item(slot_name: String) -> String:
	return equipment.get(slot_name, "")


func get_equipment_stats() -> Dictionary:
	## Sum up stat bonuses from all equipped items.
	var totals: Dictionary = {
		"attack_bonus": 0,
		"defense_bonus": 0,
		"magic_bonus": 0,
		"speed_bonus": 0.0,
		"block_chance": 0.0,
	}
	for slot_name in equipment:
		var item_id: String = equipment[slot_name]
		if item_id == "":
			continue
		var def: Dictionary = get_item_def(item_id)
		var stats: Dictionary = def.get("stats", {})
		totals["attack_bonus"] += stats.get("attack_bonus", 0)
		totals["defense_bonus"] += stats.get("defense_bonus", 0)
		totals["magic_bonus"] += stats.get("magic_bonus", 0)
		totals["speed_bonus"] += stats.get("speed_bonus", 0.0)
		totals["block_chance"] += stats.get("block_chance", 0.0)
	return totals


func _get_equip_slot_for_item(item_def: Dictionary) -> String:
	var item_type: String = item_def.get("type", "")
	var subtype: String = item_def.get("subtype", "")

	if item_type == "weapon":
		return "weapon"
	elif item_type == "armor":
		match subtype:
			"chest":
				return "body"
			"helmet":
				return "head"
			"boots":
				return "feet"
			"legs", "leggings":
				return "legs"
			"shield":
				return "shield"
			"accessory":
				# Determine ring vs amulet based on name or just default to amulet
				var name_lower: String = item_def.get("name", "").to_lower()
				if "ring" in name_lower or "band" in name_lower:
					return "ring"
				else:
					return "amulet"
	return ""


# --- Use Item ---

func use_item(item_id: String) -> bool:
	## Use a consumable item. Returns true if successful.
	if not has_item(item_id):
		return false

	var def: Dictionary = get_item_def(item_id)
	if def.is_empty():
		return false

	var item_type: String = def.get("type", "")

	if item_type == "consumable":
		var stats: Dictionary = def.get("stats", {})

		# HP restore
		if stats.has("hp_restore"):
			PlayerData.heal(int(stats["hp_restore"]))

		# MP restore
		if stats.has("mana_restore"):
			PlayerData.restore_mp(int(stats["mana_restore"]))

		# Cure poison
		if stats.get("cure_poison", false):
			# Signal to combat/status system
			EventBus.show_notification.emit("Poison cured!")

		# Cure all
		if stats.get("cure_all", false):
			EventBus.show_notification.emit("All ailments cured!")

		remove_item(item_id)
		item_used.emit(item_id)
		EventBus.show_notification.emit("Used %s" % def.get("name", item_id))
		return true

	elif item_type == "weapon" or item_type == "armor":
		# Equippable items are equipped instead of "used"
		return equip_item(item_id)

	return false


# --- Drop / Sell ---

func drop_item(item_id: String, quantity: int = 1) -> bool:
	return remove_item(item_id, quantity)


func sell_item(item_id: String, quantity: int = 1) -> bool:
	var def: Dictionary = get_item_def(item_id)
	if def.is_empty():
		return false

	var sell_price: int = int(def.get("value", 0) * 0.6)  # Sell for 60% of value
	var total_count: int = count_item(item_id)
	var actual_qty: int = mini(quantity, total_count)

	if actual_qty <= 0:
		return false

	if remove_item(item_id, actual_qty):
		var gold_earned: int = sell_price * actual_qty
		PlayerData.add_gold(gold_earned)
		EventBus.item_sold.emit(item_id)
		EventBus.show_notification.emit("Sold %s x%d for %d gold" % [def.get("name", item_id), actual_qty, gold_earned])
		return true
	return false


# --- Bag Slot Queries ---

func get_bag_slot(index: int) -> Variant:
	## Returns the bag slot data or null. { "item_id": String, "quantity": int }
	if index < 0 or index >= MAX_BAG_SLOTS:
		return null
	return bag[index]


func swap_bag_slots(from_index: int, to_index: int) -> void:
	if from_index < 0 or from_index >= MAX_BAG_SLOTS:
		return
	if to_index < 0 or to_index >= MAX_BAG_SLOTS:
		return
	var temp: Variant = bag[from_index]
	bag[from_index] = bag[to_index]
	bag[to_index] = temp
	inventory_changed.emit()


# --- Serialization ---

func serialize() -> Dictionary:
	var bag_data: Array = []
	for slot in bag:
		if slot != null:
			bag_data.append(slot.duplicate())
		else:
			bag_data.append(null)
	return {
		"bag": bag_data,
		"equipment": equipment.duplicate(),
	}


func deserialize(data: Dictionary) -> void:
	_initialize_bag()
	var bag_data: Array = data.get("bag", [])
	for i in range(mini(bag_data.size(), MAX_BAG_SLOTS)):
		bag[i] = bag_data[i]

	var equip_data: Dictionary = data.get("equipment", {})
	for slot_name in equipment:
		equipment[slot_name] = equip_data.get(slot_name, "")

	inventory_changed.emit()
	EventBus.inventory_updated.emit()
	PlayerData.recalculate()


func reset() -> void:
	_initialize_bag()
	for slot_name in equipment:
		equipment[slot_name] = ""
	inventory_changed.emit()
	EventBus.inventory_updated.emit()
