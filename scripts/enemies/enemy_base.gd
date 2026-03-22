extends CharacterBody2D
class_name EnemyBase
## Base enemy script. Loads stats from JSON, handles AI states, combat, death/loot.

# ---- Enums ----
enum State { IDLE, WANDER, CHASE, ATTACK, FLEE, DEAD }

# ---- Exported ----
@export var enemy_id: String = ""

# ---- Stats (loaded from JSON) ----
var enemy_name: String = "Enemy"
var level: int = 1
var max_hp: int = 10
var current_hp: int = 10
var attack_power: int = 1
var defense: int = 0
var speed: float = 1.0
var xp_reward: int = 5
var gold_drop_range: Array = [0, 1]
var loot_table: Array = []
var aggro_range: float = 5.0
var respawn_seconds: float = 30.0
var sprite_id: String = ""
var behavior: String = "wander"
var call_for_help_range: float = 0.0
var is_boss: bool = false
var is_mini_boss: bool = false
var abilities: Array = []

# ---- State ----
var state: State = State.IDLE
var target: Node2D = null
var player_in_attack_range: bool = false
var can_attack: bool = true
var wander_direction: Vector2 = Vector2.ZERO
var spawn_position: Vector2 = Vector2.ZERO
var invincible: bool = false
var invincibility_timer: float = 0.0

const INVINCIBILITY_DURATION: float = 0.2
const WANDER_SPEED_MULT: float = 0.4
const FLEE_HP_THRESHOLD: float = 0.15
const MAX_CHASE_DISTANCE: float = 300.0

# ---- Node references ----
@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var detection_zone: Area2D = $DetectionZone
@onready var attack_zone: Area2D = $AttackZone
@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D
@onready var wander_timer: Timer = $WanderTimer
@onready var attack_cooldown: Timer = $AttackCooldown
@onready var hit_flash_timer: Timer = $HitFlashTimer
@onready var health_bar: ProgressBar = $HealthBar
@onready var hurtbox: Area2D = $Hurtbox

# ---- Preloads ----
var DamageNumberScene: PackedScene = null
var LootDropScene: PackedScene = null


func _ready() -> void:
	add_to_group("enemies")
	spawn_position = global_position

	# Preload combat scenes if they exist
	if ResourceLoader.exists("res://scripts/combat/damage_number.tscn"):
		DamageNumberScene = load("res://scripts/combat/damage_number.tscn")
	if ResourceLoader.exists("res://scripts/combat/loot_drop.tscn"):
		LootDropScene = load("res://scripts/combat/loot_drop.tscn")

	_load_enemy_data()

	# Load enemy sprite texture if none is assigned.
	if sprite and sprite.texture == null:
		sprite.texture = _load_enemy_texture()

	_setup_detection_radius()
	_update_health_bar()
	health_bar.visible = false
	wander_timer.start()


func _load_enemy_data() -> void:
	if enemy_id.is_empty():
		return

	var all_enemies: Dictionary = GameData.get_enemy_data()
	if all_enemies.is_empty():
		return

	var data: Dictionary = all_enemies.get(enemy_id, {})
	if data.is_empty():
		push_warning("EnemyBase: No data found for enemy_id '%s'" % enemy_id)
		return

	enemy_name = data.get("name", enemy_name)
	level = data.get("level", level)
	var stats: Dictionary = data.get("stats", {})
	max_hp = stats.get("hp", max_hp)
	current_hp = max_hp
	attack_power = stats.get("attack", attack_power)
	defense = stats.get("defense", defense)
	speed = stats.get("speed", speed) * 60.0  # Convert to pixels/sec
	xp_reward = data.get("xp_reward", xp_reward)
	gold_drop_range = data.get("gold_drop", gold_drop_range)
	loot_table = data.get("loot_table", loot_table)
	aggro_range = data.get("aggro_range", aggro_range)
	respawn_seconds = data.get("respawn_seconds", respawn_seconds)
	sprite_id = data.get("sprite_id", sprite_id)
	behavior = data.get("behavior", behavior)
	call_for_help_range = data.get("call_for_help_range", 0.0)
	is_boss = data.get("is_boss", false)
	is_mini_boss = data.get("is_mini_boss", false)
	abilities = data.get("abilities", [])


