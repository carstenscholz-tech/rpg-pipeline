extends CanvasLayer
class_name NotificationUI
## Toast notification system - slides in from top, stays 3 seconds, slides out. Queues multiple.

@onready var container: VBoxContainer = %NotificationContainer

const NOTIFICATION_SCENE_PATH: String = ""  # We create notifications in code
const SLIDE_IN_TIME: float = 0.3
const DISPLAY_TIME: float = 3.0
const SLIDE_OUT_TIME: float = 0.3
const MAX_VISIBLE: int = 5

var notification_queue: Array[String] = []
var active_count: int = 0


func _ready() -> void:
	EventBus.show_notification.connect(_on_notification_requested)


func _on_notification_requested(message: String) -> void:
	if active_count >= MAX_VISIBLE:
		notification_queue.append(message)
		return
	_spawn_notification(message)


func _spawn_notification(message: String) -> void:
	active_count += 1

	var panel := PanelContainer.new()
	var stylebox := StyleBoxFlat.new()
	stylebox.bg_color = Color(0.1, 0.1, 0.15, 0.95)
	stylebox.border_color = Color(0.8, 0.7, 0.3)
	stylebox.set_border_width_all(1)
	stylebox.corner_radius_top_left = 2
	stylebox.corner_radius_top_right = 2
	stylebox.corner_radius_bottom_left = 2
	stylebox.corner_radius_bottom_right = 2
	stylebox.content_margin_left = 12
	stylebox.content_margin_right = 12
	stylebox.content_margin_top = 6
	stylebox.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", stylebox)

	var label := Label.new()
	label.text = message
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.7))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(label)

	container.add_child(panel)

	# Start off-screen (above)
	panel.modulate.a = 0.0
	panel.position.y = -30

	# Slide in
	var tween := create_tween()
	tween.tween_property(panel, "modulate:a", 1.0, SLIDE_IN_TIME)
	tween.parallel().tween_property(panel, "position:y", 0.0, SLIDE_IN_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# Wait
	tween.tween_interval(DISPLAY_TIME)

	# Slide out
	tween.tween_property(panel, "modulate:a", 0.0, SLIDE_OUT_TIME)
	tween.parallel().tween_property(panel, "position:y", -20.0, SLIDE_OUT_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)

	# Remove
	tween.tween_callback(_remove_notification.bind(panel))


func _remove_notification(panel: PanelContainer) -> void:
	panel.queue_free()
	active_count -= 1

	# Process queue
	if not notification_queue.is_empty():
		var next_message: String = notification_queue.pop_front()
		_spawn_notification(next_message)
