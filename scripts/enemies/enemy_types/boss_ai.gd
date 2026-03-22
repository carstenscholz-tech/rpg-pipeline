extends EnemyBase
class_name BossAI
## Boss AI for Chieftain Grukk. Two-phase fight with AoE and summons.

enum BossPhase { PHASE_1, PHASE_2 }

var current_phase: BossPhase = BossPhase.PHASE_1

# Phase 2 trigger
const PHASE_2_THRESHOLD: float = 0.5

# Ground Slam AoE
var ground_slam_cooldown: float = 6.0
var ground_slam_timer: float = 0.0
var ground_slam_range: float = 50.0
var ground_slam_damage_mult: float = 1.5
var is_slamming: bool = false

# Phase 2 enrage
var phase2_speed_mult: float = 1.3
var phase2_attack_speed_mult: float = 0.7  # Faster attacks (lower cooldown)
var has_transitioned: bool = false

# Summoning
var summon_cooldown: float = 15.0
var summon_timer: float = 0.0
var max_summons: int = 2
var active_summons: Array[EnemyBase] = []
var has_summoned_phase2: bool = false

# Boss health bar reference (UI at top of screen)
var boss_health_bar: Control = null

# Victory
var victory_triggered: bool = false

# Goblin scene to summon
var GoblinScene: PackedScene = null


func _ready() -> void:
	super._ready()
	add_to_group("bosses")

	is_boss = true

	# Try to load goblin scene for summoning
	if ResourceLoader.exists("res://scenes/enemies/enemy.tscn"):
		GoblinScene = load("res://scenes/enemies/enemy.tscn")

	# Create boss health bar UI
	_create_boss_health_bar()

	# Boss has longer attack cooldown base
	attack_cooldown.wait_time = 1.5
	ground_slam_timer = ground_slam_cooldown * 0.5  # Start partially ready


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return

	# Update timers
	ground_slam_timer -= delta
	summon_timer -= delta

	# Phase transition check
	if current_phase == BossPhase.PHASE_1 and get_hp_percentage() <= PHASE_2_THRESHOLD:
		_transition_to_phase2()

	# Clean dead summons
	active_summons = active_summons.filter(func(s): return is_instance_valid(s) and s.is_alive())

	# Phase 2 periodic summoning
	if current_phase == BossPhase.PHASE_2 and summon_timer <= 0.0:
		if active_summons.size() < max_summons:
			_summon_goblins()

	# Boss-specific attack choices during ATTACK state
	if state == State.ATTACK and is_instance_valid(target):
		if ground_slam_timer <= 0.0 and player_in_attack_range:
			_ground_slam()
			return

	# Update boss health bar
	_update_boss_health_bar()

	super._physics_process(delta)


# ---- Phase Transition ----

func _transition_to_phase2() -> void:
	if has_transitioned:
		return
	has_transitioned = true
	current_phase = BossPhase.PHASE_2

	# Brief invincibility during transition
	invincible = true
	invincibility_timer = 1.5

	# Enrage effects
	speed *= phase2_speed_mult
	attack_cooldown.wait_time *= phase2_attack_speed_mult

	# Visual: screen shake effect via notification, red glow
	EventBus.show_notification.emit("%s is enraged! The ground trembles..." % enemy_name)

	var tween: Tween = create_tween()
	tween.tween_property(sprite, "modulate", Color(1.5, 0.4, 0.4, 1.0), 0.5)
	tween.tween_property(sprite, "scale", Vector2(1.2, 1.2), 0.3)
	tween.tween_property(sprite, "scale", Vector2(1.1, 1.1), 0.2)

	# Summon goblins immediately on phase transition
	_summon_goblins()

	# Ground slam becomes available sooner
	ground_slam_cooldown = 4.0
	ground_slam_timer = 1.0


# ---- Ground Slam AoE ----

func _ground_slam() -> void:
	is_slamming = true
	ground_slam_timer = ground_slam_cooldown
	can_attack = false
	attack_cooldown.start()
	velocity = Vector2.ZERO

	# Wind-up visual
	var tween: Tween = create_tween()
	tween.tween_property(sprite, "position", Vector2(0, -8), 0.3)  # Jump up
	tween.tween_property(sprite, "position", Vector2(0, 0), 0.15)   # Slam down

	await tween.finished
	is_slamming = false

	# Deal AoE damage to everything in range
	var slam_damage: int = int(float(_calculate_damage()) * ground_slam_damage_mult)

	for body in get_tree().get_nodes_in_group("player"):
		if is_instance_valid(body) and body.global_position.distance_to(global_position) <= ground_slam_range:
			if body.has_method("take_damage"):
				body.take_damage(slam_damage, self)
			else:
				EventBus.player_damaged.emit(slam_damage)

	# Visual: expanding circle effect (modulate nearby sprites)
	_slam_visual_effect()

	EventBus.show_notification.emit("%s slams the ground!" % enemy_name)


func _slam_visual_effect() -> void:
	# Create a brief expanding visual indicator
	# We use a simple approach: temporarily add a ColorRect as a circle
	var indicator: Node2D = Node2D.new()
	indicator.global_position = global_position
	get_tree().current_scene.add_child(indicator)

	# Simple visual: modulate everything briefly
	var tween: Tween = create_tween()
	tween.tween_callback(func():
		modulate = Color(1.0, 0.8, 0.2, 1.0)
	)
	tween.tween_interval(0.2)
	tween.tween_callback(func():
		modulate = Color.WHITE if current_phase == BossPhase.PHASE_1 else Color(1.5, 0.4, 0.4, 1.0)
	)
	tween.tween_callback(indicator.queue_free)