## Load enemy sprite texture from assets, or create a colored placeholder.
func _load_enemy_texture() -> Texture2D:
	# Try enemy_id-based path first.
	if enemy_id != "":
		var tex_path: String = "res://assets/sprites/enemies/" + enemy_id + ".png"
		if ResourceLoader.exists(tex_path):
			var tex := load(tex_path) as Texture2D
			if tex:
				return tex

	# Try sprite_id from loaded data.
	if sprite_id != "":
		var tex_path2: String = "res://assets/sprites/enemies/" + sprite_id + ".png"
		if ResourceLoader.exists(tex_path2):
			var tex := load(tex_path2) as Texture2D
			if tex:
				return tex

	# Fallback: create a 64x64 colored placeholder.
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	# Deterministic color from enemy_id.
	var hash_val: int = enemy_id.hash() if enemy_id != "" else randi()
	var r: float = fmod(abs(float(hash_val)) * 0.718033, 1.0)
	var g: float = fmod(abs(float(hash_val)) * 0.202585, 1.0)
	var b: float = fmod(abs(float(hash_val)) * 0.346290, 1.0)
	var body_color := Color(clampf(r, 0.3, 0.95), clampf(g, 0.15, 0.7), clampf(b, 0.15, 0.7))

	for py in range(64):
		for px in range(64):
			var cx: float = float(px) - 32.0
			var cy: float = float(py) - 32.0
			var dist_sq: float = cx * cx + cy * cy
			var c: Color = Color.TRANSPARENT
			# Draw a rough enemy blob shape.
			if dist_sq < 576.0:  # radius ~24
				var edge_factor: float = dist_sq / 576.0
				c = body_color.darkened(edge_factor * 0.4)
				# Eyes.
				if (abs(cx - 8.0) < 4.0 or abs(cx + 8.0) < 4.0) and abs(cy + 4.0) < 4.0:
					c = Color.RED
			if c.a > 0.0:
				img.set_pixel(px, py, c)

	return ImageTexture.create_from_image(img)


func _setup_detection_radius() -> void:
	var detection_shape: CollisionShape2D = detection_zone.get_node("DetectionShape")
	if detection_shape and detection_shape.shape is CircleShape2D:
		detection_shape.shape = detection_shape.shape.duplicate()
		detection_shape.shape.radius = aggro_range * 16.0  # tiles to pixels


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return

	# Invincibility cooldown
	if invincible:
		invincibility_timer -= delta
		if invincibility_timer <= 0.0:
			invincible = false

	match state:
		State.IDLE:
			_process_idle(delta)
		State.WANDER:
			_process_wander(delta)
		State.CHASE:
			_process_chase(delta)
		State.ATTACK:
			_process_attack(delta)
		State.FLEE:
			_process_flee(delta)

	move_and_slide()


# ---- State Processing ----

func _process_idle(_delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, speed * 0.1)


func _process_wander(_delta: float) -> void:
	velocity = wander_direction * speed * WANDER_SPEED_MULT
	# Stop wandering if far from spawn
	if global_position.distance_to(spawn_position) > 100.0:
		wander_direction = (spawn_position - global_position).normalized()


func _process_chase(_delta: float) -> void:
	if not is_instance_valid(target):
		_change_state(State.IDLE)
		return

	# Give up if too far from spawn
	if global_position.distance_to(spawn_position) > MAX_CHASE_DISTANCE:
		target = null
		_change_state(State.IDLE)
		# Walk back to spawn
		nav_agent.target_position = spawn_position
		return

	nav_agent.target_position = target.global_position

	if nav_agent.is_navigation_finished():
		velocity = Vector2.ZERO
		return

	var next_pos: Vector2 = nav_agent.get_next_path_position()
	var direction: Vector2 = (next_pos - global_position).normalized()
	velocity = direction * speed

	# Flip sprite based on direction
	if direction.x != 0.0:
		sprite.flip_h = direction.x < 0.0

	# Check for flee condition
	if _should_flee():
		_change_state(State.FLEE)


