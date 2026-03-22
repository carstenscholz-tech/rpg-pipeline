extends Node
## Turn-based combat manager. Handles initiative, actions, damage, rewards, and death.

# --- Signals ---
signal combat_started(enemies: Array)
signal combat_ended(victory: bool)
signal turn_started(combatant_id: String, is_player: bool)
signal turn_ended(combatant_id: String)
signal action_performed(combatant_id: String, action: String, target_id: String, result: Dictionary)
signal damage_dealt(source_id: String, target_id: String, amount: int, is_critical: bool)
signal combatant_defeated(combatant_id: String)
signal player_turn_ready()
signal enemy_turn_ready(enemy_id: String)
signal loot_dropped(loot: Array)
signal flee_attempted(success: bool)
signal status_effect_applied(target_id: String, effect: String, duration: int)

# --- Combat States ---
enum CombatState {
	INACTIVE,
	STARTING,
	PLAYER_TURN,
	ENEMY_TURN,
	PROCESSING,
	VICTORY,
	DEFEAT,
	FLED,
}

# --- State ---
var state: CombatState = CombatState.INACTIVE
var is_active: bool = false

# --- Combatants ---
# Each entry: { "id": String, "name": String, "is_player": bool, "hp": int, "max_hp": int,
#   "attack": int, "defense": int, "speed": float, "level": int, "alive": bool,
#   "enemy_data": Dictionary (for enemies), "status_effects": Dictionary }
var combatants: Array[Dictionary] = []
var turn_order: Array[String] = []  # IDs in initiative order
var current_turn_index: int = 0

# --- Enemy definitions (loaded from GameData) ---
var enemy_definitions: Dictionary = {}


func _ready() -> void:
	call_deferred("_load_enemy_definitions")


func _load_enemy_definitions() -> void:
	## Build enemy_id -> enemy_data lookup from data/enemies/*.json
	enemy_definitions.clear()
	var dir_path := "res://data/enemies/"
	var dir := DirAccess.open(dir_path)
	if not dir:
		push_warning("CombatManager: No enemies directory at %s" % dir_path)
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".json"):
			var full_path := dir_path + file_name
			var file := FileAccess.open(full_path, FileAccess.READ)
			if file:
				var json := JSON.new()
				if json.parse(file.get_as_text()) == OK and json.data is Dictionary:
					var data: Dictionary = json.data
					# Handle files with "enemies" array
					if data.has("enemies"):
						for enemy in data["enemies"]:
							var eid: String = enemy.get("enemy_id", "")
							if eid != "":
								enemy_definitions[eid] = enemy
					else:
						var eid: String = data.get("enemy_id", file_name.get_basename())
						enemy_definitions[eid] = data
		file_name = dir.get_next()
	print("CombatManager: Loaded %d enemy definitions" % enemy_definitions.size())


# --- Starting Combat ---

