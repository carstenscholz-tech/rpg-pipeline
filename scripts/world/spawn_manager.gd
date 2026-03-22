extends Node
class_name EnemySpawnManager
## Manages enemy spawning in zones. Reads enemy_zones from map data,
## spawns enemies on timers, respects max counts, and scales to player level.

const ENEMY_SCENE_PATH: String = "res://scenes/enemies/enemy.tscn"
const TILE_SIZE: int = 32

## Maximum enemies allowed per spawn zone.
@export var max_per_zone: int = 5
## Base respawn interval in seconds.
@export var respawn_interval: float = 30.0
## Minimum distance from the player to spawn enemies (pixels).
@export var min_spawn_distance: float = 200.0

## Preloaded enemy scene.
var _enemy_scene: PackedScene = null
## Current zone node reference.
var _zone_node: Node2D = null
## Active spawn zone data.
var _spawn_zones: Array = []
## Spawned enemy instances grouped by zone index.
var _spawned_enemies: Dictionary = {}  # zone_index -> Array[Node]
## Respawn timer per zone.
var _respawn_timers: Dictionary = {}  # zone_index -> float
## Enemy data from data/enemies/.
var _enemy_data_cache: Dictionary = {}
## Current zone ID.
var _current_zone_id: String = ""


func _ready() -> void:
	_enemy_scene = load(ENEMY_SCENE_PATH) as PackedScene
	EventBus.enemy_defeated.connect(_on_enemy_defeated)


func _process(delta: float) -> void:
	if _spawn_zones.is_empty() or _zone_node == null:
		return

	# Update respawn timers.
	for zone_idx in _respawn_timers:
		_respawn_timers[zone_idx] -= delta
		if _respawn_timers[zone_idx] <= 0.0:
			_try_spawn_in_zone(zone_idx)
			_respawn_timers[zone_idx] = respawn_interval

	# Clean up dead references.
	for zone_idx in _spawned_enemies:
		var enemies: Array = _spawned_enemies[zone_idx]
		for i in range(enemies.size() - 1, -1, -1):
			if not is_instance_valid(enemies[i]):
				enemies.remove_at(i)


## Set up enemy spawning for a new zone.
func setup_zone(zone_id: String, zone_node: Node2D) -> void:
	# Clear previous spawns.
	clear_all()

	_zone_node = zone_node
	_current_zone_id = zone_id

	# Load map data for enemy zones.
	var map_data: Dictionary = GameData.get_map(zone_id)
	_spawn_zones = map_data.get("enemy_zones", [])

	# Load enemy type data.
	_load_enemy_data()

	# Initialize tracking for each zone.
	for i in range(_spawn_zones.size()):
		_spawned_enemies[i] = []
		_respawn_timers[i] = 2.0  # Short initial delay before first spawn.

	# Initial population.
	for i in range(_spawn_zones.size()):
		var zone_data: Dictionary = _spawn_zones[i]
		var density: float = zone_data.get("density", 0.2)
		var initial_count := int(max_per_zone * density)
		for _j in range(initial_count):
			_try_spawn_in_zone(i)


## Try to spawn an enemy in a specific zone.
func _try_spawn_in_zone(zone_idx: int) -> void:
	if not _enemy_scene or not _zone_node:
		return
	if zone_idx >= _spawn_zones.size():
		return

	var enemies: Array = _spawned_enemies.get(zone_idx, [])
	if enemies.size() >= max_per_zone:
		return

	var zone_data: Dictionary = _spawn_zones[zone_idx]
	var area: Array = zone_data.get("area", [0, 0, 10, 10])
	if area.size() < 4:
		return

	var enemy_types: Array = zone_data.get("enemy_types", [])
	if enemy_types.is_empty():
		return

	var level_range: Array = zone_data.get("level_range", [1, 1])
	var min_level: int = int(level_range[0]) if level_range.size() > 0 else 1
	var max_level: int = int(level_range[1]) if level_range.size() > 1 else min_level

	# Pick a random position within the area (tile coords -> pixel coords).
	var spawn_x := randf_range(float(area[0]), float(area[2])) * TILE_SIZE
	var spawn_y := randf_range(float(area[1]), float(area[3])) * TILE_SIZE

	# Check distance from player.
	var player_nodes := get_tree().get_nodes_in_group("player")
	if player_nodes.size() > 0:
		var player_pos: Vector2 = player_nodes[0].global_position
		if Vector2(spawn_x, spawn_y).distance_to(player_pos) < min_spawn_distance:
			return  # Too close to player; try again next cycle.

	# Pick a random enemy type.
	var enemy_type: String = enemy_types[randi() % enemy_types.size()]

	# Scale level to player level.
	var enemy_level := randi_range(min_level, max_level)
	var player_level: int = _get_player_level()
	# Mild scaling: enemies within +/-2 of player level.
	enemy_level = clampi(enemy_level, max(1, player_level - 2), player_level + 2)

	# Instantiate enemy.
	var enemy_instance := _enemy_scene.instantiate()
	enemy_instance.position = Vector2(spawn_x, spawn_y)

	# Set enemy properties if it has the expected interface.
	if enemy_instance.has_method("setup"):
		var type_data: Dictionary = _enemy_data_cache.get(enemy_type, {})
		enemy_instance.setup(enemy_type, enemy_level, type_data)
	else:
		# Fallback: set properties directly if they exist.
		if "enemy_type" in enemy_instance:
			enemy_instance.enemy_type = enemy_type
		if "level" in enemy_instance:
			enemy_instance.level = enemy_level

	# Add to zone's enemy container or directly to zone.
	var enemy_container := _zone_node.get_node_or_null("Enemies")
	if enemy_container:
		enemy_container.add_child(enemy_instance)
	else:
		_zone_node.add_child(enemy_instance)

	enemies.append(enemy_instance)
	_spawned_enemies[zone_idx] = enemies


## Get the current player combat level (fallback to 1).
func _get_player_level() -> int:
	var stats: Dictionary = SaveManager.save_data.player.get("stats", {})
	return int(stats.get("combat_level", 1))


## Load enemy type data from data/enemies/.
func _load_enemy_data() -> void:
	if not _enemy_data_cache.is_empty():
		return
	var path := "res://data/enemies/"
	var dir := DirAccess.open(path)
	if not dir:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".json"):
			var full_path := path + file_name
			var file := FileAccess.open(full_path, FileAccess.READ)
			if file:
				var json := JSON.new()
				if json.parse(file.get_as_text()) == OK and json.data is Dictionary:
					var data: Dictionary = json.data
					# The starter_enemies.json contains multiple entries.
					if data.has("enemies"):
						for enemy in data.enemies:
							var eid: String = enemy.get("enemy_id", "")
							if eid != "":
								_enemy_data_cache[eid] = enemy
					else:
						var eid: String = data.get("enemy_id", file_name.get_basename())
						_enemy_data_cache[eid] = data
		file_name = dir.get_next()


## Handle enemy death to clean up tracking.
func _on_enemy_defeated(enemy_id: String) -> void:
	# The actual node removal is handled by the enemy itself.
	# We just need to clean our tracking arrays.
	pass


## Remove all spawned enemies and reset.
func clear_all() -> void:
	for zone_idx in _spawned_enemies:
		var enemies: Array = _spawned_enemies[zone_idx]
		for enemy in enemies:
			if is_instance_valid(enemy):
				enemy.queue_free()
	_spawned_enemies.clear()
	_respawn_timers.clear()
	_spawn_zones.clear()
	_zone_node = null
