extends Camera2D
class_name GameCamera
## Camera that follows the player with smoothing, screen shake, and zoom transitions.

## How quickly the camera catches up (higher = snappier).
@export var follow_speed: float = 5.0
## Default zoom level for overworld.
@export var default_zoom: Vector2 = Vector2(3.0, 3.0)
## Zoom level when entering a building/interior.
@export var interior_zoom: Vector2 = Vector2(4.0, 4.0)
## Duration of zoom transitions in seconds.
@export var zoom_transition_time: float = 0.4

# --- Screen shake state ---
var _shake_intensity: float = 0.0
var _shake_duration: float = 0.0
var _shake_timer: float = 0.0

# --- Zoom tween ---
var _zoom_tween: Tween = null

# --- Room bounds (limits) ---
var _limits_active: bool = false


func _ready() -> void:
	zoom = default_zoom
	position_smoothing_enabled = true
	position_smoothing_speed = follow_speed
	# Camera is a child of Player so it follows automatically via scene tree.
	# We only need to handle shake offset, limits, and zoom.
	EventBus.zone_entered.connect(_on_zone_entered)


func _process(delta: float) -> void:
	# Apply screen shake.
	if _shake_timer > 0.0:
		_shake_timer -= delta
		var shake_amount: float = _shake_intensity * (_shake_timer / _shake_duration)
		offset = Vector2(
			randf_range(-shake_amount, shake_amount),
			randf_range(-shake_amount, shake_amount)
		)
	else:
		offset = Vector2.ZERO


# ---------------------------------------------------------------------------
# Screen Shake
# ---------------------------------------------------------------------------

## Trigger a screen shake effect. Useful for combat hits or explosions.
func shake(intensity: float = 4.0, duration: float = 0.2) -> void:
	_shake_intensity = intensity
	_shake_duration = duration
	_shake_timer = duration


# ---------------------------------------------------------------------------
# Zoom Transitions
# ---------------------------------------------------------------------------

## Smoothly transition to a target zoom level.
func zoom_to(target_zoom: Vector2, duration: float = -1.0) -> void:
	if duration < 0.0:
		duration = zoom_transition_time

	if _zoom_tween and _zoom_tween.is_valid():
		_zoom_tween.kill()

	_zoom_tween = create_tween().set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	_zoom_tween.tween_property(self, "zoom", target_zoom, duration)


## Transition to interior zoom.
func enter_interior() -> void:
	zoom_to(interior_zoom)


## Transition back to default zoom.
func exit_interior() -> void:
	zoom_to(default_zoom)


# ---------------------------------------------------------------------------
# Camera Limits (room / area bounds)
# ---------------------------------------------------------------------------

## Set camera limits to confine it within a rectangular region (in world coords).
func set_room_bounds(bounds: Rect2) -> void:
	limit_left = int(bounds.position.x)
	limit_top = int(bounds.position.y)
	limit_right = int(bounds.end.x)
	limit_bottom = int(bounds.end.y)
	_limits_active = true


## Remove camera limits so the camera can follow freely.
func clear_room_bounds() -> void:
	limit_left = -10000000
	limit_top = -10000000
	limit_right = 10000000
	limit_bottom = 10000000
	_limits_active = false


## Returns whether room bounds are currently active.
func has_room_bounds() -> bool:
	return _limits_active


# ---------------------------------------------------------------------------
# Signal callbacks
# ---------------------------------------------------------------------------

func _on_zone_entered(zone_id: String) -> void:
	# Look up map data for the zone to set camera limits.
	var map_data: Dictionary = GameData.get_map(zone_id)
	if map_data.is_empty():
		return

	var bounds_data: Dictionary = map_data.get("camera_bounds", {})
	if bounds_data.is_empty():
		clear_room_bounds()
		return

	var rect := Rect2(
		bounds_data.get("x", 0),
		bounds_data.get("y", 0),
		bounds_data.get("w", 1280),
		bounds_data.get("h", 720),
	)
	set_room_bounds(rect)

	# Check if this zone is an interior and adjust zoom.
	if map_data.get("interior", false):
		enter_interior()
	else:
		exit_interior()
