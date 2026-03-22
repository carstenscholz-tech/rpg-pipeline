extends Node
class_name NPCSpawner
## Loads NPC data from GameData and instances NPC scenes into the current zone.

const NPC_SCENE_PATH: String = "res://scenes/npcs/npc.tscn"

## Currently spawned NPC instances keyed by npc_id.
var spawned_npcs: Dictionary = {}
## Preloaded NPC packed scene.
var _npc_scene: PackedScene = null


func _ready() -> void:
	_npc_scene = load(NPC_SCENE_PATH) as PackedScene
	if not _npc_scene:
		push_warning("NPCSpawner: Could not load NPC scene at '%s'" % NPC_SCENE_PATH)


## Spawn all NPCs that belong to the given zone.
func spawn_npcs_for_zone(zone_id: String, zone_node: Node2D) -> void:
	# Clear any previously spawned NPCs.
	despawn_all()

	if not _npc_scene:
		_npc_scene = load(NPC_SCENE_PATH) as PackedScene
		if not _npc_scene:
			push_warning("NPCSpawner: NPC scene not available.")
			return

	# Get the map data to find NPC spawn list.
	var map_data: Dictionary = GameData.get_map(zone_id)
	var npc_list: Array = map_data.get("npc_spawns", [])

	for npc_id in npc_list:
		var npc_data: Dictionary = GameData.get_npc(npc_id)
		if npc_data.is_empty():
			push_warning("NPCSpawner: No data for NPC '%s'" % npc_id)
			continue

		# Verify this NPC belongs to this zone.
		var npc_zone: String = npc_data.get("location", {}).get("zone", "")
		if npc_zone != zone_id:
			continue

		_spawn_npc(npc_id, npc_data, zone_node)


## Instantiate a single NPC and add it to the zone.
func _spawn_npc(npc_id: String, npc_data: Dictionary, parent: Node2D) -> void:
	var npc_instance = _npc_scene.instantiate()
	if not npc_instance:
		push_warning("NPCSpawner: Failed to instantiate NPC scene for '%s'" % npc_id)
		return

	# Set NPC properties.
	npc_instance.npc_id = npc_id
	npc_instance.npc_data = npc_data
	npc_instance.display_name = npc_data.get("name", npc_id)

	# Position from data (pixel coordinates).
	var location: Dictionary = npc_data.get("location", {})
	var pos_x: float = float(location.get("x", 0))
	var pos_y: float = float(location.get("y", 0))

	# First try to find a named Marker2D in the zone scene.
	var marker_name := "NPC_" + npc_id
	var marker := _find_marker(parent, marker_name)
	if marker:
		npc_instance.position = marker.position
	else:
		npc_instance.position = Vector2(pos_x, pos_y)

	# Add to the zone's NPC container if it exists, otherwise directly to zone.
	var npc_container := parent.get_node_or_null("NPCs")
	if npc_container:
		npc_container.add_child(npc_instance)
	else:
		parent.add_child(npc_instance)

	# Set the home position for idle wandering.
	npc_instance._home_position = npc_instance.global_position

	spawned_npcs[npc_id] = npc_instance


## Remove all spawned NPCs.
func despawn_all() -> void:
	for npc_id in spawned_npcs:
		var npc := spawned_npcs[npc_id] as Node
		if is_instance_valid(npc):
			npc.queue_free()
	spawned_npcs.clear()


## Get a spawned NPC by ID.
func get_npc(npc_id: String) -> Node:
	return spawned_npcs.get(npc_id, null)


## Find a Marker2D in the node tree by name.
func _find_marker(node: Node, marker_name: String) -> Marker2D:
	if node is Marker2D and node.name == marker_name:
		return node as Marker2D
	for child in node.get_children():
		var found := _find_marker(child, marker_name)
		if found:
			return found
	return null


## Update quest indicators on all spawned NPCs.
func refresh_quest_icons() -> void:
	for npc_id in spawned_npcs:
		var npc = spawned_npcs[npc_id]
		if is_instance_valid(npc) and npc.has_method("_update_quest_icon"):
			npc._update_quest_icon()
