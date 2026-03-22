extends CharacterBody2D
class_name NPCController
## Base NPC controller. Handles idle behavior, schedule-driven movement,
## interaction icon display, and facing the player on interact.

enum NPCState { IDLE, WALKING, TALKING }

## NPC data ID (matches data/npcs/*.json key).
@export var npc_id: String = ""
## Display name shown above the NPC.
@export var display_name: String = ""
## Walk speed for schedule movement.
@export var move_speed: float = 40.0

## Current behavior state.
var state: NPCState = NPCState.IDLE
## Full NPC data dictionary loaded from JSON.
var npc_data: Dictionary = {}
## Current facing direction.
var facing_direction: Vector2 = Vector2.DOWN
## Walk target for schedule movement.
var _walk_target: Vector2 = Vector2.ZERO
## Whether the NPC has a walk target.
var _has_walk_target: bool = false

## Idle wander variables.
var _idle_timer: float = 0.0
var _idle_wander_range: float = 24.0  # pixels
var _home_position: Vector2 = Vector2.ZERO

@onready var sprite: Sprite2D = $Sprite2D
@onready var name_label: Label = $NameLabel
@onready var quest_icon: Sprite2D = $QuestIcon
@onready var interaction_area: Area2D = $InteractionArea
@onready var collision_shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	add_to_group("npcs")
	_home_position = global_position

	# Load NPC data if not yet set.
	if npc_id != "" and npc_data.is_empty():
		npc_data = GameData.get_npc(npc_id)

	# Load NPC sprite texture if none is assigned.
	if sprite and sprite.texture == null:
		sprite.texture = _load_npc_texture()

	# Set display name.
	if display_name == "" and npc_data.has("name"):
		display_name = npc_data.name
	if name_label:
		name_label.text = display_name

	# Connect interaction area.
	if interaction_area:
		interaction_area.connect("body_entered", _on_interaction_body_entered)
		interaction_area.connect("body_exited", _on_interaction_body_exited)

	# Initialize quest icon state.
	_update_quest_icon()

	# Listen for quest events to update icon.
	EventBus.quest_started.connect(_on_quest_changed)
	EventBus.quest_completed.connect(_on_quest_changed)
	EventBus.quest_updated.connect(_on_quest_changed)

	# Start idle timer.
	_idle_timer = randf_range(2.0, 5.0)


func _physics_process(delta: float) -> void:
	match state:
		NPCState.IDLE:
			_process_idle(delta)
		NPCState.WALKING:
			_process_walking(delta)
		NPCState.TALKING:
			# Don't move while talking.
			velocity = Vector2.ZERO


func _process_idle(delta: float) -> void:
	velocity = Vector2.ZERO

	_idle_timer -= delta
	if _idle_timer <= 0.0:
		# Small idle wander near home position.
		var wander_offset := Vector2(
			randf_range(-_idle_wander_range, _idle_wander_range),
			randf_range(-_idle_wander_range, _idle_wander_range)
		)
		_walk_target = _home_position + wander_offset
		_has_walk_target = true
		state = NPCState.WALKING
		_idle_timer = randf_range(3.0, 7.0)


func _process_walking(delta: float) -> void:
	if not _has_walk_target:
		state = NPCState.IDLE
		return

	var direction := (_walk_target - global_position)
	var distance := direction.length()

	if distance < 4.0:
		# Reached target.
		_has_walk_target = false
		state = NPCState.IDLE
		velocity = Vector2.ZERO
		return

	direction = direction.normalized()
	velocity = direction * move_speed
	_update_facing(direction)
	move_and_slide()


func _update_facing(dir: Vector2) -> void:
	if abs(dir.x) > abs(dir.y):
		facing_direction = Vector2.RIGHT if dir.x > 0.0 else Vector2.LEFT
	else:
		facing_direction = Vector2.DOWN if dir.y > 0.0 else Vector2.UP

	# Flip sprite based on facing.
	if sprite:
		sprite.flip_h = (facing_direction == Vector2.LEFT)


## Face toward a world position (used when player interacts).
func face_position(target_pos: Vector2) -> void:
	var dir := (target_pos - global_position).normalized()
	_update_facing(dir)


