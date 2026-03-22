extends Node
class_name InteractionHandler
## Detects interactable objects within the player's InteractionZone (Area2D)
## and handles interaction priority and prompt display.

## Interaction priority — lower number = higher priority.
const PRIORITY: Dictionary = {
	"npc": 0,
	"chest": 1,
	"item": 2,
	"sign": 3,
	"default": 10,
}

## Reference to the Area2D parent that acts as the interaction zone.
@onready var zone: Area2D = get_parent()
## CollisionShape2D of the interaction zone, repositioned based on facing.
@onready var zone_shape: CollisionShape2D = get_parent().get_node("InteractionShape")

## Currently tracked interactables inside the zone.
var _nearby: Array[Node2D] = []
## The best-priority target right now.
var _current_target: Node2D = null

const ZONE_OFFSET: float = 12.0


func _ready() -> void:
	zone.body_entered.connect(_on_body_entered)
	zone.body_exited.connect(_on_body_exited)
	zone.area_entered.connect(_on_area_entered)
	zone.area_exited.connect(_on_area_exited)


func _process(_delta: float) -> void:
	var best: Node2D = _get_best_target()
	if best != _current_target:
		_current_target = best
		_update_prompt()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Called by PlayerController when the player presses interact.
func try_interact() -> void:
	if _current_target == null:
		return

	EventBus.player_interacted.emit(_current_target)

	if _current_target.has_method("interact"):
		_current_target.interact()
	elif _current_target.has_meta("interactable"):
		# Fallback: look for a parent with interact().
		var parent := _current_target.get_parent()
		if parent and parent.has_method("interact"):
			parent.interact()


## Called by PlayerController to reposition the zone collision shape.
func update_facing(facing: Vector2) -> void:
	if zone_shape:
		zone_shape.position = facing * ZONE_OFFSET


# ---------------------------------------------------------------------------
# Target selection
# ---------------------------------------------------------------------------

func _get_best_target() -> Node2D:
	# Remove freed references.
	_nearby = _nearby.filter(func(n: Node2D) -> bool: return is_instance_valid(n))

	if _nearby.is_empty():
		return null

	var best: Node2D = _nearby[0]
	var best_prio: int = _get_priority(best)

	for node in _nearby:
		var prio: int = _get_priority(node)
		if prio < best_prio:
			best = node
			best_prio = prio
		elif prio == best_prio:
			# Tie-break by distance to player.
			var player: Node2D = zone.get_parent()
			if player and node.global_position.distance_squared_to(player.global_position) < best.global_position.distance_squared_to(player.global_position):
				best = node
				best_prio = prio

	return best


func _get_priority(node: Node2D) -> int:
	if node.has_meta("interact_type"):
		var itype: String = node.get_meta("interact_type")
		return PRIORITY.get(itype, PRIORITY["default"])

	# Infer type from groups.
	if node.is_in_group("npc"):
		return PRIORITY["npc"]
	if node.is_in_group("chest"):
		return PRIORITY["chest"]
	if node.is_in_group("item") or node.is_in_group("pickup"):
		return PRIORITY["item"]
	if node.is_in_group("sign"):
		return PRIORITY["sign"]

	return PRIORITY["default"]


# ---------------------------------------------------------------------------
# Prompt display
# ---------------------------------------------------------------------------

func _update_prompt() -> void:
	if _current_target:
		var label: String = _get_prompt_label(_current_target)
		EventBus.show_tooltip.emit(label, _current_target.global_position + Vector2(0, -16))
	else:
		EventBus.hide_tooltip.emit()


func _get_prompt_label(node: Node2D) -> String:
	if node.has_meta("prompt_text"):
		return node.get_meta("prompt_text")
	if node.is_in_group("npc"):
		return "[E] Talk"
	if node.is_in_group("chest"):
		return "[E] Open"
	if node.is_in_group("item") or node.is_in_group("pickup"):
		return "[E] Pick up"
	if node.is_in_group("sign"):
		return "[E] Read"
	return "[E] Interact"


# ---------------------------------------------------------------------------
# Area / body enter/exit callbacks
# ---------------------------------------------------------------------------

func _on_body_entered(body: Node2D) -> void:
	if body == zone.get_parent():
		return
	if _is_interactable(body) and body not in _nearby:
		_nearby.append(body)


func _on_body_exited(body: Node2D) -> void:
	_nearby.erase(body)
	if _current_target == body:
		_current_target = null
		_update_prompt()


func _on_area_entered(area: Area2D) -> void:
	var owner_node: Node2D = area.get_parent()
	if owner_node and owner_node != zone.get_parent() and _is_interactable(owner_node):
		if owner_node not in _nearby:
			_nearby.append(owner_node)


func _on_area_exited(area: Area2D) -> void:
	var owner_node: Node2D = area.get_parent()
	_nearby.erase(owner_node)
	if _current_target == owner_node:
		_current_target = null
		_update_prompt()


func _is_interactable(node: Node2D) -> bool:
	if node.has_method("interact"):
		return true
	if node.has_meta("interactable"):
		return true
	if node.is_in_group("npc") or node.is_in_group("chest") or node.is_in_group("item") or node.is_in_group("pickup") or node.is_in_group("sign"):
		return true
	return false
