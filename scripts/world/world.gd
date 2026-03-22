extends Node2D
## Master world scene that manages zone loading, player persistence,
## day/night cycle, and background music.

@onready var zone_container: Node2D = $ZoneContainer
@onready var player: CharacterBody2D = $Player
@onready var zone_manager: Node = $ZoneManager
@onready var npc_spawner: Node = $NPCSpawner
@onready var spawn_manager: Node = $SpawnManager
@onready var fade_overlay: ColorRect = $UILayer/FadeOverlay
@onready var day_night_overlay: ColorRect = $UILayer/DayNightOverlay
@onready var bg_music: AudioStreamPlayer = $BGMusic

## In-game time tracking (0.0 to 24.0 hours).
var game_time: float = 8.0
## How many real seconds per in-game hour.
const SECONDS_PER_GAME_HOUR: float = 60.0
## Whether day/night visual cycle is enabled.
var day_night_enabled: bool = true

## Music tracks per zone (paths to audio files).
var zone_music: Dictionary = {
	"hearthholm": "res://assets/audio/music/peaceful_town.ogg",
	"oldroot_forest": "res://assets/audio/music/mysterious_forest.ogg",
}


func _ready() -> void:
	# Wire up the zone manager.
	zone_manager.zone_container = zone_container
	zone_manager.fade_overlay = fade_overlay
	zone_manager.player = player
	zone_manager.transition_finished.connect(_on_zone_loaded)

	# Make sure fade overlay starts invisible.
	if fade_overlay:
		fade_overlay.visible = false
		fade_overlay.modulate.a = 0.0

	# Initialize day/night overlay.
	if day_night_overlay:
		day_night_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		day_night_overlay.color = Color(0, 0, 0, 0)

	# Determine starting zone.
	var start_zone: String = SaveManager.save_data.player.get("zone", "hearthholm")
	zone_manager.change_zone(start_zone)


func _process(delta: float) -> void:
	# Advance game clock.
	game_time += delta / SECONDS_PER_GAME_HOUR
	if game_time >= 24.0:
		game_time -= 24.0

	# Update day/night overlay.
	if day_night_enabled and day_night_overlay:
		_update_day_night()


func _update_day_night() -> void:
	var darkness: float = 0.0
	# Night: 20:00 - 05:00 (full dark around midnight).
	# Dawn: 05:00 - 07:00.
	# Day: 07:00 - 18:00.
	# Dusk: 18:00 - 20:00.
	if game_time >= 20.0 or game_time < 5.0:
		darkness = 0.45
	elif game_time >= 5.0 and game_time < 7.0:
		# Dawn transition.
		darkness = lerp(0.45, 0.0, (game_time - 5.0) / 2.0)
	elif game_time >= 18.0 and game_time < 20.0:
		# Dusk transition.
		darkness = lerp(0.0, 0.45, (game_time - 18.0) / 2.0)

	# Slight blue tint at night.
	var night_color := Color(0.05, 0.05, 0.2, darkness)
	day_night_overlay.color = night_color


func _on_zone_loaded(zone_id: String) -> void:
	# Update save data.
	SaveManager.save_data.player.zone = zone_id

	# Spawn NPCs for this zone.
	if npc_spawner and npc_spawner.has_method("spawn_npcs_for_zone"):
		npc_spawner.spawn_npcs_for_zone(zone_id, zone_manager.current_zone)

	# Set up enemy spawning.
	if spawn_manager and spawn_manager.has_method("setup_zone"):
		spawn_manager.setup_zone(zone_id, zone_manager.current_zone)

	# Play zone music.
	_play_zone_music(zone_id)


func _play_zone_music(zone_id: String) -> void:
	if not bg_music:
		return
	var music_path: String = zone_music.get(zone_id, "")
	if music_path == "":
		bg_music.stop()
		return
	if ResourceLoader.exists(music_path):
		var stream := load(music_path) as AudioStream
		if stream and bg_music.stream != stream:
			bg_music.stream = stream
			bg_music.play()
	else:
		# Music file not yet created; just keep silent.
		bg_music.stop()


## Get the current game time as a formatted string like "08:30".
func get_time_string() -> String:
	var hours := int(game_time)
	var minutes := int((game_time - float(hours)) * 60.0)
	return "%02d:%02d" % [hours, minutes]