## Called when the player presses interact while in range.
func interact(player_node: CharacterBody2D) -> void:
	# Face the player.
	face_position(player_node.global_position)
	state = NPCState.TALKING

	# Emit interaction signal.
	EventBus.npc_interacted.emit(npc_id)

	# Load dialogue data and start dialogue.
	var dialogue_id: String = npc_data.get("dialogue_tree_id", "")
	var dialogue_data: Dictionary = {}
	if dialogue_id != "":
		dialogue_data = GameData.get_dialogue(dialogue_id)

	EventBus.start_dialogue.emit(npc_id, dialogue_data)

	# When dialogue ends, resume idle.
	if not EventBus.dialogue_ended.is_connected(_on_dialogue_ended):
		EventBus.dialogue_ended.connect(_on_dialogue_ended, CONNECT_ONE_SHOT)


func _on_dialogue_ended() -> void:
	state = NPCState.IDLE


## Update quest icon above NPC head based on quest state.
func _update_quest_icon() -> void:
	if not quest_icon:
		return

	var quests_given: Array = npc_data.get("quests_given", [])
	if quests_given.is_empty():
		quest_icon.visible = false
		return

	# Check quest states to determine which icon to show.
	var has_available := false
	var has_in_progress := false
	var has_turn_in := false

	for quest_id in quests_given:
		var is_active: bool = SaveManager.get_flag("quest_active_" + quest_id, false)
		var is_complete: bool = SaveManager.get_flag("quest_complete_" + quest_id, false)

		if is_complete:
			continue  # Already done, no icon.
		elif is_active:
			# Check if the quest can be turned in (all steps done).
			# For simplicity, show ? for in-progress.
			has_in_progress = true
		else:
			has_available = true

	# Priority: turn-in (checkmark) > available (!) > in-progress (?)
	if has_available:
		quest_icon.visible = true
		quest_icon.modulate = Color.YELLOW
		# The actual texture swap would happen when textures exist.
		# For now we use modulate to differentiate.
	elif has_in_progress:
		quest_icon.visible = true
		quest_icon.modulate = Color.GRAY
	else:
		quest_icon.visible = false


func _on_quest_changed(_quest_id: String) -> void:
	_update_quest_icon()


## Interaction area signals.
var _player_in_range: bool = false

func _on_interaction_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_range = true


func _on_interaction_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_range = false


## Check if the player is in interaction range.
func is_player_in_range() -> bool:
	return _player_in_range


## Set the NPC's schedule home position (where they wander around).
func set_home_position(pos: Vector2) -> void:
	_home_position = pos
	global_position = pos


## Move the NPC to a specific position (for schedule changes).
func move_to(target: Vector2) -> void:
	_walk_target = target
	_has_walk_target = true
	state = NPCState.WALKING


## Load the NPC sprite texture from assets, or create a colored placeholder.
func _load_npc_texture() -> Texture2D:
	# Try loading from the standard NPC sprite path.
	if npc_id != "":
		var tex_path: String = "res://assets/sprites/npcs/" + npc_id + ".png"
		if ResourceLoader.exists(tex_path):
			var tex := load(tex_path) as Texture2D
			if tex:
				return tex

	# Also try sprite_id from npc_data if available.
	var sprite_id_str: String = npc_data.get("sprite_id", "")
	if sprite_id_str != "":
		var tex_path2: String = "res://assets/sprites/npcs/" + sprite_id_str + ".png"
		if ResourceLoader.exists(tex_path2):
			var tex := load(tex_path2) as Texture2D
			if tex:
				return tex

	# Fallback: create a 32x32 colored placeholder.
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	# Generate a deterministic color from the npc_id.
	var hash_val: int = npc_id.hash() if npc_id != "" else randi()
	var r: float = fmod(abs(float(hash_val)) * 0.618033, 1.0)
	var g: float = fmod(abs(float(hash_val)) * 0.302585, 1.0)
	var b: float = fmod(abs(float(hash_val)) * 0.146290, 1.0)
	var body_color := Color(clampf(r, 0.2, 0.9), clampf(g, 0.2, 0.9), clampf(b, 0.2, 0.9))
	var skin_color := Color(0.9, 0.75, 0.6)

	for py in range(32):
		for px in range(32):
			var cx: int = px - 16
			var cy: int = py - 16
			var c: Color = Color.TRANSPARENT
			# Head.
			if cx * cx + (cy + 8) * (cy + 8) < 36:
				c = skin_color
			# Body.
			elif abs(cx) < 6 and cy > -4 and cy < 10:
				c = body_color
			# Legs.
			elif abs(cx) < 4 and cy >= 10 and cy < 16:
				c = body_color.darkened(0.3)
			if c.a > 0.0:
				img.set_pixel(px, py, c)

	return ImageTexture.create_from_image(img)
