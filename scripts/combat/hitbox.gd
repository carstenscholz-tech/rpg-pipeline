extends Area2D
class_name Hitbox
## Hitbox component - attach to weapons/attacks to deal damage.
## Detects overlapping Hurtbox areas and applies damage.

@export var damage: int = 1
@export var knockback_force: float = 100.0
@export var is_crit: bool = false
@export var source: Node2D = null  ## The entity that owns this hitbox.

# Track what we've already hit this swing to avoid double-hits
var hit_targets: Array[Node2D] = []
var active: bool = false


func _ready() -> void:
	# Hitbox should detect hurtboxes
	collision_layer = 0
	collision_mask = 0
	monitoring = false
	monitorable = false

	area_entered.connect(_on_area_entered)


## Activate the hitbox for one attack swing.
func activate(attack_damage: int = -1, attacker: Node2D = null) -> void:
	if attack_damage >= 0:
		damage = attack_damage
	if attacker:
		source = attacker
	hit_targets.clear()
	active = true
	monitoring = true
	monitorable = true


## Deactivate after the attack swing ends.
func deactivate() -> void:
	active = false
	monitoring = false
	monitorable = false
	hit_targets.clear()


func _on_area_entered(area: Area2D) -> void:
	if not active:
		return

	if area is Hurtbox:
		var hurtbox: Hurtbox = area
		var owner_node: Node2D = hurtbox.get_parent()

		# Don't hit ourselves
		if owner_node == source:
			return

		# Don't hit the same target twice per swing
		if owner_node in hit_targets:
			return

		hit_targets.append(owner_node)

		# Apply damage through hurtbox
		hurtbox.receive_hit(damage, knockback_force, source, is_crit)
