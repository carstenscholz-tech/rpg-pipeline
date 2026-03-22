extends Node
class_name CombatSystem
## Handles combat calculations and enemy interactions.

func calculate_damage(attacker_stats: Dictionary, defender_stats: Dictionary) -> int:
	var base_attack: int = attacker_stats.get("attack", 1)
	var base_defense: int = defender_stats.get("defense", 0)
	var damage: int = maxi(1, base_attack - base_defense / 2 + randi_range(-2, 2))
	return damage


func calculate_hit_chance(attacker_level: int, defender_level: int) -> float:
	var diff: float = float(attacker_level - defender_level)
	return clampf(0.5 + diff * 0.05, 0.1, 0.95)


func attempt_attack(attacker_stats: Dictionary, defender_stats: Dictionary) -> Dictionary:
	var hit_chance: float = calculate_hit_chance(
		attacker_stats.get("level", 1),
		defender_stats.get("level", 1)
	)

	if randf() > hit_chance:
		return {"hit": false, "damage": 0}

	var damage: int = calculate_damage(attacker_stats, defender_stats)
	return {"hit": true, "damage": damage}


func calculate_xp_reward(enemy_level: int) -> int:
	return enemy_level * 10 + randi_range(0, enemy_level * 2)
