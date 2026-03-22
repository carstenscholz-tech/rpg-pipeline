extends CanvasLayer
class_name ShopUI
## Shop/merchant UI with buy/sell tabs, quantity selector.
## Uses InventoryManager and PlayerData autoloads.

@onready var shop_panel: PanelContainer = %ShopPanel
@onready var shop_list: ItemList = %ShopItemList
@onready var player_list: ItemList = %PlayerItemList
@onready var tab_buy: Button = %TabBuy
@onready var tab_sell: Button = %TabSell
@onready var item_info_label: Label = %ItemInfoLabel
@onready var price_label: Label = %PriceLabel
@onready var quantity_spin: SpinBox = %QuantitySpinBox
@onready var action_btn: Button = %ActionButton
@onready var gold_label: Label = %GoldLabel
@onready var shop_name_label: Label = %ShopNameLabel

var is_open: bool = false
var is_buy_mode: bool = true
var shop_data: Dictionary = {}
var shop_items: Array = []
var selected_item_id: String = ""
var selected_item_price: int = 0


func _ready() -> void:
	shop_panel.visible = false
	_connect_signals()


func _connect_signals() -> void:
	EventBus.open_shop.connect(_on_open_shop)
	InventoryManager.inventory_changed.connect(_on_inventory_changed)
	tab_buy.pressed.connect(_switch_to_buy)
	tab_sell.pressed.connect(_switch_to_sell)
	shop_list.item_selected.connect(_on_shop_item_selected)
	player_list.item_selected.connect(_on_player_item_selected)
	action_btn.pressed.connect(_on_action_pressed)
	quantity_spin.value_changed.connect(_on_quantity_changed)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and is_open:
		close()
		get_viewport().set_input_as_handled()


func _on_open_shop(data: Dictionary) -> void:
	shop_data = data
	shop_items = data.get("items", [])
	shop_name_label.text = data.get("shop_name", "Shop")
	open()


func open() -> void:
	is_open = true
	shop_panel.visible = true
	_switch_to_buy()
	_refresh_gold()


func close() -> void:
	is_open = false
	shop_panel.visible = false
	selected_item_id = ""
	EventBus.shop_closed.emit()


func _switch_to_buy() -> void:
	is_buy_mode = true
	tab_buy.disabled = true
	tab_sell.disabled = false
	action_btn.text = "Buy"
	_refresh_shop_list()
	_clear_selection()


func _switch_to_sell() -> void:
	is_buy_mode = false
	tab_buy.disabled = false
	tab_sell.disabled = true
	action_btn.text = "Sell"
	_refresh_player_list()
	_clear_selection()


func _refresh_shop_list() -> void:
	shop_list.clear()
	for item_entry in shop_items:
		var item_id: String
		var stock: int = -1
		if item_entry is Dictionary:
			item_id = item_entry.get("item_id", "")
			stock = item_entry.get("stock", -1)
		else:
			item_id = str(item_entry)

		var item_def: Dictionary = InventoryManager.get_item_def(item_id)
		if item_def.is_empty():
			continue
		var name: String = item_def.get("name", item_id)
		var price: int = item_def.get("value", 0)
		var display: String = "%s - %dg" % [name, price]
		if stock >= 0:
			display += " (x%d)" % stock
		shop_list.add_item(display)
		shop_list.set_item_metadata(shop_list.item_count - 1, item_id)


func _refresh_player_list() -> void:
	player_list.clear()
	for i in range(InventoryManager.MAX_BAG_SLOTS):
		var slot_data: Variant = InventoryManager.get_bag_slot(i)
		if slot_data == null:
			continue
		var item_id: String = slot_data["item_id"]
		var quantity: int = slot_data["quantity"]
		var item_def: Dictionary = InventoryManager.get_item_def(item_id)
		if item_def.is_empty():
			continue
		var name: String = item_def.get("name", item_id)
		var sell_price: int = int(item_def.get("value", 0) * 0.6)
		var display: String = "%s x%d - %dg ea" % [name, quantity, sell_price]
		player_list.add_item(display)
		player_list.set_item_metadata(player_list.item_count - 1, item_id)

	_refresh_gold()


func _refresh_gold() -> void:
	gold_label.text = "Gold: %d" % PlayerData.gold


func _on_shop_item_selected(index: int) -> void:
	if not is_buy_mode:
		return
	selected_item_id = shop_list.get_item_metadata(index)
	var item_def: Dictionary = InventoryManager.get_item_def(selected_item_id)
	selected_item_price = item_def.get("value", 0)

	item_info_label.text = "%s\n%s" % [
		item_def.get("name", selected_item_id),
		item_def.get("description", ""),
	]
	_update_price_display()
	quantity_spin.value = 1
	quantity_spin.max_value = 99
	action_btn.disabled = false


func _on_player_item_selected(index: int) -> void:
	if is_buy_mode:
		return
	selected_item_id = player_list.get_item_metadata(index)
	var item_def: Dictionary = InventoryManager.get_item_def(selected_item_id)
	selected_item_price = int(item_def.get("value", 0) * 0.6)

	item_info_label.text = "%s\n%s" % [
		item_def.get("name", selected_item_id),
		item_def.get("description", ""),
	]

	var max_qty: int = InventoryManager.count_item(selected_item_id)
	quantity_spin.max_value = maxi(max_qty, 1)
	quantity_spin.value = 1
	_update_price_display()
	action_btn.disabled = false


func _on_quantity_changed(_value: float) -> void:
	_update_price_display()


func _update_price_display() -> void:
	var qty: int = int(quantity_spin.value)
	var total: int = selected_item_price * qty
	if is_buy_mode:
		price_label.text = "Cost: %dg" % total
	else:
		price_label.text = "Earn: %dg" % total


func _on_action_pressed() -> void:
	if selected_item_id.is_empty():
		return
	var qty: int = int(quantity_spin.value)
	if qty <= 0:
		return
	if is_buy_mode:
		_buy_item(selected_item_id, qty)
	else:
		_sell_item(selected_item_id, qty)


func _buy_item(item_id: String, quantity: int) -> void:
	var total_cost: int = selected_item_price * quantity
	if not PlayerData.spend_gold(total_cost):
		EventBus.show_notification.emit("Not enough gold!")
		return

	var overflow: int = 0
	for i in range(quantity):
		var leftover: int = InventoryManager.add_item(item_id)
		overflow += leftover

	if overflow > 0:
		# Refund for items that couldn't fit
		var refund: int = selected_item_price * overflow
		PlayerData.add_gold(refund)
		EventBus.show_notification.emit("Inventory full! Refunded %dg" % refund)

	var bought: int = quantity - overflow
	if bought > 0:
		var item_def: Dictionary = InventoryManager.get_item_def(item_id)
		EventBus.show_notification.emit("Bought %s x%d" % [item_def.get("name", item_id), bought])

	_refresh_gold()
	if not is_buy_mode:
		_refresh_player_list()


func _sell_item(item_id: String, quantity: int) -> void:
	var actual_qty: int = mini(quantity, InventoryManager.count_item(item_id))
	if actual_qty <= 0:
		EventBus.show_notification.emit("You don't have any to sell.")
		return

	InventoryManager.sell_item(item_id, actual_qty)
	_refresh_gold()
	_refresh_player_list()
	_clear_selection()


func _clear_selection() -> void:
	selected_item_id = ""
	selected_item_price = 0
	item_info_label.text = "Select an item"
	price_label.text = ""
	quantity_spin.value = 1
	action_btn.disabled = true


func _on_inventory_changed() -> void:
	if is_open and not is_buy_mode:
		_refresh_player_list()
	if is_open:
		_refresh_gold()
