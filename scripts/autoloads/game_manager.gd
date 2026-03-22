extends Node
## Global game state manager. Controls game state, scene transitions, and save/load.

# --- Game States ---
enum GameState {
	MENU,
	PLAYING,
	PAUSED,
	DIALOGUE,
	COMBAT,
	INVENTORY,
}

# --- Signals (signal bus) ---
signal state_changed(old_state: GameState, new_state: GameState)
signal scene_transition_started(target_scene: String)
signal scene_transition_finished(target_scene: String)
signal fade_finished()
signal game_paused()
signal game_resumed()
signal player_died()
signal player_respawned()
signal notification_requested(message: String, duration: float)

# --- State ---
var current_state: GameState = GameState.MENU
var previous_state: GameState = GameState.MENU
var current_scene_path: String = ""
var is_transitioning: bool = false
var _fade_overlay: ColorRect = null
var _fade_tween: Tween = null

# --- Constants ---
const FADE_DURATION: float = 0.4
const SAVE_DIR: String = "user://saves/"
const SAVE_EXTENSION: String = ".json"
const MAX_SAVE_SLOTS: int = 3


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_create_fade_overlay()
	_ensure_save_directory()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		match current_state:
			GameState.PLAYING:
				pause_game()
			GameState.PAUSED:
				resume_game()
			GameState.INVENTORY:
				change_state(GameState.PLAYING)
			GameState.DIALOGUE:
				pass  # Dialogue handles its own cancel


# --- State Management ---

func change_state(new_state: GameState) -> void:
	if new_state == current_state:
		return
	var old_state := current_state
	previous_state = current_state
	current_state = new_state

	match new_state:
		GameState.PAUSED:
			get_tree().paused = true
		GameState.PLAYING:
			get_tree().paused = false
		GameState.DIALOGUE:
			get_tree().paused = false  # Dialogue runs unpaused but blocks input
		GameState.COMBAT:
			get_tree().paused = false
		GameState.INVENTORY:
			get_tree().paused = true
		GameState.MENU:
			get_tree().paused = false

	state_changed.emit(old_state, new_state)


func pause_game() -> void:
	if current_state == GameState.PLAYING:
		change_state(GameState.PAUSED)
		game_paused.emit()


func resume_game() -> void:
	if current_state == GameState.PAUSED:
		change_state(GameState.PLAYING)
		game_resumed.emit()


func is_playing() -> bool:
	return current_state == GameState.PLAYING


func can_player_move() -> bool:
	return current_state == GameState.PLAYING


# --- Scene Transitions ---

func transition_to_scene(scene_path: String, spawn_point: String = "") -> void:
	if is_transitioning:
		return
	is_transitioning = true
	scene_transition_started.emit(scene_path)

	# Fade out
	await _fade_out()

	# Change scene
	var error := get_tree().change_scene_to_file(scene_path)
	if error != OK:
		push_error("GameManager: Failed to load scene: %s (error %d)" % [scene_path, error])
		is_transitioning = false
		await _fade_in()
		return

	current_scene_path = scene_path

	# Wait one frame for the new scene to initialize
	await get_tree().process_frame

	# Handle spawn point if specified
	if spawn_point != "":
		_move_player_to_spawn(spawn_point)

	# Fade in
	await _fade_in()

	is_transitioning = false
	scene_transition_finished.emit(scene_path)
	EventBus.zone_entered.emit(scene_path.get_file().get_basename())


func _move_player_to_spawn(spawn_name: String) -> void:
	var spawn_markers := get_tree().get_nodes_in_group("spawn_points")
	for marker in spawn_markers:
		if marker.name == spawn_name:
			var player := get_tree().get_first_node_in_group("player")
			if player:
				player.global_position = marker.global_position
			return
	push_warning("GameManager: Spawn point '%s' not found" % spawn_name)


# --- Fade Effect ---

func _create_fade_overlay() -> void:
	_fade_overlay = ColorRect.new()
	_fade_overlay.name = "FadeOverlay"
	_fade_overlay.color = Color(0, 0, 0, 0)
	_fade_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_overlay.z_index = 100

	# Use a CanvasLayer so the overlay is always on top
	var canvas_layer := CanvasLayer.new()
	canvas_layer.name = "FadeLayer"
	canvas_layer.layer = 100
	add_child(canvas_layer)

	_fade_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas_layer.add_child(_fade_overlay)


