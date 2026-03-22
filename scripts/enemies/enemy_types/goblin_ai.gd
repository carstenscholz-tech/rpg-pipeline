extends EnemyBase
class_name GoblinAI
## Goblin-specific AI. Scouts call for help, warriors charge and block,
## shamans stay at range and cast spells.

enum GoblinRole { SCOUT, WARRIOR, SHAMAN }

@export var goblin_role: GoblinRole = GoblinRole.SCOUT

# Shaman-specific
var preferred_range: float = 80.0  # pixels - distance shaman tries to maintain
var spell_cooldown: float = 3.0
var spell_timer: float = 0.0
var mana: int = 0
var max_mana: int = 0

# Warrior-specific
var is_blocking: bool = false
var block_chance: float = 0.3
var charge_speed_mult: float = 1.8
var is_charging: bool = false
var charge_timer: float = 0.0
const CHARGE_DURATION: float = 0.6

# Help-calling
var has_called_for_help: bool = false


func _ready() -> void:
	super._ready()
	add_to_group("goblins")
	_detect_role_from_data()


func _detect_role_from_data() -> void:
	match behavior:
		"support_caster":
			goblin_role = GoblinRole.SHAMAN
			var stats_data: Dictionary = GameData.get_enemy_data().get(enemy_id, {}).get("stats", {})
			max_mana = stats_data.get("mana", 25)
			mana = max_mana
		"patrol":
			# Check if warrior or scout based on enemy_id
			if enemy_id == "goblin" or "warrior" in enemy_id:
				goblin_role = GoblinRole.WARRIOR
			else:
				goblin_role = GoblinRole.SCOUT
		_:
			goblin_role = GoblinRole.SCOUT


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return

	# Update charge timer
	if is_charging:
		charge_timer -= delta
		if charge_timer <= 0.0:
			is_charging = false

	# Update spell cooldown
	if spell_timer > 0.0:
		spell_timer -= delta

	match goblin_role:
		GoblinRole.SHAMAN:
			_process_shaman(delta)
		GoblinRole.WARRIOR:
			_process_warrior(delta)
		_:
			super._physics_process(delta)
			return

	# Still need base movement
	if goblin_role != GoblinRole.SHAMAN:
		super._physics_process(delta)
	else:
		# Shaman handles its own movement
		if invincible:
			invincibility_timer -= delta
			if invincibility_timer <= 0.0:
				invincible = false
		move_and_slide()


# ---- Scout Behavior ----
# Scouts use base behavior but always call for help when hit.

func _on_damaged(amount: int, attacker: Node2D) -> void:
	if not has_called_for_help and call_for_help_range > 0.0:
		has_called_for_help = true
		_call_for_help_goblins(attacker)


func _call_for_help_goblins(attacker: Node2D) -> void:
	var help_range: float = call_for_help_range * 16.0
	for goblin in get_tree().get_nodes_in_group("goblins"):
		if goblin == self or not is_instance_valid(goblin):
			continue
		if not goblin.is_alive():
			continue
		if goblin.global_position.distance_to(global_position) <= help_range:
			goblin.alert_to_target(attacker)
			# Visual indicator: brief yellow flash on alerted goblins
			goblin.modulate = Color(1.0, 1.0, 0.3, 1.0)
			if goblin.hit_flash_timer:
				goblin.hit_flash_timer.wait_time = 0.3
				goblin.hit_flash_timer.start()


# ---- Warrior Behavior ----

func _process_warrior(_delta: float) -> void:
	if state == State.CHASE and is_instance_valid(target):
		var dist: float = global_position.distance_to(target.global_position)
		# Initiate charge when within medium range
		if dist < 60.0 and dist > 25.0 and not is_charging:
			_start_charge()

	if is_charging and is_instance_valid(target):
		var dir: Vector2 = (target.global_position - global_position).normalized()
		velocity = dir * speed * charge_speed_mult


func _start_charge() -> void:
	is_charging = true
	charge_timer = CHARGE_DURATION
	# Brief visual: slight scale up during charge
	var tween: Tween = create_tween()
	tween.tween_property(sprite, "scale", Vector2(1.2, 1.2), 0.1)
	tween.tween_property(sprite, "scale", Vector2(1.0, 1.0), 0.1)


