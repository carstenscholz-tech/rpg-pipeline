extends Node2D
class_name DamageNumber
## Floating damage number that spawns at hit position, floats up, and fades out.

var amount: int = 0
var is_crit: bool = false
var is_heal: bool = false
var is_player_damage: bool = false

var float_speed: float = 40.0
var float_direction: Vector2 = Vector2.ZERO
var lifetime: float = 1.0
var elapsed: float = 0.0

@onready var label: Label = null


func _ready() -> void:
	# Create label dynamically
	label = Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	# Set text
	if is_heal:
		label.text = "+%d" % amount
	else:
		label.text = str(amount)
		if is_crit:
			label.text += "!"

	# Set color
	if is_heal:
		label.modulate = Color(0.2, 1.0, 0.2, 1.0)  # Green
	elif is_crit:
		label.modulate = Color(1.0, 1.0, 0.0, 1.0)  # Yellow
	elif is_player_damage:
		label.modulate = Color(1.0, 0.2, 0.2, 1.0)  # Red
	else:
		label.modulate = Color.WHITE  # White normal

	# Set font size based on damage type
	if is_crit:
		label.add_theme_font_size_override("font_size", 14)
	else:
		label.add_theme_font_size_override("font_size", 10)

	# Center the label
	label.position = Vector2(-20, -10)
	label.size = Vector2(40, 20)

	add_child(label)

	# Random horizontal offset for variety
	float_direction = Vector2(randf_range(-0.3, 0.3), -1.0).normalized()

	# Crit numbers float a bit higher
	if is_crit:
		float_speed *= 1.3


func _process(delta: float) -> void:
	elapsed += delta

	# Float upward
	position += float_direction * float_speed * delta

	# Slight deceleration
	float_speed = lerpf(float_speed, 10.0, delta * 2.0)

	# Fade out
	var alpha: float = 1.0 - (elapsed / lifetime)
	if label:
		label.modulate.a = alpha

	# Scale pop effect in first 0.1 seconds
	if elapsed < 0.1:
		var t: float = elapsed / 0.1
		var s: float = 1.0 + 0.5 * (1.0 - t)  # Scale from 1.5 to 1.0
		scale = Vector2(s, s)
	else:
		scale = Vector2.ONE

	# Remove when done
	if elapsed >= lifetime:
		queue_free()
