extends Node
## Player stats singleton. Tracks player identity, stats, XP, leveling, and class skills.

# --- Signals ---
signal stats_changed()
signal level_changed(new_level: int)
signal xp_gained(amount: int)
signal hp_changed(new_hp: int, max_hp: int)
signal mp_changed(new_mp: int, max_mp: int)
signal skill_unlocked(skill_id: String)
signal player_died()

# --- Class Definitions (loaded from data/classes/) ---
var class_definitions: Dictionary = {}

# --- Player Identity ---
var player_name: String = "Adventurer"
var player_class: String = ""  # "warrior", "ranger", "mage"

# --- Level & XP ---
var level: int = 1
var xp: int = 0
var gold: int = 0

# --- Core Stats ---
var max_hp: int = 50
var current_hp: int = 50
var max_mp: int = 10
var current_mp: int = 10

# --- Attributes ---
var strength: int = 5
var dexterity: int = 5
var intelligence: int = 5
var wisdom: int = 5
var constitution: int = 5
var luck: int = 5

# --- Derived Stats (recalculated from base + equipment) ---
var attack: int = 0
var defense: int = 0
var speed: float = 1.0
var magic_attack: int = 0

# --- Unlocked Skills ---
var unlocked_skills: Array[String] = []

# --- XP Table: XP needed to reach the given level ---
const XP_TABLE: Array[int] = [
	0,      # Level 1 (start)
	100,    # Level 2
	250,    # Level 3
	500,    # Level 4
	850,    # Level 5
	1300,   # Level 6
	1900,   # Level 7
	2650,   # Level 8
	3600,   # Level 9
	4800,   # Level 10
	6300,   # Level 11
	8100,   # Level 12
	10300,  # Level 13
	13000,  # Level 14
	16200,  # Level 15
	20000,  # Level 16
	24500,  # Level 17
	30000,  # Level 18
	36500,  # Level 19
	44000,  # Level 20
]

const MAX_LEVEL: int = 20


func _ready() -> void:
	_load_class_definitions()


# --- Data Loading ---

func _load_class_definitions() -> void:
	var dir_path := "res://data/classes/"
	var dir := DirAccess.open(dir_path)
	if not dir:
		push_warning("PlayerData: No classes directory found at %s" % dir_path)
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
					var class_id: String = data.get("class_id", file_name.get_basename())
					class_definitions[class_id] = data
		file_name = dir.get_next()
	print("PlayerData: Loaded %d class definitions" % class_definitions.size())


# --- Initialization ---

func initialize(p_name: String, p_class: String) -> void:
	player_name = p_name
	player_class = p_class
	level = 1
	xp = 0
	gold = 0
	unlocked_skills.clear()

	if class_definitions.has(p_class):
		var class_data: Dictionary = class_definitions[p_class]
		var base_stats: Dictionary = class_data.get("base_stats", {})
		max_hp = base_stats.get("hp", 50)
		current_hp = max_hp
		max_mp = base_stats.get("mp", 10)
		current_mp = max_mp
		strength = base_stats.get("strength", 5)
		dexterity = base_stats.get("dexterity", 5)
		intelligence = base_stats.get("intelligence", 5)
		wisdom = base_stats.get("wisdom", 5)
		constitution = base_stats.get("constitution", 5)
		luck = base_stats.get("luck", 5)
	else:
		push_warning("PlayerData: Unknown class '%s', using defaults" % p_class)
		_apply_default_stats()

	_recalculate_derived_stats()
	_check_skill_unlocks()
	stats_changed.emit()


func _apply_default_stats() -> void:
	max_hp = 50
	current_hp = 50
	max_mp = 10
	current_mp = 10
	strength = 5
	dexterity = 5
	intelligence = 5
	wisdom = 5
	constitution = 5
	luck = 5


func reset() -> void:
	player_name = "Adventurer"
	player_class = ""
	level = 1
	xp = 0
	gold = 0
	unlocked_skills.clear()
	_apply_default_stats()
	_recalculate_derived_stats()
	stats_changed.emit()


# --- XP & Leveling ---

func add_xp(amount: int) -> void:
	if level >= MAX_LEVEL:
		return
	xp += amount
	xp_gained.emit(amount)
	EventBus.xp_gained.emit("combat", amount)

	# Check for level ups (can be multiple)
	while level < MAX_LEVEL and xp >= xp_for_next_level():
		_level_up()


func xp_for_next_level() -> int:
	if level >= MAX_LEVEL:
		return 999999
	if level < XP_TABLE.size():
		return XP_TABLE[level]
	# Fallback formula for levels beyond the table
	return int(XP_TABLE[XP_TABLE.size() - 1] * pow(1.25, level - XP_TABLE.size() + 1))


func xp_progress() -> float:
	## Returns 0.0-1.0 representing progress toward next level.
	if level >= MAX_LEVEL:
		return 1.0
	var current_threshold: int = XP_TABLE[level - 1] if level - 1 < XP_TABLE.size() else 0
	var next_threshold: int = xp_for_next_level()
	var range_total: int = next_threshold - current_threshold
	if range_total <= 0:
		return 1.0
	return clampf(float(xp - current_threshold) / float(range_total), 0.0, 1.0)


