extends CharacterBody2D
## Player character controller. WASD movement, E to interact.

const SPEED: float = 120.0

var current_direction: String = "down"
var can_interact: bool = false
var nearby_interactable: Node2D = null

@onready var sprite: Sprite2D = $Sprite2D
@onready var interaction_ray: RayCast2D = $InteractionRay
@onready var camera: Camera2D = $Camera2D


func _ready() -> void:
	add_to_group("player")


func _physics_process(_delta: float) -> void:
	var input_dir := Vector2.ZERO
	input_dir.x = Input.get_axis("move_left", "move_right")
	input_dir.y = Input.get_axis("move_up", "move_down")

	if input_dir != Vector2.ZERO:
		input_dir = input_dir.normalized()
		velocity = input_dir * SPEED
		_update_direction(input_dir)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, SPEED)

	move_and_slide()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		_try_interact()


func _update_direction(dir: Vector2) -> void:
	if abs(dir.x) > abs(dir.y):
		current_direction = "right" if dir.x > 0 else "left"
	else:
		current_direction = "down" if dir.y > 0 else "up"

	# Update raycast direction for interaction
	match current_direction:
		"up":
			interaction_ray.target_position = Vector2(0, -20)
		"down":
			interaction_ray.target_position = Vector2(0, 20)
		"left":
			interaction_ray.target_position = Vector2(-20, 0)
		"right":
			interaction_ray.target_position = Vector2(20, 0)


func _try_interact() -> void:
	if interaction_ray.is_colliding():
		var collider := interaction_ray.get_collider()
		if collider and collider.has_method("interact"):
			collider.interact()
			EventBus.npc_interacted.emit(collider.get("npc_id"))