func _process_attack(_delta: float) -> void:
	velocity = Vector2.ZERO
	if not is_instance_valid(target):
		_change_state(State.IDLE)
		return

	if not player_in_attack_range:
		_change_state(State.CHASE)
		return

	if can_attack:
		_perform_attack()


func _process_flee(_delta: float) -> void:
	if not is_instance_valid(target):
		_change_state(State.IDLE)
		return

	var flee_dir: Vector2 = (global_position - target.global_position).normalized()
	velocity = flee_dir * speed * 1.2

	if sprite:
		sprite.flip_h = flee_dir.x < 0.0

	# Stop fleeing if far enough away
	if global_position.distance_to(target.global_position) > aggro_range * 16.0 * 1.5:
		target = null
		_change_state(State.IDLE)


# ---- State Transitions ----

func _change_state(new_state: State) -> void:
	var old_state: State = state
	state = new_state

	match new_state:
		State.IDLE:
			velocity = Vector2.ZERO
			wander_timer.start()
		State.WANDER:
			pass
		State.CHASE:
			health_bar.visible = true
		State.ATTACK:
			pass
		State.FLEE:
			pass
		State.DEAD:
			_handle_death()

	_on_state_changed(old_state, new_state)


## Override in subclasses for custom state transition logic.
func _on_state_changed(_old_state: State, _new_state: State) -> void:
	pass


func _should_flee() -> bool:
	return float(current_hp) / float(max_hp) < FLEE_HP_THRESHOLD and not is_boss


# ---- Combat ----

func _perform_attack() -> void:
	can_attack = false
	attack_cooldown.start()

	if not is_instance_valid(target):
		return

	# Use CombatSystem if it exists as an autoload, otherwise simple calc
	var damage: int = _calculate_damage()

	if target.has_method("take_damage"):
		target.take_damage(damage, self)
	elif target is CharacterBody2D:
		# Fallback: emit signal
		EventBus.player_damaged.emit(damage)

	_on_attack_performed()


## Override to customize attack behavior.
func _on_attack_performed() -> void:
	pass


func _calculate_damage() -> int:
	var base: int = attack_power
	var variance: int = randi_range(-2, 2)
	return maxi(1, base + variance)


func take_damage(amount: int, attacker: Node2D = null) -> void:
	if state == State.DEAD or invincible:
		return

	var actual_damage: int = maxi(1, amount - defense / 2)
	current_hp -= actual_damage

	# Invincibility frames
	invincible = true
	invincibility_timer = INVINCIBILITY_DURATION

	# Hit flash
	modulate = Color(1.5, 0.3, 0.3, 1.0)
	hit_flash_timer.start()

	# Show health bar
	health_bar.visible = true
	_update_health_bar()

	# Spawn damage number
	_spawn_damage_number(actual_damage, false)

	# Signal
	EventBus.enemy_damaged.emit(enemy_id, actual_damage)

	# Aggro on attacker
	if attacker and state != State.CHASE and state != State.ATTACK:
		target = attacker
		_change_state(State.CHASE)

	# Call for help (goblins etc)
	if call_for_help_range > 0.0:
		_call_for_help(attacker)

	# Custom hook
	_on_damaged(actual_damage, attacker)

	# Death check
	if current_hp <= 0:
		current_hp = 0
		_change_state(State.DEAD)


## Override for custom on-damage behavior.
func _on_damaged(_amount: int, _attacker: Node2D) -> void:
	pass


func heal(amount: int) -> void:
	if state == State.DEAD:
		return
	current_hp = mini(current_hp + amount, max_hp)
	_update_health_bar()
	_spawn_damage_number(amount, false, true)


func _call_for_help(attacker: Node2D) -> void:
	var help_range: float = call_for_help_range * 16.0
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy == self or not is_instance_valid(enemy):
			continue
		if enemy.global_position.distance_to(global_position) <= help_range:
			if enemy.state == State.IDLE or enemy.state == State.WANDER:
				enemy.alert_to_target(attacker)


func alert_to_target(new_target: Node2D) -> void:
	if state == State.DEAD:
		return
	target = new_target
	_change_state(State.CHASE)


# ---- Death & Loot ----