func _level_up() -> void:
	level += 1

	# Apply stat growth from class definition
	if class_definitions.has(player_class):
		var growth: Dictionary = class_definitions[player_class].get("stat_growth", {})
		max_hp += growth.get("hp", 5)
		max_mp += growth.get("mp", 2)
		strength += growth.get("strength", 1)
		dexterity += growth.get("dexterity", 1)
		intelligence += growth.get("intelligence", 1)
		wisdom += growth.get("wisdom", 1)
		constitution += growth.get("constitution", 1)
		luck += growth.get("luck", 1)
	else:
		# Default growth
		max_hp += 5
		max_mp += 2
		strength += 1
		dexterity += 1
		intelligence += 1
		wisdom += 1
		constitution += 1
		luck += 1

	# Full heal on level up
	current_hp = max_hp
	current_mp = max_mp

	_recalculate_derived_stats()
	_check_skill_unlocks()

	level_changed.emit(level)
	EventBus.level_up.emit("combat", level)
	stats_changed.emit()
	print("PlayerData: Level up! Now level %d" % level)


func _check_skill_unlocks() -> void:
	if not class_definitions.has(player_class):
		return
	var skills: Array = class_definitions[player_class].get("skills", [])
	for skill_data in skills:
		var skill_id: String = skill_data.get("skill_id", "")
		var unlock_level: int = skill_data.get("unlock_level", 1)
		if level >= unlock_level and skill_id not in unlocked_skills:
			unlocked_skills.append(skill_id)
			skill_unlocked.emit(skill_id)
			EventBus.show_notification.emit("Skill unlocked: %s" % skill_data.get("name", skill_id))


# --- Derived Stats ---

func _recalculate_derived_stats() -> void:
	# Base derived stats from attributes
	attack = strength + int(dexterity * 0.5)
	defense = constitution + int(strength * 0.3)
	speed = 1.0 + dexterity * 0.02
	magic_attack = intelligence + int(wisdom * 0.5)

	# Add equipment bonuses
	if is_instance_valid(InventoryManager):
		var equip_stats: Dictionary = InventoryManager.get_equipment_stats()
		attack += equip_stats.get("attack_bonus", 0)
		defense += equip_stats.get("defense_bonus", 0)
		magic_attack += equip_stats.get("magic_bonus", 0)
		speed += equip_stats.get("speed_bonus", 0.0)


func recalculate() -> void:
	## Public method to trigger stat recalculation (e.g., after equipping gear).
	_recalculate_derived_stats()
	stats_changed.emit()


# --- HP / MP ---

func take_damage(amount: int) -> void:
	var actual_damage: int = maxi(amount, 0)
	current_hp = maxi(current_hp - actual_damage, 0)
	hp_changed.emit(current_hp, max_hp)
	EventBus.player_damaged.emit(actual_damage)

	if current_hp <= 0:
		player_died.emit()


func heal(amount: int) -> void:
	var actual_heal: int = mini(amount, max_hp - current_hp)
	current_hp = mini(current_hp + amount, max_hp)
	hp_changed.emit(current_hp, max_hp)
	if actual_heal > 0:
		EventBus.player_healed.emit(actual_heal)


func use_mp(amount: int) -> bool:
	if current_mp < amount:
		return false
	current_mp -= amount
	mp_changed.emit(current_mp, max_mp)
	return true


func restore_mp(amount: int) -> void:
	current_mp = mini(current_mp + amount, max_mp)
	mp_changed.emit(current_mp, max_mp)


func is_alive() -> bool:
	return current_hp > 0


func heal_full() -> void:
	current_hp = max_hp
	current_mp = max_mp
	hp_changed.emit(current_hp, max_hp)
	mp_changed.emit(current_mp, max_mp)


# --- Gold ---

func add_gold(amount: int) -> void:
	gold += amount
	stats_changed.emit()


func spend_gold(amount: int) -> bool:
	if gold < amount:
		return false
	gold -= amount
	stats_changed.emit()
	return true


# --- Skill Queries ---

func get_skill_data(skill_id: String) -> Dictionary:
	if not class_definitions.has(player_class):
		return {}
	var skills: Array = class_definitions[player_class].get("skills", [])
	for skill_data in skills:
		if skill_data.get("skill_id") == skill_id:
			return skill_data
	return {}


func get_available_skills() -> Array:
	## Returns full skill data for all unlocked skills.
	var result: Array = []
	if not class_definitions.has(player_class):
		return result
	var skills: Array = class_definitions[player_class].get("skills", [])
	for skill_data in skills:
		if skill_data.get("skill_id", "") in unlocked_skills:
			result.append(skill_data)
	return result


# --- Serialization ---

func serialize() -> Dictionary:
	return {
		"name": player_name,
		"class": player_class,
		"level": level,
		"xp": xp,
		"gold": gold,
		"max_hp": max_hp,
		"current_hp": current_hp,
		"max_mp": max_mp,
		"current_mp": current_mp,
		"strength": strength,
		"dexterity": dexterity,
		"intelligence": intelligence,
		"wisdom": wisdom,
		"constitution": constitution,
		"luck": luck,
		"unlocked_skills": unlocked_skills.duplicate(),
	}


func deserialize(data: Dictionary) -> void:
	player_name = data.get("name", "Adventurer")
	player_class = data.get("class", "")
	level = data.get("level", 1)
	xp = data.get("xp", 0)
	gold = data.get("gold", 0)
	max_hp = data.get("max_hp", 50)
	current_hp = data.get("current_hp", max_hp)
	max_mp = data.get("max_mp", 10)
	current_mp = data.get("current_mp", max_mp)
	strength = data.get("strength", 5)
	dexterity = data.get("dexterity", 5)
	intelligence = data.get("intelligence", 5)
	wisdom = data.get("wisdom", 5)
	constitution = data.get("constitution", 5)
	luck = data.get("luck", 5)
	unlocked_skills.clear()
	for s in data.get("unlocked_skills", []):
		unlocked_skills.append(s)
	_recalculate_derived_stats()
	stats_changed.emit()
