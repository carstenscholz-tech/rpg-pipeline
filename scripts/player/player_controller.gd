extends CharacterBody2D
class_name PlayerController
## Main player controller handling movement, input, and state management.
## Emits signals through EventBus for cross-system communication.

enum State { IDLE, WALKING, SPRINTING, ATTACKING, FROZEN }

const WALK_SPEED: float = 80.0
const SPRINT_SPEED: float = 120.0
const FRICTION: float = 600.0

## Current facing direction as a unit-ish vector (snapped to 4 or 8 dir).
var facing_direction: Vector2 = Vector2.DOWN
## Current movement state.
var state: State = State.IDLE
## When true the player cannot move (dialogue, cutscene, menu).
var input_frozen: bool = false

# Attack cooldown tracking.
var _attack_cooldown: float = 0.0
const ATTACK_COOLDOWN_TIME: float = 0.4
const ATTACK_DURATION: float = 0.25
var _attack_timer: float = 0.0

# Footstep audio timer.
var _footstep_timer: float = 0.0
const FOOTSTEP_INTERVAL: float = 0.3

@onready var animation_handler: Node = $PlayerAnimation
@onready var interaction_handler: Node = $InteractionZone/InteractionHandler
@onready var sprite: Sprite2D = $Sprite2D
@onready var camera: Camera2D = $GameCamera
@onready var footstep_audio: AudioStreamPlayer2D = $FootstepAudio


func _ready() -> void:
	add_to_group("player")
	# Listen for freeze/unfreeze from dialogue and other systems.
	EventBus.start_dialogue.connect(_on_dialogue_started)
	EventBus.dialogue_ended.connect(_on_dialogue_ended)


func _physics_process(delta: float) -> void:
	if state == State.ATTACKING:
		_attack_timer -= delta
		if _attack_timer <= 0.0:
			_end_attack()
		# During attack, decelerate but don't accept new input.
		velocity = velocity.move_toward(Vector2.ZERO, FRICTION * delta)
		move_and_slide()
		return

	if input_frozen or state == State.FROZEN:
		velocity = Vector2.ZERO
		return

	# --- Gather input ---
	var input_dir := Vector2.ZERO
	input_dir.x = Input.get_axis("move_left", "move_right")
	input_dir.y = Input.get_axis("move_up", "move_down")

	var is_sprinting: bool = Input.is_action_pressed("sprint")

	# --- Apply movement ---
	if input_dir != Vector2.ZERO:
		input_dir = input_dir.normalized()
		var speed: float = SPRINT_SPEED if is_sprinting else WALK_SPEED
		velocity = input_dir * speed
		_update_facing(input_dir)

		var new_state: State = State.SPRINTING if is_sprinting else State.WALKING
		if state != new_state:
			_set_state(new_state)

		# Footstep sound.
		_footstep_timer -= delta
		if _footstep_timer <= 0.0:
			_play_footstep()
			_footstep_timer = FOOTSTEP_INTERVAL

		EventBus.player_moved.emit(global_position)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, FRICTION * delta)
		if state != State.IDLE:
			_set_state(State.IDLE)
			_footstep_timer = 0.0

	move_and_slide()

	# Update attack cooldown.
	if _attack_cooldown > 0.0:
		_attack_cooldown -= delta

	# Update animation.
	if animation_handler:
		animation_handler.update_animation(facing_direction, state != State.IDLE)


func _unhandled_input(event: InputEvent) -> void:
	if input_frozen or state == State.FROZEN:
		return

	if event.is_action_pressed("interact"):
		_try_interact()

	if event.is_action_pressed("attack") and _attack_cooldown <= 0.0 and state != State.ATTACKING:
		_start_attack()


# ---------------------------------------------------------------------------
# Direction
# ---------------------------------------------------------------------------

func _update_facing(input_dir: Vector2) -> void:
	# Snap to the dominant axis for 4-directional sprite facing.
	if abs(input_dir.x) > abs(input_dir.y):
		facing_direction = Vector2.RIGHT if input_dir.x > 0.0 else Vector2.LEFT
	else:
		facing_direction = Vector2.DOWN if input_dir.y > 0.0 else Vector2.UP

	# Point the interaction zone in the facing direction.
	if interaction_handler:
		interaction_handler.update_facing(facing_direction)


## Returns the facing direction as one of "down", "up", "left", "right".
func get_facing_name() -> String:
	if facing_direction == Vector2.UP:
		return "up"
	elif facing_direction == Vector2.DOWN:
		return "down"
	elif facing_direction == Vector2.LEFT:
		return "left"
	else:
		return "right"


# ---------------------------------------------------------------------------
# Attack
# ---------------------------------------------------------------------------

func _start_attack() -> void:
	_set_state(State.ATTACKING)
	_attack_timer = ATTACK_DURATION
	_attack_cooldown = ATTACK_COOLDOWN_TIME
	EventBus.player_attacked.emit(facing_direction)
	if animation_handler:
		animation_handler.play_attack(facing_direction)


func _end_attack() -> void:
	_set_state(State.IDLE)


# ---------------------------------------------------------------------------
# Interaction
# ---------------------------------------------------------------------------

func _try_interact() -> void:
	if interaction_handler and interaction_handler.has_method("try_interact"):
		interaction_handler.try_interact()


# ---------------------------------------------------------------------------
# State management
# ---------------------------------------------------------------------------

func _set_state(new_state: State) -> void:
	if state == new_state:
		return
	state = new_state
	EventBus.player_state_changed.emit(State.keys()[new_state].to_lower())


func freeze() -> void:
	input_frozen = true
	velocity = Vector2.ZERO
	_set_state(State.FROZEN)
	if animation_handler:
		animation_handler.update_animation(facing_direction, false)


func unfreeze() -> void:
	input_frozen = false
	_set_state(State.IDLE)


# ---------------------------------------------------------------------------
# Audio
# ---------------------------------------------------------------------------

func _play_footstep() -> void:
	if footstep_audio and footstep_audio.stream:
		footstep_audio.pitch_scale = randf_range(0.9, 1.1)
		footstep_audio.play()


# ---------------------------------------------------------------------------
# Signal callbacks
# ---------------------------------------------------------------------------

func _on_dialogue_started(_npc_id: String, _data: Dictionary) -> void:
	freeze()


func _on_dialogue_ended() -> void:
	unfreeze()