func take_damage(amount: int, attacker: Node2D = null) -> void:
	# Warriors can block attacks
	if goblin_role == GoblinRole.WARRIOR and not is_charging:
		if randf() < block_chance:
			# Blocked! Reduce damage significantly
			amount = maxi(1, amount / 4)
			is_blocking = true
			# Flash blue for block
			modulate = Color(0.5, 0.5, 1.5, 1.0)
			hit_flash_timer.start()
			_spawn_damage_number(amount, false, false)
			EventBus.show_notification.emit("%s blocked!" % enemy_name)
			# Still take reduced damage via parent
			super.take_damage(amount, attacker)
			return

	super.take_damage(amount, attacker)


# ---- Shaman Behavior ----

func _process_shaman(delta: float) -> void:
	match state:
		State.IDLE, State.WANDER:
			# Use base idle/wander
			if state == State.IDLE:
				velocity = velocity.move_toward(Vector2.ZERO, speed * 0.1)
			elif state == State.WANDER:
				velocity = wander_direction * speed * WANDER_SPEED_MULT
		State.CHASE:
			_shaman_chase(delta)
		State.ATTACK:
			_shaman_attack(delta)
		State.FLEE:
			_process_flee(delta)


func _shaman_chase(_delta: float) -> void:
	if not is_instance_valid(target):
		_change_state(State.IDLE)
		return

	var dist: float = global_position.distance_to(target.global_position)

	# Stay at preferred range
	if dist < preferred_range * 0.7:
		# Too close, back away
		var away_dir: Vector2 = (global_position - target.global_position).normalized()
		velocity = away_dir * speed * 0.8
	elif dist > preferred_range * 1.3:
		# Too far, move closer
		nav_agent.target_position = target.global_position
		if not nav_agent.is_navigation_finished():
			var next_pos: Vector2 = nav_agent.get_next_path_position()
			var direction: Vector2 = (next_pos - global_position).normalized()
			velocity = direction * speed * 0.7
	else:
		# In range, try to cast
		velocity = Vector2.ZERO
		if spell_timer <= 0.0 and mana > 0:
			_change_state(State.ATTACK)

	if velocity.x != 0.0 and sprite:
		sprite.flip_h = velocity.x < 0.0


func _shaman_attack(_delta: float) -> void:
	velocity = Vector2.ZERO

	if not is_instance_valid(target):
		_change_state(State.IDLE)
		return

	if spell_timer <= 0.0 and mana > 0:
		_cast_spell()
		_change_state(State.CHASE)
	else:
		_change_state(State.CHASE)


func _cast_spell() -> void:
	# Decide: heal ally or attack
	var wounded_ally: EnemyBase = _find_wounded_ally()
	if wounded_ally and "heal_ally" in abilities:
		_cast_heal(wounded_ally)
	elif "poison_bolt" in abilities:
		_cast_poison_bolt()
	else:
		# Fallback ranged attack
		_perform_attack()


func _cast_heal(ally: EnemyBase) -> void:
	var heal_amount: int = attack_power  # Use attack as spell power
	mana -= 5
	spell_timer = spell_cooldown
	ally.heal(heal_amount)

	# Visual: green flash on healed ally
	ally.modulate = Color(0.3, 1.5, 0.3, 1.0)
	if ally.hit_flash_timer:
		ally.hit_flash_timer.wait_time = 0.3
		ally.hit_flash_timer.start()

	EventBus.show_notification.emit("%s heals %s!" % [enemy_name, ally.enemy_name])


func _cast_poison_bolt() -> void:
	if not is_instance_valid(target):
		return

	mana -= 4
	spell_timer = spell_cooldown

	var damage: int = _calculate_damage() + 3  # Bonus magic damage

	if target.has_method("take_damage"):
		target.take_damage(damage, self)
	else:
		EventBus.player_damaged.emit(damage)

	# Visual: brief purple flash on self when casting
	modulate = Color(0.8, 0.3, 1.2, 1.0)
	hit_flash_timer.start()


func _find_wounded_ally() -> EnemyBase:
	var best_ally: EnemyBase = null
	var lowest_hp_pct: float = 0.7  # Only heal allies below 70%

	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy == self or not is_instance_valid(enemy):
			continue
		if not enemy.is_alive():
			continue
		if enemy.global_position.distance_to(global_position) > preferred_range * 2.0:
			continue
		var hp_pct: float = enemy.get_hp_percentage()
		if hp_pct < lowest_hp_pct:
			lowest_hp_pct = hp_pct
			best_ally = enemy

	return best_ally


func _on_state_changed(_old_state: State, _new_state: State) -> void:
	# Reset blocking state
	if goblin_role == GoblinRole.WARRIOR:
		is_blocking = false
