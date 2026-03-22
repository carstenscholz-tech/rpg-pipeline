extends EnemyBase
class_name WolfAI
## Wolf AI with pack behavior. Wolves follow the alpha's target.
## Alpha wolf enrages at low HP. Wolves circle prey before attacking.

@export var is_alpha: bool = false

# Pack behavior
var pack_members: Array[EnemyBase] = []
var alpha_ref: WolfAI = null
var circle_angle: float = 0.0
var circle_speed: float = 1.5  # radians per second
var circle_radius: float = 40.0
var is_circling: bool = false
var circle_timer: float = 0.0
const CIRCLE_DURATION: float = 2.5
const CIRCLE_MIN_DURATION: float = 1.0

# Alpha enrage
var is_enraged: bool = false
const ENRAGE_THRESHOLD: float = 0.3
const ENRAGE_SPEED_MULT: float = 1.5
const ENRAGE_ATTACK_MULT: float = 1.4
var base_speed: float = 0.0
var base_attack: int = 0


func _ready() -> void:
	super._ready()
	add_to_group("wolves")

	# Detect alpha status from data
	if enemy_id == "wolf_alpha" or is_mini_boss:
		is_alpha = true

	base_speed = speed
	base_attack = attack_power

	# Find pack after a frame so all wolves are spawned
	call_deferred("_find_pack")


func _find_pack() -> void:
	pack_members.clear()
	alpha_ref = null

	for wolf in get_tree().get_nodes_in_group("wolves"):
		if wolf == self or not is_instance_valid(wolf):
			continue
		if not wolf.is_alive():
			continue
		# Wolves within pack range
		if wolf.global_position.distance_to(global_position) <= 150.0:
			pack_members.append(wolf)
			if wolf is WolfAI and wolf.is_alpha:
				alpha_ref = wolf

	if is_alpha:
		# Register self as alpha for nearby pack members
		for member in pack_members:
			if member is WolfAI:
				member.alpha_ref = self


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return

	# Check alpha enrage
	if is_alpha and not is_enraged and get_hp_percentage() <= ENRAGE_THRESHOLD:
		_enrage()

	# Pack sync: follow alpha's target
	if not is_alpha and is_instance_valid(alpha_ref) and alpha_ref.is_alive():
		if is_instance_valid(alpha_ref.target) and target != alpha_ref.target:
			target = alpha_ref.target
			if state == State.IDLE or state == State.WANDER:
				_change_state(State.CHASE)

	# Circling behavior before attack
	if is_circling:
		_process_circle(delta)
		# Still do base invincibility logic
		if invincible:
			invincibility_timer -= delta
			if invincibility_timer <= 0.0:
				invincible = false
		move_and_slide()
		return

	super._physics_process(delta)


func _process_circle(delta: float) -> void:
	if not is_instance_valid(target):
		is_circling = false
		_change_state(State.IDLE)
		return

	circle_timer -= delta
	circle_angle += circle_speed * delta

	# Calculate circle position around target
	var offset: Vector2 = Vector2(
		cos(circle_angle) * circle_radius,
		sin(circle_angle) * circle_radius
	)
	var desired_pos: Vector2 = target.global_position + offset
	var direction: Vector2 = (desired_pos - global_position).normalized()

	var current_speed: float = speed
	if is_enraged:
		current_speed = speed  # Already boosted by enrage

	velocity = direction * current_speed * 0.7

	if direction.x != 0.0 and sprite:
		sprite.flip_h = direction.x < 0.0

	# Done circling? Attack!
	if circle_timer <= 0.0:
		is_circling = false
		if player_in_attack_range:
			_change_state(State.ATTACK)
		else:
			_change_state(State.CHASE)


func _on_state_changed(old_state: State, new_state: State) -> void:
	# Start circling when transitioning from chase to a close range
	if new_state == State.CHASE and old_state == State.IDLE or old_state == State.WANDER:
		# Randomize circle parameters per wolf for natural look
		circle_angle = randf() * TAU
		circle_radius = randf_range(30.0, 50.0)

	if new_state == State.ATTACK and not is_circling:
		# Wolves circle before their first attack
		if old_state == State.CHASE and randf() < 0.6:
			is_circling = true
			circle_timer = randf_range(CIRCLE_MIN_DURATION, CIRCLE_DURATION)
			state = State.CHASE  # Stay in chase visually


func _on_attack_performed() -> void:
	# After attacking, sometimes circle again
	if randf() < 0.3 and is_instance_valid(target):
		is_circling = true
		circle_timer = randf_range(0.8, 1.5)


# ---- Alpha Enrage ----

func _enrage() -> void:
	is_enraged = true
	speed = base_speed * ENRAGE_SPEED_MULT
	attack_power = int(float(base_attack) * ENRAGE_ATTACK_MULT)

	# Visual: red tint and scale up slightly
	var tween: Tween = create_tween()
	tween.tween_property(sprite, "modulate", Color(1.4, 0.6, 0.6, 1.0), 0.3)
	tween.tween_property(sprite, "scale", Vector2(1.15, 1.15), 0.3)

	EventBus.show_notification.emit("%s is enraged!" % enemy_name)

	# Alert pack to be more aggressive
	for member in pack_members:
		if is_instance_valid(member) and member.is_alive():
			if member is WolfAI:
				member.circle_speed *= 1.5  # Circle faster
				member.attack_cooldown.wait_time *= 0.7  # Attack faster


func _should_flee() -> bool:
	# Wolves don't flee if alpha or if alpha is alive
	if is_alpha:
		return false
	if is_instance_valid(alpha_ref) and alpha_ref.is_alive():
		return false
	return super._should_flee()


func _on_death() -> void:
	# If alpha dies, pack may flee
	if is_alpha:
		for member in pack_members:
			if is_instance_valid(member) and member.is_alive():
				if member is WolfAI:
					member.alpha_ref = null
					# 50% chance pack members flee
					if randf() < 0.5:
						member._change_state(State.FLEE)
