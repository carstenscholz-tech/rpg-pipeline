extends Control
class_name MainMenu
## Main menu with title, buttons, animated background, and version number.

@onready var title_label: Label = %TitleLabel
@onready var new_game_btn: Button = %NewGameButton
@onready var continue_btn: Button = %ContinueButton
@onready var settings_btn: Button = %SettingsButton
@onready var quit_btn: Button = %QuitButton
@onready var version_label: Label = %VersionLabel
@onready var bg_sprite: TextureRect = %BackgroundSprite
@onready var animation_player: AnimationPlayer = %AnimationPlayer

const CHAR_CREATION_SCENE: String = "res://scenes/ui/character_creation.tscn"
const GAME_SCENE: String = "res://scenes/main.tscn"

var bg_scroll_offset: float = 0.0


func _ready() -> void:
	version_label.text = "v0.1.0"
	title_label.text = "Echoes of the Aether"
	_connect_buttons()
	_check_save_exists()
	if animation_player and animation_player.has_animation("bg_float"):
		animation_player.play("bg_float")


func _process(delta: float) -> void:
	# Subtle background scroll for pixel art feel
	bg_scroll_offset += delta * 8.0
	if bg_sprite and bg_sprite.material is ShaderMaterial:
		(bg_sprite.material as ShaderMaterial).set_shader_parameter("scroll_offset", bg_scroll_offset)


func _connect_buttons() -> void:
	new_game_btn.pressed.connect(_on_new_game)
	continue_btn.pressed.connect(_on_continue)
	settings_btn.pressed.connect(_on_settings)
	quit_btn.pressed.connect(_on_quit)


func _check_save_exists() -> void:
	continue_btn.disabled = not FileAccess.file_exists("user://save_data.json")


func _on_new_game() -> void:
	get_tree().change_scene_to_file(CHAR_CREATION_SCENE)


func _on_continue() -> void:
	if SaveManager.load_game():
		get_tree().change_scene_to_file(GAME_SCENE)
	else:
		EventBus.show_notification.emit("No save file found!")


func _on_settings() -> void:
	# Placeholder - settings UI to be implemented
	EventBus.show_notification.emit("Settings coming soon!")


func _on_quit() -> void:
	get_tree().quit()