func start_combat(enemy_ids: Array) -> void:
	## Begin a turn-based combat encounter with the given enemies.
	if is_active:
		push_warning("CombatManager: Combat already active")
		return

	is_active = true
	state = CombatState.STARTING
	combatants.clear()
	turn_order.clear()
	current_turn_index = 0

	# Add player combatant
	var player_combatant: Dictionary = {
		"id": "player",
		"name": PlayerData.player_name,
		"is_player": true,
		"hp": PlayerData.current_hp,
		"max_hp": PlayerData.max_hp,
		"mp": PlayerData.current_mp,
		"max_mp": PlayerData.max_mp,
		"attack": PlayerData.attack,
		"defense": PlayerData.defense,
		"speed": PlayerData.speed,
		"magic_attack": PlayerData.magic_attack,
		"level": PlayerData.level,
		"alive": true,
		"status_effects": {},
		"is_defending": false,
	}
	combatants.append(player_combatant)

	# Add enemy combatants
	var enemy_index: int = 0
	for enemy_id in enemy_ids:
		var def: Dictionary = enemy_definitions.get(enemy_id, {})
		if def.is_empty():
			push_warning("CombatManager: Unknown enemy '%s'" % enemy_id)
			continue

		var stats: Dictionary = def.get("stats", {})
		var unique_id: String = "%s_%d" % [enemy_id, enemy_index]
		var enemy_combatant: Dictionary = {
			"id": unique_id,
			"base_id": enemy_id,
			"name": def.get("name", enemy_id),
			"is_player": false,
			"hp": stats.get("hp", 10),
			"max_hp": stats.get("hp", 10),
			"mp": stats.get("mana", 0),
			"max_mp": stats.get("mana", 0),
			"attack": stats.get("attack", 5),
			"defense": stats.get("defense", 2),
			"speed": stats.get("speed", 1.0),
			"magic_attack": 0,
			"level": def.get("level", 1),
			"alive": true,
			"status_effects": {},
			"is_defending": false,
			"enemy_data": def,
		}
		combatants.append(enemy_combatant)
		enemy_index += 1

	# Calculate initiative
	_calculate_initiative()

	GameManager.change_state(GameManager.GameState.COMBAT)

	var enemy_names: Array = []
	for c in combatants:
		if not c["is_player"]:
			enemy_names.append(c["name"])
	combat_started.emit(enemy_names)
	print("CombatManager: Combat started vs %s" % str(enemy_names))

	# Begin first turn
	_next_turn()


# --- Initiative ---

func _calculate_initiative() -> void:
	## Sort combatants by speed (descending) with some randomness.
	var initiative_list: Array[Dictionary] = []
	for combatant in combatants:
		var roll: float = combatant["speed"] + randf_range(-0.3, 0.3)
		initiative_list.append({"id": combatant["id"], "roll": roll})

	initiative_list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["roll"] > b["roll"]
	)

	turn_order.clear()
	for entry in initiative_list:
		turn_order.append(entry["id"])

	current_turn_index = 0


# --- Turn Management ---

func _next_turn() -> void:
	## Advance to the next alive combatant's turn.
	if not is_active:
		return

	# Check for combat end conditions
	if _check_combat_end():
		return

	# Process status effects at start of turn
	_process_status_effects()

	# Find next alive combatant
	var attempts: int = 0
	while attempts < combatants.size():
		if current_turn_index >= turn_order.size():
			current_turn_index = 0
		var combatant_id: String = turn_order[current_turn_index]
		var combatant: Dictionary = _get_combatant(combatant_id)
		if combatant.get("alive", false):
			# Reset defense flag
			combatant["is_defending"] = false
			turn_started.emit(combatant_id, combatant["is_player"])
			if combatant["is_player"]:
				state = CombatState.PLAYER_TURN
				player_turn_ready.emit()
			else:
				state = CombatState.ENEMY_TURN
				enemy_turn_ready.emit(combatant_id)
				# Auto-execute enemy AI after a short delay
				_execute_enemy_turn(combatant_id)
			return
		current_turn_index += 1
		attempts += 1

	# Should not reach here
	_end_combat(false)


func _advance_turn() -> void:
	current_turn_index += 1
	if current_turn_index >= turn_order.size():
		current_turn_index = 0
	_next_turn()


# --- Player Actions ---

func player_attack(target_id: String) -> void:
	## Player performs a basic attack on the target.
	if state != CombatState.PLAYER_TURN:
		return
	state = CombatState.PROCESSING

	var player: Dictionary = _get_combatant("player")
	var target: Dictionary = _get_combatant(target_id)
	if target.is_empty() or not target["alive"]:
		state = CombatState.PLAYER_TURN
		return

	var result: Dictionary = _calculate_damage(player, target)
	_apply_damage(target_id, result["damage"])

	action_performed.emit("player", "attack", target_id, result)
	damage_dealt.emit("player", target_id, result["damage"], result["critical"])

	turn_ended.emit("player")
	_advance_turn()


