extends Area2D
class_name LootDrop
## Dropped loot item. Spawns on enemy death, bounces, can be picked up.

@export var item_id: String = ""
@export var quantity: int = 1

var is_gold: bool = false
var despawn_time: float = 60.0
var elapsed: float = 0.0

# Bounce animation
var bounce_velocity: Vector2 = Vector2.ZERO
var bounce_gravity: float = 300.0
var is_bouncing: bool = true
var ground_y: float = 0.0
var bounce_count: int = 0
const MAX_BOUNCES: int = 3

# Bob animation (after landing)
var bob_offset: float = 0.0
var bob_speed: float = 2.5
var bob_amplitude: float = 2.0
var base_y: float = 0.0

# Pickup
var can_pickup: bool = false
var player_nearby: bool = false

# Hover label
var name_label: Label = null
var item_name: String = ""

@onready var sprite: Sprite2D = null
@onready var collision: CollisionShape2D = null


func _ready() -> void:
	add_to_group("loot_drops")

	# Determine if gold
	is_gold = (item_id == "gold")

	# Look up item name
	if is_gold:
		item_name = "%d Gold" % quantity
	else:
		var item_data: Dictionary = GameData.get_item(item_id)
		item_name = item_data.get("name", item_id.replace("_", " ").capitalize())
		if quantity > 1:
			item_name = "%s x%d" % [item_name, quantity]

	# Create sprite
	sprite = Sprite2D.new()
	sprite.name = "Sprite2D"
	# Gold gets a yellow tint; items get white
	if is_gold:
		sprite.modulate = Color(1.0, 0.9, 0.3, 1.0)
	add_child(sprite)

	# Create collision shape
	collision = CollisionShape2D.new()
	var shape: CircleShape2D = CircleShape2D.new()
	shape.radius = 8.0
	collision.shape = shape
	collision.name = "CollisionShape2D"
	add_child(collision)

	# Setup area detection
	collision_layer = 16  # Interactables layer
	collision_mask = 1    # Player layer
	monitoring = false
	monitorable = true

	# Connect signals
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	# Setup name label (hidden by default)
	name_label = Label.new()
	name_label.text = item_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.position = Vector2(-30, -24)
	name_label.size = Vector2(60, 16)
	name_label.add_theme_font_size_override("font_size", 8)
	name_label.visible = false
	if is_gold:
		name_label.modulate = Color(1.0, 0.9, 0.3, 1.0)
	add_child(name_label)

	# Initialize bounce
	ground_y = global_position.y
	bounce_velocity = Vector2(randf_range(-30, 30), randf_range(-80, -50))

	# Enable pickup after bounce
	await get_tree().create_timer(0.5).timeout
	can_pickup = true
	monitoring = true


func _process(delta: float) -> void:
	elapsed += delta

	# Despawn check
	if elapsed >= despawn_time:
		_despawn()
		return

	# Blink when close to despawn (last 10 seconds)
	if elapsed >= despawn_time - 10.0:
		var blink: float = sin(elapsed * 8.0)
		if sprite:
			sprite.visible = blink > 0.0

	# Bounce physics
	if is_bouncing:
		bounce_velocity.y += bounce_gravity * delta
		position += bounce_velocity * delta

		# Hit ground
		if position.y >= 0.0:
			position.y = 0.0
			bounce_count += 1
			if bounce_count >= MAX_BOUNCES:
				is_bouncing = false
				base_y = position.y
			else:
				bounce_velocity.y = -abs(bounce_velocity.y) * 0.5
				bounce_velocity.x *= 0.7
	else:
		# Gentle bob animation
		bob_offset += bob_speed * delta
		if sprite:
			sprite.position.y = base_y + sin(bob_offset) * bob_amplitude

	# Show label when player is nearby
	if name_label:
		name_label.visible = player_nearby


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_nearby = true
		if can_pickup:
			_pickup(body)


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_nearby = false


func _pickup(_player: Node2D) -> void:
	if is_gold:
		# Add gold to inventory
		var inventory: Node = _find_inventory()
		if inventory and inventory.has_method("add_gold"):
			inventory.add_gold(quantity)
		EventBus.show_notification.emit("Picked up %d gold" % quantity)
	else:
		# Add item to inventory
		EventBus.item_added.emit(item_id, quantity)
		EventBus.show_notification.emit("Picked up %s" % item_name)

	# Pickup visual: quick scale up and fade
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector2(1.5, 1.5), 0.15)
	tween.tween_property(self, "modulate:a", 0.0, 0.15)
	tween.chain().tween_callback(queue_free)


func _despawn() -> void:
	var tween: Tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	tween.tween_callback(queue_free)


func _find_inventory() -> Node:
	# Try to find inventory system in tree
	var inv: Node = get_tree().current_scene.find_child("Inventory", true, false)
	if inv:
		return inv
	# Check autoloads by iterating root children
	for child in get_tree().root.get_children():
		if child.has_method("add_item"):
			return child
	return null


# ---- Tooltip on hover (mouse) ----

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var mouse_pos: Vector2 = get_global_mouse_position()
		var dist: float = mouse_pos.distance_to(global_position)
		if dist < 16.0:
			EventBus.show_tooltip.emit(item_name, global_position + Vector2(0, -30))
		else:
			if player_nearby:
				pass  # Keep label visible from proximity
			else:
				EventBus.hide_tooltip.emit()
