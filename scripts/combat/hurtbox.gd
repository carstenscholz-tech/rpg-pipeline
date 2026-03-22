extends Area2D
class_name Hurtbox
## Hurtbox component - attach to entities that can receive damage.
## Handles invincibility frames after being hit.

signal hit_received(damage: int, knockback: float, attacker: Node2D, is_crit: bool)

@export var invincibility_duration: float = 0.3

var invincible: bool = false
var invincibility_timer: float = 0.0


func _ready() -> void:
	# Hurtbox is detectable by hitboxes
	collision_layer = 0
	collision_mask = 0
	monitoring = false
	monitorable = true


func _process(delta: float) -> void:
	if invincible:
		invincibility_timer -= delta
		if invincibility_timer <= 0.0:
			invincible = false
			# Restore normal appearance
			var parent: Node2D = get_parent()
			if parent:
				parent.modulate.a = 1.0


## Called by Hitbox when it overlaps this Hurtbox.
func receive_hit(damage: int, knockback: float, attacker: Node2D, is_crit: bool = false) -> void:
	if invincible:
		return

	# Start invincibility frames
	invincible = true
	invincibility_timer = invincibility_duration

	# Flash effect during invincibility
	_flash_invincible()

	# Emit signal for the parent to handle
	hit_received.emit(damage, knockback, attacker, is_crit)

	# Try to call take_damage on parent directly
	var parent: Node2D = get_parent()
	if parent and parent.has_method("take_damage"):
		parent.take_damage(damage, attacker)
	elif parent and parent.is_in_group("player"):
		EventBus.player_damaged.emit(damage)
	elif parent and parent.is_in_group("enemies"):
		EventBus.enemy_damaged.emit(parent.get("enemy_id"), damage)

	# Apply knockback
	if knockback > 0.0 and attacker and parent:
		_apply_knockback(parent, attacker, knockback)


func _apply_knockback(target: Node2D, attacker: Node2D, force: float) -> void:
	if not is_instance_valid(target) or not is_instance_valid(attacker):
		return

	var knockback_dir: Vector2 = (target.global_position - attacker.global_position).normalized()

	if target is CharacterBody2D:
		target.velocity = knockback_dir * force


func _flash_invincible() -> void:
	var parent: Node2D = get_parent()
	if not parent:
		return

	# Blink effect: alternate visibility
	var tween: Tween = create_tween()
	var flashes: int = int(invincibility_duration / 0.1)
	for i in range(flashes):
		tween.tween_property(parent, "modulate:a", 0.3, 0.05)
		tween.tween_property(parent, "modulate:a", 1.0, 0.05)
	tween.tween_property(parent, "modulate:a", 1.0, 0.0)


## Check if currently invincible.
func is_invincible() -> bool:
	return invincible


## Manually set invincibility (e.g., during dodge roll).
func set_invincible(duration: float) -> void:
	invincible = true
	invincibility_timer = duration
