extends Node
## Global signal bus for cross-system communication.
## All systems emit and connect signals through this autoload.

# --- Dialogue ---
signal start_dialogue(npc_id: String, dialogue_data: Dictionary)
signal dialogue_choice_made(node_id: String)
signal dialogue_ended()

# --- Inventory ---
signal item_added(item_id: String, quantity: int)
signal item_removed(item_id: String, quantity: int)
signal inventory_updated()

# --- Shop ---
signal open_shop(shop_data: Dictionary)
signal shop_closed()
signal item_purchased(item_id: String)
signal item_sold(item_id: String)

# --- Quest ---
signal quest_started(quest_id: String)
signal quest_step_completed(quest_id: String, step_id: int)
signal quest_completed(quest_id: String)
signal quest_updated(quest_id: String)

# --- Combat ---
signal enemy_damaged(enemy_id: String, damage: int)
signal enemy_defeated(enemy_id: String)
signal player_damaged(damage: int)
signal player_healed(amount: int)
signal loot_dropped(item_id: String, position: Vector2)
signal boss_defeated(boss_id: String)

# --- Skills ---
signal xp_gained(skill_id: String, amount: int)
signal level_up(skill_id: String, new_level: int)

# --- Player ---
signal player_moved(position: Vector2)
signal player_interacted(target: Node2D)
signal player_attacked(direction: Vector2)
signal player_state_changed(new_state: String)

# --- World ---
signal zone_entered(zone_id: String)
signal zone_exited(zone_id: String)
signal npc_interacted(npc_id: String)

# --- UI ---
signal show_notification(message: String)
signal show_tooltip(text: String, position: Vector2)
signal hide_tooltip()
signal open_inventory()
signal close_inventory()
signal open_quest_log()
signal close_quest_log()
signal dialogue_node_displayed(npc_id: String, text: String, responses: Array)

# --- Player stats (for HUD) ---
signal player_hp_changed(current: int, maximum: int)
signal player_mp_changed(current: int, maximum: int)
signal player_xp_changed(current: int, needed: int)
signal player_level_changed(new_level: int)
signal player_gold_changed(amount: int)
signal target_changed(target_data: Dictionary)
signal target_cleared()

# --- Character creation ---
signal character_created(char_name: String, char_class: String)

# --- Save/Load ---
signal game_saved()
signal game_loaded()