func _fade_out() -> void:
	if _fade_tween and _fade_tween.is_running():
		_fade_tween.kill()
	_fade_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_fade_tween = create_tween()
	_fade_tween.tween_property(_fade_overlay, "color:a", 1.0, FADE_DURATION)
	await _fade_tween.finished


func _fade_in() -> void:
	if _fade_tween and _fade_tween.is_running():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(_fade_overlay, "color:a", 0.0, FADE_DURATION)
	await _fade_tween.finished
	_fade_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_finished.emit()


# --- Save / Load System ---

func _ensure_save_directory() -> void:
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_recursive_absolute(SAVE_DIR)


func save_game(slot: int = 0) -> bool:
	if slot < 0 or slot >= MAX_SAVE_SLOTS:
		push_error("GameManager: Invalid save slot %d" % slot)
		return false

	var save_data: Dictionary = {
		"timestamp": Time.get_datetime_string_from_system(),
		"scene": current_scene_path,
		"player": PlayerData.serialize(),
		"quests": QuestManager.serialize(),
		"inventory": InventoryManager.serialize(),
		"flags": SaveManager.save_data.get("flags", {}),
	}

	# Get player position
	var player := get_tree().get_first_node_in_group("player")
	if player:
		save_data["player_position"] = {
			"x": player.global_position.x,
			"y": player.global_position.y,
		}

	var path := SAVE_DIR + "save_slot_%d%s" % [slot, SAVE_EXTENSION]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		push_error("GameManager: Cannot write to save file: %s" % path)
		return false

	file.store_string(JSON.stringify(save_data, "\t"))
	file.close()

	EventBus.game_saved.emit()
	notification_requested.emit("Game saved.", 2.0)
	print("GameManager: Game saved to slot %d" % slot)
	return true


func load_game(slot: int = 0) -> bool:
	if slot < 0 or slot >= MAX_SAVE_SLOTS:
		push_error("GameManager: Invalid save slot %d" % slot)
		return false

	var path := SAVE_DIR + "save_slot_%d%s" % [slot, SAVE_EXTENSION]
	if not FileAccess.file_exists(path):
		push_warning("GameManager: No save file in slot %d" % slot)
		return false

	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("GameManager: Cannot read save file: %s" % path)
		return false

	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("GameManager: Failed to parse save file: %s" % path)
		return false

	var save_data: Dictionary = json.data
	if not save_data is Dictionary:
		push_error("GameManager: Save data is not a dictionary")
		return false

	# Restore systems
	if save_data.has("player"):
		PlayerData.deserialize(save_data["player"])
	if save_data.has("quests"):
		QuestManager.deserialize(save_data["quests"])
	if save_data.has("inventory"):
		InventoryManager.deserialize(save_data["inventory"])
	if save_data.has("flags"):
		SaveManager.save_data["flags"] = save_data["flags"]

	# Transition to saved scene
	if save_data.has("scene") and save_data["scene"] != "":
		await transition_to_scene(save_data["scene"])

		# Restore player position
		if save_data.has("player_position"):
			var player := get_tree().get_first_node_in_group("player")
			if player:
				player.global_position = Vector2(
					save_data["player_position"]["x"],
					save_data["player_position"]["y"]
				)

	change_state(GameState.PLAYING)
	EventBus.game_loaded.emit()
	notification_requested.emit("Game loaded.", 2.0)
	print("GameManager: Game loaded from slot %d" % slot)
	return true


func has_save(slot: int) -> bool:
	var path := SAVE_DIR + "save_slot_%d%s" % [slot, SAVE_EXTENSION]
	return FileAccess.file_exists(path)


func delete_save(slot: int) -> void:
	var path := SAVE_DIR + "save_slot_%d%s" % [slot, SAVE_EXTENSION]
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func get_save_info(slot: int) -> Dictionary:
	var path := SAVE_DIR + "save_slot_%d%s" % [slot, SAVE_EXTENSION]
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return {}
	var data: Dictionary = json.data
	return {
		"timestamp": data.get("timestamp", ""),
		"scene": data.get("scene", ""),
		"player_name": data.get("player", {}).get("name", "Unknown"),
		"player_level": data.get("player", {}).get("level", 1),
	}


# --- Utility ---

func show_notification(message: String, duration: float = 3.0) -> void:
	notification_requested.emit(message, duration)
	EventBus.show_notification.emit(message)


func start_new_game() -> void:
	PlayerData.reset()
	QuestManager.reset()
	InventoryManager.reset()
	SaveManager.save_data["flags"] = {}
	change_state(GameState.PLAYING)
