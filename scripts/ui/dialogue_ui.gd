extends CanvasLayer
class_name DialogueUI
## Dialogue box with typewriter effect, NPC portrait, name, and choice buttons.
## Connects to DialogueManager autoload for state and navigation.

@onready var dialogue_panel: PanelContainer = %DialoguePanel
@onready var portrait_rect: TextureRect = %Portrait
@onready var npc_name_label: Label = %NPCName
@onready var dialogue_text: RichTextLabel = %DialogueText
@onready var choices_container: VBoxContainer = %ChoicesContainer
@onready var advance_indicator: Label = %AdvanceIndicator

const TYPEWRITER_SPEED: float = 0.03  # Seconds per character
const MAX_CHOICES: int = 4

var is_active: bool = false
var typewriter_active: bool = false
var full_text: String = ""
var visible_chars: int = 0
var typewriter_timer: float = 0.0
var current_choices: Array = []


func _ready() -> void:
	dialogue_panel.visible = false
	advance_indicator.visible = false
	_connect_signals()
	_clear_choices()


func _connect_signals() -> void:
	DialogueManager.dialogue_started.connect(_on_dialogue_started)
	DialogueManager.dialogue_text_shown.connect(_on_text_shown)
	DialogueManager.dialogue_choices_shown.connect(_on_choices_shown)
	DialogueManager.dialogue_ended.connect(_on_dialogue_ended)


func _process(delta: float) -> void:
	if not typewriter_active:
		return

	typewriter_timer += delta
	if typewriter_timer >= TYPEWRITER_SPEED:
		typewriter_timer = 0.0
		visible_chars += 1
		dialogue_text.visible_characters = visible_chars
		if visible_chars >= full_text.length():
			_finish_typewriter()


func _unhandled_input(event: InputEvent) -> void:
	if not is_active:
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_advance()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_handle_advance()
		get_viewport().set_input_as_handled()


func _handle_advance() -> void:
	if typewriter_active:
		# First press: skip typewriter, show full text immediately
		_finish_typewriter()
	elif current_choices.size() == 1 and current_choices[0].get("next", "") == "__end__":
		# Auto-advance terminal node
		DialogueManager.select_choice(0)


func _on_dialogue_started(_npc_id: String) -> void:
	is_active = true
	dialogue_panel.visible = true

	# Load portrait
	var portrait_path: String = "res://assets/sprites/npcs/%s_portrait.png" % _npc_id
	if ResourceLoader.exists(portrait_path):
		portrait_rect.texture = load(portrait_path)
	else:
		portrait_rect.texture = null


func _on_text_shown(speaker: String, text: String) -> void:
	npc_name_label.text = speaker

	# Start typewriter effect
	full_text = text
	visible_chars = 0
	typewriter_timer = 0.0
	typewriter_active = true

	dialogue_text.text = full_text
	dialogue_text.visible_characters = 0
	advance_indicator.visible = false
	_clear_choices()


func _on_choices_shown(choices: Array) -> void:
	current_choices = choices
	# Choices are shown after typewriter finishes (if still typing)
	if not typewriter_active:
		_show_choices()


func _finish_typewriter() -> void:
	typewriter_active = false
	dialogue_text.visible_characters = -1  # Show all

	# Now display choices
	_show_choices()


func _show_choices() -> void:
	_clear_choices()

	# Check if this is a simple continue-to-end
	var is_terminal: bool = current_choices.size() == 1 and current_choices[0].get("next", "") == "__end__"

	if is_terminal:
		advance_indicator.visible = true
		advance_indicator.text = "[Click to continue]"
		return

	advance_indicator.visible = false

	for i in range(mini(current_choices.size(), MAX_CHOICES)):
		var choice: Dictionary = current_choices[i]
		var btn := Button.new()
		btn.text = "%d. %s" % [i + 1, choice.get("text", "...")]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 10)

		var stylebox := StyleBoxFlat.new()
		stylebox.bg_color = Color(0.15, 0.15, 0.2, 0.9)
		stylebox.border_color = Color(0.5, 0.5, 0.6)
		stylebox.set_border_width_all(1)
		stylebox.content_margin_left = 8
		stylebox.content_margin_right = 8
		stylebox.content_margin_top = 4
		stylebox.content_margin_bottom = 4
		btn.add_theme_stylebox_override("normal", stylebox)

		var hover_style := stylebox.duplicate() as StyleBoxFlat
		hover_style.bg_color = Color(0.25, 0.25, 0.35, 0.9)
		hover_style.border_color = Color.GOLD
		btn.add_theme_stylebox_override("hover", hover_style)

		btn.pressed.connect(_on_choice_pressed.bind(i))
		choices_container.add_child(btn)


func _on_choice_pressed(choice_index: int) -> void:
	_clear_choices()
	advance_indicator.visible = false
	DialogueManager.select_choice(choice_index)


func _clear_choices() -> void:
	for child in choices_container.get_children():
		child.queue_free()


func _on_dialogue_ended() -> void:
	is_active = false
	dialogue_panel.visible = false
	typewriter_active = false
	current_choices.clear()
	_clear_choices()
	advance_indicator.visible = false