func player_defend() -> void:
	## Player defends, increasing defense for this round.
	if state != CombatState.PLAYER_TURN:
		return
	state = CombatState.PROCESSING

	var player: Dictionary = _get_combatant("player")
	player["is_defending"] = true

	action_performed.emit("player", "defend", "player", {"message": "Defending!"})

	turn_ended.emit("player")
	_advance_turn()


func player_use_skill(skill_id: String, target_id: String = "") -> void:
	## Player uses a combat skill.
	if state != CombatState.PLAYER_TURN:
		return

	var skill_data: Dictionary = PlayerData.get_skill_data(skill_id)
	if skill_data.is_empty():
		return

	var mp_cost: int = skill_data.get("mp_cost", 0)
	if not PlayerData.use_mp(mp_cost):
		EventBus.show_notification.emit("Not enough MP!")
		return

	state = CombatState.PROCESSING
	var player: Dictionary = _get_combatant("player")

	# Update player MP in combatant data
	player["mp"] = PlayerData.current_mp

	var damage_mod: float = skill_data.get("damage_modifier", 1.0)
	var hits_type: Variant = skill_data.get("hits", 1)
	var stat_scale: String = skill_data.get("stat_scale", "")

	# Determine base attack for skill
	var base_attack: int = player["attack"]
	if stat_scale == "intelligence":
		base_attack = player["magic_attack"]

	if hits_type == "all_enemies":
		# AoE skill
		for combatant in combatants:
			if not combatant["is_player"] and combatant["alive"]:
				var result: Dictionary = _calculate_damage(player, combatant, damage_mod, base_attack)
				_apply_damage(combatant["id"], result["damage"])
				damage_dealt.emit("player", combatant["id"], result["damage"], result["critical"])
		action_performed.emit("player", "skill:" + skill_id, "all", {"skill": skill_data})
	elif hits_type is int and hits_type > 1:
		# Multi-hit skill
		var hit_count: int = int(hits_type)
		for h in range(hit_count):
			if target_id != "":
				var target: Dictionary = _get_combatant(target_id)
				if target.get("alive", false):
					var result: Dictionary = _calculate_damage(player, target, damage_mod, base_attack)
					_apply_damage(target_id, result["damage"])
					damage_dealt.emit("player", target_id, result["damage"], result["critical"])
		action_performed.emit("player", "skill:" + skill_id, target_id, {"skill": skill_data, "hits": hits_type})
	else:
		# Single target
		if target_id == "":
			target_id = _get_first_alive_enemy()
		var target: Dictionary = _get_combatant(target_id)
		if not target.is_empty() and target["alive"]:
			var result: Dictionary = _calculate_damage(player, target, damage_mod, base_attack)
			_apply_damage(target_id, result["damage"])
			damage_dealt.emit("player", target_id, result["damage"], result["critical"])
			action_performed.emit("player", "skill:" + skill_id, target_id, result)

	# Handle skill effects
	var effect: String = skill_data.get("effect", "")
	if effect != "":
		_apply_skill_effect(effect, "player", target_id)

	turn_ended.emit("player")
	_advance_turn()


func player_use_item(item_id: String) -> void:
	## Player uses a consumable item in combat.
	if state != CombatState.PLAYER_TURN:
		return
	state = CombatState.PROCESSING

	if InventoryManager.use_item(item_id):
		# Sync HP/MP to combatant data
		var player: Dictionary = _get_combatant("player")
		player["hp"] = PlayerData.current_hp
		player["mp"] = PlayerData.current_mp
		action_performed.emit("player", "item:" + item_id, "player", {"item_id": item_id})
	else:
		EventBus.show_notification.emit("Cannot use that item!")
		state = CombatState.PLAYER_TURN
		return

	turn_ended.emit("player")
	_advance_turn()