func _handle_death() -> void:
	state = State.DEAD
	velocity = Vector2.ZERO

	# Disable collisions
	collision_shape.set_deferred("disabled", true)
	detection_zone.set_deferred("monitoring", false)
	attack_zone.set_deferred("monitoring", false)
	hurtbox.set_deferred("monitoring", false)
	hurtbox.set_deferred("monitorable", false)

	# Visual death
	health_bar.visible = false
	var tween: Tween = create_tween()
	tween.tween_property(sprite, "modulate", Color(1, 1, 1, 0), 0.5)
	tween.tween_property(sprite, "self_modulate", Color(0.5, 0.5, 0.5, 0.5), 0.3)

	# Drop loot
	_drop_loot()

	# Give XP
	EventBus.enemy_defeated.emit(enemy_id)
	EventBus.xp_gained.emit("combat", xp_reward)

	# Custom hook
	_on_death()

	# Queue free after delay
	await get_tree().create_timer(1.0).timeout
	queue_free()


## Override for custom death behavior (boss cutscenes, etc.)
func _on_death() -> void:
	pass


func _drop_loot() -> void:
	# Drop gold
	var gold_amount: int = 0
	if gold_drop_range.size() >= 2:
		gold_amount = randi_range(int(gold_drop_range[0]), int(gold_drop_range[1]))

	if gold_amount > 0:
		_spawn_loot_item("gold", gold_amount)

	# Roll loot table
	for entry in loot_table:
		var item_id: String = entry.get("item_id", "")
		var drop_rate: float = entry.get("drop_rate", 0.0)
		if item_id != "" and randf() <= drop_rate:
			_spawn_loot_item(item_id, 1)


func _spawn_loot_item(item_id: String, quantity: int) -> void:
	if LootDropScene:
		var loot: Node2D = LootDropScene.instantiate()
		loot.item_id = item_id
		loot.quantity = quantity
		loot.global_position = global_position + Vector2(randf_range(-10, 10), randf_range(-10, 10))
		get_tree().current_scene.call_deferred("add_child", loot)
	else:
		# Fallback: add directly to inventory
		if item_id == "gold":
			# Try to find inventory system
			var inventory: Node = get_tree().current_scene.find_child("Inventory", true, false)
			if inventory and inventory.has_method("add_gold"):
				inventory.add_gold(quantity)
		else:
			EventBus.item_added.emit(item_id, quantity)


# ---- Damage Numbers ----

func _spawn_damage_number(amount: int, is_crit: bool = false, is_heal: bool = false) -> void:
	if DamageNumberScene:
		var dmg_num: Node2D = DamageNumberScene.instantiate()
		dmg_num.amount = amount
		dmg_num.is_crit = is_crit
		dmg_num.is_heal = is_heal
		dmg_num.global_position = global_position + Vector2(0, -16)
		get_tree().current_scene.call_deferred("add_child", dmg_num)


# ---- Health Bar ----

func _update_health_bar() -> void:
	if health_bar:
		health_bar.value = (float(current_hp) / float(max_hp)) * 100.0


# ---- Signal Callbacks ----

func _on_detection_zone_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") and state != State.DEAD:
		target = body
		if state == State.IDLE or state == State.WANDER:
			_change_state(State.CHASE)


func _on_detection_zone_body_exited(body: Node2D) -> void:
	if body == target:
		if state == State.CHASE:
			target = null
			_change_state(State.IDLE)


func _on_attack_zone_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_in_attack_range = true
		if state == State.CHASE:
			_change_state(State.ATTACK)


func _on_attack_zone_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_in_attack_range = false
		if state == State.ATTACK and is_instance_valid(target):
			_change_state(State.CHASE)


func _on_wander_timer_timeout() -> void:
	if state == State.IDLE:
		wander_direction = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
		_change_state(State.WANDER)
		# Wander for a bit then go idle
		await get_tree().create_timer(randf_range(1.0, 3.0)).timeout
		if state == State.WANDER:
			_change_state(State.IDLE)


func _on_attack_cooldown_timeout() -> void:
	can_attack = true


func _on_hit_flash_timer_timeout() -> void:
	modulate = Color.WHITE


# ---- Utility ----

func get_hp_percentage() -> float:
	return float(current_hp) / float(max_hp)


func is_alive() -> bool:
	return state != State.DEAD and current_hp > 0
