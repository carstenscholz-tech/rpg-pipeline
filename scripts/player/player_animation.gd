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
		# Load sprite sheet texture if none is assigned.
		if sprite.texture == null:
			sprite.texture = _load_player_texture()
		sprite.hframes = 3
		sprite.vframes = 4
		sprite.frame = 0


## Load the player sprite sheet texture, falling back to a colored placeholder.
func _load_player_texture() -> Texture2D:
	# Try the knight sheet as default.
	var sheet_path: String = "res://assets/sprites/characters/class_knight_sheet.png"
	if ResourceLoader.exists(sheet_path):
		var tex := load(sheet_path) as Texture2D
		if tex:
			return tex

	# Fallback: create a colored placeholder (192x256 for 3x4 grid of 64x64).
	var cell: int = 64
	var img := Image.create(cell * 3, cell * 4, false, Image.FORMAT_RGBA8)
	var body_color := Color(0.3, 0.5, 0.8)  # Blue knight
	var skin_color := Color(0.9, 0.75, 0.6)
	var half: int = cell / 2
	for vy in range(4):
		for vx in range(3):
			var ox: int = vx * cell
			var oy: int = vy * cell
			# Draw a simple character silhouette per frame.
			for py in range(cell):
				for px in range(cell):
					var c: Color = Color.TRANSPARENT
					var cx: int = px - half
					var cy: int = py - half
					# Head (top circle).
					if cx * cx + (cy + 16) * (cy + 16) < 144:
						c = skin_color
					# Body (rectangle).
					elif abs(cx) < 12 and cy > -8 and cy < 20:
						c = body_color
					# Legs offset for walk frames.
					elif abs(cx) < 8 and cy >= 20 and cy < 32:
						var leg_offset: int = 0
						if vx == 1:
							leg_offset = 4
						elif vx == 2:
							leg_offset = -4
						if abs(cx - leg_offset) < 6:
							c = body_color.darkened(0.3)
					if c.a > 0.0:
						img.set_pixel(ox + px, oy + py, c)
	return ImageTexture.create_from_image(img)


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