func player_flee() -> void:
	## Attempt to flee from combat.
	if state != CombatState.PLAYER_TURN:
		return
	state = CombatState.PROCESSING

	# Flee chance: 50% base + 5% per level above average enemy level
	var avg_enemy_level: float = 0.0
	var enemy_count: int = 0
	for combatant in combatants:
		if not combatant["is_player"] and combatant["alive"]:
			avg_enemy_level += combatant["level"]
			enemy_count += 1
	if enemy_count > 0:
		avg_enemy_level /= enemy_count

	var flee_chance: float = 0.5 + (PlayerData.level - avg_enemy_level) * 0.05
	flee_chance = clampf(flee_chance, 0.1, 0.9)

	var roll: float = randf()
	var success: bool = roll < flee_chance

	flee_attempted.emit(success)

	if success:
		state = CombatState.FLED
		EventBus.show_notification.emit("Escaped!")
		_end_combat_cleanup()
		combat_ended.emit(false)
	else:
		EventBus.show_notification.emit("Cannot escape!")
		action_performed.emit("player", "flee_failed", "", {})
		turn_ended.emit("player")
		_advance_turn()


# --- Enemy AI ---

func _execute_enemy_turn(enemy_id: String) -> void:
	var enemy: Dictionary = _get_combatant(enemy_id)
	if enemy.is_empty() or not enemy["alive"]:
		_advance_turn()
		return

	# Simple AI: attack the player
	var target_id := "player"
	var player: Dictionary = _get_combatant("player")

	if not player.get("alive", false):
		_advance_turn()
		return

	# Check for special abilities
	var enemy_data: Dictionary = enemy.get("enemy_data", {})
	var abilities: Array = enemy_data.get("abilities", [])

	var action_name: String = "attack"
	var damage_mod: float = 1.0

	# Simple AI decisions
	if abilities.size() > 0 and enemy.get("mp", 0) > 5 and randf() < 0.3:
		# Use a random ability sometimes
		var ability: String = abilities[randi() % abilities.size()]
		if ability == "heal_ally":
			# Find a wounded ally to heal
			var wounded: Dictionary = _find_wounded_ally(enemy_id)
			if not wounded.is_empty():
				var heal_amount: int = enemy["attack"]  # Simple heal
				wounded["hp"] = mini(wounded["hp"] + heal_amount, wounded["max_hp"])
				action_name = "heal"
				action_performed.emit(enemy_id, "heal", wounded["id"], {"heal": heal_amount})
				turn_ended.emit(enemy_id)
				_advance_turn()
				return
		elif ability == "poison_bolt":
			action_name = "poison_bolt"
			damage_mod = 0.8
			_apply_status_effect("player", "poison", 3)
		elif ability == "war_cry":
			# Buff self
			_apply_status_effect(enemy_id, "attack_up", 3)
			action_name = "war_cry"
			action_performed.emit(enemy_id, "war_cry", enemy_id, {"message": "%s lets out a war cry!" % enemy["name"]})
			turn_ended.emit(enemy_id)
			_advance_turn()
			return

	# Basic attack
	var result: Dictionary = _calculate_damage(enemy, player, damage_mod)
	_apply_damage_to_player(result["damage"])

	action_performed.emit(enemy_id, action_name, target_id, result)
	damage_dealt.emit(enemy_id, target_id, result["damage"], result["critical"])
	EventBus.player_damaged.emit(result["damage"])

	turn_ended.emit(enemy_id)
	_advance_turn()


func _find_wounded_ally(exclude_id: String) -> Dictionary:
	for combatant in combatants:
		if not combatant["is_player"] and combatant["alive"] and combatant["id"] != exclude_id:
			if combatant["hp"] < combatant["max_hp"] * 0.5:
				return combatant
	return {}


# --- Damage Calculation ---

