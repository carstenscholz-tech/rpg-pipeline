extends Node
class_name InventorySystem
## Manages the player's inventory.

var slots: Array[Dictionary] = []
var max_slots: int = 28  # RuneScape-style 28 slots
var gold: int = 0


func _ready() -> void:
	EventBus.item_purchased.connect(_on_item_purchased)


func add_item(item_id: String, quantity: int = 1) -> bool:
	var item_data: Dictionary = GameData.get_item(item_id)
	if item_data.is_empty():
		push_warning("Unknown item: " + item_id)
		return false

	# Check if stackable and already exists
	if item_data.get("stackable", false):
		for slot in slots:
			if slot.get("item_id") == item_id:
				slot["quantity"] = slot.get("quantity", 1) + quantity
				EventBus.item_added.emit(item_id, quantity)
				EventBus.inventory_updated.emit()
				return true

	# Add to new slot
	if slots.size() >= max_slots:
		EventBus.show_notification.emit("Inventory is full!")
		return false

	slots.append({"item_id": item_id, "quantity": quantity})
	EventBus.item_added.emit(item_id, quantity)
	EventBus.inventory_updated.emit()
	return true


func remove_item(item_id: String, quantity: int = 1) -> bool:
	for i in range(slots.size()):
		if slots[i].get("item_id") == item_id:
			var current_qty: int = slots[i].get("quantity", 1)
			if current_qty <= quantity:
				slots.remove_at(i)
			else:
				slots[i]["quantity"] = current_qty - quantity
			EventBus.item_removed.emit(item_id, quantity)
			EventBus.inventory_updated.emit()
			return true
	return false


func has_item(item_id: String, quantity: int = 1) -> bool:
	for slot in slots:
		if slot.get("item_id") == item_id:
			return slot.get("quantity", 1) >= quantity
	return false


func get_item_count(item_id: String) -> int:
	for slot in slots:
		if slot.get("item_id") == item_id:
			return slot.get("quantity", 1)
	return 0


func add_gold(amount: int) -> void:
	gold += amount
	EventBus.inventory_updated.emit()


func remove_gold(amount: int) -> bool:
	if gold >= amount:
		gold -= amount
		EventBus.inventory_updated.emit()
		return true
	EventBus.show_notification.emit("Not enough gold!")
	return false


func _on_item_purchased(item_id: String) -> void:
	var item_data: Dictionary = GameData.get_item(item_id)
	var cost: int = item_data.get("value", 0)
	if remove_gold(cost):
		add_item(item_id)


func to_save_data() -> Array:
	return slots.duplicate(true)


func from_save_data(data: Array) -> void:
	slots = data.duplicate(true)
	EventBus.inventory_updated.emit()
