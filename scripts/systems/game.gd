extends Node

## Central game state and bootstrap autoload.
## Holds the player's spawn point, saved game state, and global settings.

const SAVE_PATH := "user://savegame.json"

var player_spawn: Vector3 = Vector3(0, 0, 0)
var current_weather: String = "clear"
var time_of_day: float = 10.0

## Directory where imported/generated Jacksonville data lives (user:// so it can change).
const DATA_DIR := "user://jax_data"

func spawn_point() -> Vector3:
	return player_spawn

func _ready() -> void:
	# Ensure the data directory exists at runtime.
	DirAccess.make_dir_recursive_absolute(DATA_DIR)

## Save player position and state to disk.
func save_game(target_pos: Vector3, extra: Dictionary = {}) -> bool:
	var data := {
		"player_pos": {
			"x": target_pos.x,
			"y": target_pos.y,
			"z": target_pos.z,
		},
		"time_of_day": time_of_day,
		"weather": current_weather,
	}
	data.merge(extra)
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Could not open save file: %s" % SAVE_PATH)
		return false
	file.store_string(JSON.stringify(data))
	file.close()
	return true

## Load saved game state. Returns true if a save exists.
func load_game() -> Dictionary:
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	if parsed is Dictionary:
		var pos: Dictionary = parsed.get("player_pos", {})
		player_spawn = Vector3(float(pos.get("x", 0.0)), float(pos.get("y", 0.0)), float(pos.get("z", 0.0)))
		time_of_day = float(parsed.get("time_of_day", 10.0))
		current_weather = parsed.get("weather", "clear")
		return parsed
	return {}

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func delete_save() -> void:
	DirAccess.remove_absolute(SAVE_PATH)
