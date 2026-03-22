extends Node
class_name PlayerAnimation
## Manages the player sprite sheet animation.
##
## Expected sprite sheet layout (4 rows x 3 columns):
##   Row 0 (front / down):  idle, step_left, step_right
##   Row 1 (back  / up):    idle, step_left, step_right
##   Row 2 (left):          idle, step_left, step_right
##   Row 3 (right):         idle, step_left, step_right
##
## The script uses Sprite2D.hframes / vframes to index into the sheet.

const ANIM_FPS: float = 6.0
const ATTACK_ANIM_FPS: float = 10.0

## Row indices matching the sprite sheet layout.
enum Row { FRONT = 0, BACK = 1, LEFT = 2, RIGHT = 3 }

var _anim_time: float = 0.0
var _current_row: int = Row.FRONT
var _is_moving: bool = false
var _is_attacking: bool = false
var _attack_timer: float = 0.0

@onready var sprite: Sprite2D = get_parent().get_node("Sprite2D")


func _ready() -> void:
	# Ensure the sprite sheet is configured correctly.
	if sprite:
		sprite.hframes = 3
		sprite.vframes = 4
		sprite.frame = 0


func _process(delta: float) -> void:
	if not sprite:
		return

	if _is_attacking:
		_attack_timer -= delta
		if _attack_timer <= 0.0:
			_is_attacking = false
		_anim_time += delta * ATTACK_ANIM_FPS
		# During attack, cycle columns 1-2 rapidly.
		var col: int = 1 + (int(_anim_time) % 2)
		sprite.frame = _current_row * 3 + col
		return

	if _is_moving:
		_anim_time += delta * ANIM_FPS
		# Walk cycle: col 0 -> 1 -> 0 -> 2 -> repeat
		var walk_frames: Array[int] = [0, 1, 0, 2]
		var col: int = walk_frames[int(_anim_time) % walk_frames.size()]
		sprite.frame = _current_row * 3 + col
	else:
		# Idle: always column 0.
		_anim_time = 0.0
		sprite.frame = _current_row * 3


## Called by PlayerController each physics frame.
func update_animation(facing: Vector2, moving: bool) -> void:
	_is_moving = moving
	_current_row = _direction_to_row(facing)


## Start the attack animation overlay.
func play_attack(facing: Vector2) -> void:
	_is_attacking = true
	_attack_timer = 0.25
	_anim_time = 0.0
	_current_row = _direction_to_row(facing)


## Convert a facing vector to a sprite sheet row index.
func _direction_to_row(dir: Vector2) -> int:
	if dir == Vector2.UP:
		return Row.BACK
	elif dir == Vector2.DOWN:
		return Row.FRONT
	elif dir == Vector2.LEFT:
		return Row.LEFT
	elif dir == Vector2.RIGHT:
		return Row.RIGHT
	# Default to front.
	return Row.FRONT