# ---- Summon Goblins ----

func _summon_goblins() -> void:
	if not GoblinScene:
		return

	summon_timer = summon_cooldown

	var summon_count: int = max_summons - active_summons.size()
	summon_count = mini(summon_count, 2)

	EventBus.show_notification.emit("%s calls for reinforcements!" % enemy_name)

	for i in range(summon_count):
		var goblin: Node2D = GoblinScene.instantiate()
		# Set as goblin scout
		goblin.set("enemy_id", "goblin_scout")

		# Spawn at offset positions
		var angle: float = randf() * TAU
		var offset: Vector2 = Vector2(cos(angle), sin(angle)) * 40.0
		goblin.global_position = global_position + offset

		get_tree().current_scene.call_deferred("add_child", goblin)

		# Track the summon
		if goblin is EnemyBase:
			active_summons.append(goblin)
			# Make summon target the player immediately
			if is_instance_valid(target):
				goblin.call_deferred("alert_to_target", target)


# ---- Boss Health Bar UI ----

func _create_boss_health_bar() -> void:
	# Find or create UI layer
	var ui_layer: CanvasLayer = null
	for child in get_tree().current_scene.get_children():
		if child is CanvasLayer:
			ui_layer = child
			break

	if not ui_layer:
		ui_layer = CanvasLayer.new()
		ui_layer.name = "BossUI"
		get_tree().current_scene.call_deferred("add_child", ui_layer)

	# Create boss health bar container
	boss_health_bar = VBoxContainer.new()
	boss_health_bar.name = "BossHealthBar"
	boss_health_bar.anchors_preset = Control.PRESET_CENTER_TOP
	boss_health_bar.offset_left = -200.0
	boss_health_bar.offset_top = 16.0
	boss_health_bar.offset_right = 200.0
	boss_health_bar.offset_bottom = 60.0
	boss_health_bar.visible = false

	# Boss name label
	var name_label: Label = Label.new()
	name_label.name = "BossName"
	name_label.text = enemy_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_health_bar.add_child(name_label)

	# Health progress bar
	var hp_bar: ProgressBar = ProgressBar.new()
	hp_bar.name = "HPBar"
	hp_bar.custom_minimum_size = Vector2(400, 20)
	hp_bar.value = 100.0
	hp_bar.show_percentage = false
	boss_health_bar.add_child(hp_bar)

	ui_layer.call_deferred("add_child", boss_health_bar)

	# Hide the regular health bar
	health_bar.visible = false


func _update_boss_health_bar() -> void:
	if not is_instance_valid(boss_health_bar):
		return

	var hp_bar: ProgressBar = boss_health_bar.get_node_or_null("HPBar")
	if hp_bar:
		hp_bar.value = get_hp_percentage() * 100.0

	# Show boss bar when in combat
	boss_health_bar.visible = (state == State.CHASE or state == State.ATTACK)


# ---- Overrides ----

func _on_state_changed(old_state: State, new_state: State) -> void:
	if new_state == State.CHASE or new_state == State.ATTACK:
		if is_instance_valid(boss_health_bar):
			boss_health_bar.visible = true
	elif new_state == State.IDLE:
		if is_instance_valid(boss_health_bar):
			boss_health_bar.visible = false


func _should_flee() -> bool:
	# Bosses never flee
	return false


func _on_attack_performed() -> void:
	# War cry ability in phase 2: boost nearby goblins occasionally
	if current_phase == BossPhase.PHASE_2 and "war_cry" in abilities and randf() < 0.2:
		_war_cry()


func _war_cry() -> void:
	EventBus.show_notification.emit("%s lets out a war cry!" % enemy_name)
	# Boost nearby goblin attack speed temporarily
	for enemy in get_tree().get_nodes_in_group("goblins"):
		if is_instance_valid(enemy) and enemy.is_alive():
			if enemy.global_position.distance_to(global_position) <= 120.0:
				# Brief speed boost
				var old_speed: float = enemy.speed
				enemy.speed *= 1.3
				# Reset after 3 seconds
				get_tree().create_timer(3.0).timeout.connect(func():
					if is_instance_valid(enemy):
						enemy.speed = old_speed
				)


func _on_death() -> void:
	# Kill all summons
	for summon in active_summons:
		if is_instance_valid(summon) and summon.is_alive():
			summon.take_damage(9999, null)

	# Remove boss health bar
	if is_instance_valid(boss_health_bar):
		boss_health_bar.queue_free()

	# Trigger victory
	if not victory_triggered:
		victory_triggered = true
		_trigger_victory()


func _trigger_victory() -> void:
	EventBus.show_notification.emit("Chieftain Grukk has been defeated!")

	# Mark quest as progressed
	EventBus.quest_step_completed.emit("the_chieftains_challenge", 0)

	# Brief pause for dramatic effect
	get_tree().paused = true
	await get_tree().create_timer(2.0).timeout
	get_tree().paused = false

	EventBus.show_notification.emit("Victory! The goblin threat is ended... for now.")