func _calculate_damage(attacker: Dictionary, defender: Dictionary, skill_mod: float = 1.0, override_attack: int = -1) -> Dictionary:
	## Core damage formula: (attack * skill_modifier) - (defense * 0.5) + random(-2, 2)
	var atk: int = override_attack if override_attack >= 0 else attacker["attack"]
	var def: int = defender["defense"]

	# Apply defending bonus
	if defender.get("is_defending", false):
		def = int(def * 1.5)

	# Apply status effect modifiers
	if attacker.get("status_effects", {}).has("attack_up"):
		atk = int(atk * 1.25)

	var raw_damage: float = (atk * skill_mod) - (def * 0.5) + randf_range(-2.0, 2.0)
	var damage: int = maxi(int(raw_damage), 1)  # Minimum 1 damage

	# Critical hit check (based on luck or flat 10%)
	var crit_chance: float = 0.1
	if attacker.get("is_player", false):
		crit_chance = 0.05 + PlayerData.luck * 0.01
	var is_critical: bool = randf() < crit_chance
	if is_critical:
		damage = int(damage * 1.5)

	return {
		"damage": damage,
		"critical": is_critical,
		"raw": raw_damage,
	}


func _apply_damage(combatant_id: String, amount: int) -> void:
	var combatant: Dictionary = _get_combatant(combatant_id)
	if combatant.is_empty():
		return

	combatant["hp"] = maxi(combatant["hp"] - amount, 0)
	if combatant["hp"] <= 0:
		combatant["alive"] = false
		combatant_defeated.emit(combatant_id)
		if not combatant["is_player"]:
			EventBus.enemy_defeated.emit(combatant.get("base_id", combatant_id))


func _apply_damage_to_player(amount: int) -> void:
	var player: Dictionary = _get_combatant("player")
	if player.is_empty():
		return

	PlayerData.take_damage(amount)
	player["hp"] = PlayerData.current_hp
	if PlayerData.current_hp <= 0:
		player["alive"] = false
		combatant_defeated.emit("player")


# --- Status Effects ---

func _apply_status_effect(target_id: String, effect: String, duration: int) -> void:
	var combatant: Dictionary = _get_combatant(target_id)
	if combatant.is_empty():
		return
	combatant["status_effects"][effect] = duration
	status_effect_applied.emit(target_id, effect, duration)


func _apply_skill_effect(effect: String, source_id: String, target_id: String) -> void:
	if effect.begins_with("stun_"):
		var turns: int = int(effect.split("_")[0].substr(4)) if "_" in effect else 1
		_apply_status_effect(target_id, "stun", turns)
	elif effect.begins_with("buff_attack_"):
		# e.g. buff_attack_25_3t -> 25% for 3 turns
		_apply_status_effect(source_id, "attack_up", 3)
	elif effect.begins_with("buff_defense_"):
		_apply_status_effect(source_id, "defense_up", 2)
	elif effect.begins_with("dodge_"):
		_apply_status_effect(source_id, "evasion", 2)
	elif effect.begins_with("poison_"):
		var turns: int = 3
		_apply_status_effect(target_id, "poison", turns)
	elif effect.begins_with("slow_"):
		var turns: int = 2
		_apply_status_effect(target_id, "slow", turns)
	elif effect == "absorb_damage_mp_3t":
		_apply_status_effect(source_id, "mana_shield", 3)


func _process_status_effects() -> void:
	var combatant_id: String = turn_order[current_turn_index] if current_turn_index < turn_order.size() else ""
	var combatant: Dictionary = _get_combatant(combatant_id)
	if combatant.is_empty() or not combatant["alive"]:
		return

	var effects_to_remove: Array[String] = []
	for effect in combatant["status_effects"]:
		var duration: int = combatant["status_effects"][effect]

		# Apply per-turn effects
		if effect == "poison":
			var poison_damage: int = maxi(int(combatant["max_hp"] * 0.05), 1)
			if combatant["is_player"]:
				_apply_damage_to_player(poison_damage)
			else:
				_apply_damage(combatant_id, poison_damage)
			EventBus.show_notification.emit("%s takes %d poison damage!" % [combatant["name"], poison_damage])

		# Decrement duration
		combatant["status_effects"][effect] = duration - 1
		if combatant["status_effects"][effect] <= 0:
			effects_to_remove.append(effect)

	for effect in effects_to_remove:
		combatant["status_effects"].erase(effect)


# --- Combat End ---

func _check_combat_end() -> bool:
	var player: Dictionary = _get_combatant("player")
	if not player.get("alive", false):
		_end_combat(false)
		return true

	var enemies_alive: bool = false
	for combatant in combatants:
		if not combatant["is_player"] and combatant["alive"]:
			enemies_alive = true
			break

	if not enemies_alive:
		_end_combat(true)
		return true

	return false


func _end_combat(victory: bool) -> void:
	if victory:
		state = CombatState.VICTORY
		_grant_rewards()
	else:
		state = CombatState.DEFEAT
		if not _get_combatant("player").get("alive", false):
			_handle_death()

	_end_combat_cleanup()
	combat_ended.emit(victory)


func _grant_rewards() -> void:
	var total_xp: int = 0
	var total_gold: int = 0
	var all_loot: Array = []

	for combatant in combatants:
		if combatant["is_player"]:
			continue
		var enemy_data: Dictionary = combatant.get("enemy_data", {})

		# XP
		total_xp += enemy_data.get("xp_reward", 0)

		# Gold
		var gold_range: Array = enemy_data.get("gold_drop", [0, 0])
		if gold_range.size() >= 2:
			total_gold += randi_range(int(gold_range[0]), int(gold_range[1]))

		# Loot
		var loot_table: Array = enemy_data.get("loot_table", [])
		for loot_entry in loot_table:
			var drop_rate: float = loot_entry.get("drop_rate", 0.0)
			if randf() < drop_rate:
				var item_id: String = loot_entry.get("item_id", "")
				if item_id != "":
					all_loot.append(item_id)

	# Apply rewards
	if total_xp > 0:
		PlayerData.add_xp(total_xp)
		EventBus.show_notification.emit("Gained %d XP!" % total_xp)

	if total_gold > 0:
		PlayerData.add_gold(total_gold)
		EventBus.show_notification.emit("Found %d gold!" % total_gold)

	for item_id in all_loot:
		InventoryManager.add_item(item_id)

	if all_loot.size() > 0:
		loot_dropped.emit(all_loot)


func _handle_death() -> void:
	## Handle player death -- respawn with penalty.
	EventBus.show_notification.emit("You have been defeated...")
	GameManager.player_died.emit()

	# Respawn: restore to 50% HP, lose 10% gold
	PlayerData.current_hp = maxi(int(PlayerData.max_hp * 0.5), 1)
	PlayerData.current_mp = maxi(int(PlayerData.max_mp * 0.5), 1)
	var gold_penalty: int = int(PlayerData.gold * 0.1)
	PlayerData.gold = maxi(PlayerData.gold - gold_penalty, 0)

	PlayerData.hp_changed.emit(PlayerData.current_hp, PlayerData.max_hp)
	PlayerData.mp_changed.emit(PlayerData.current_mp, PlayerData.max_mp)
	PlayerData.stats_changed.emit()

	if gold_penalty > 0:
		EventBus.show_notification.emit("Lost %d gold..." % gold_penalty)

	GameManager.player_respawned.emit()


func _end_combat_cleanup() -> void:
	is_active = false
	combatants.clear()
	turn_order.clear()
	current_turn_index = 0
	GameManager.change_state(GameManager.GameState.PLAYING)


# --- Queries ---

func _get_combatant(combatant_id: String) -> Dictionary:
	for combatant in combatants:
		if combatant["id"] == combatant_id:
			return combatant
	return {}


func _get_first_alive_enemy() -> String:
	for combatant in combatants:
		if not combatant["is_player"] and combatant["alive"]:
			return combatant["id"]
	return ""


func get_alive_enemies() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for combatant in combatants:
		if not combatant["is_player"] and combatant["alive"]:
			result.append(combatant)
	return result


func get_player_combatant() -> Dictionary:
	return _get_combatant("player")


func get_enemy_def(enemy_id: String) -> Dictionary:
	return enemy_definitions.get(enemy_id, {})
