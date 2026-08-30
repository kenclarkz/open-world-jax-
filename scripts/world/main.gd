extends Node3D

## Main scene controller.
## Bootstraps the world at startup:
##   1. Loads terrain (real elevation file if placed, else generated).
##   2. Imports / loads the OSM dataset for Jacksonville.
##   3. Seeds a few traffic cars and pedestrians near the player.
##   4. Hands the player node to the TileStreamer.
##
## It checks user data first (where the README tells the user to drop
## downloads) and falls back to a built-in prototype district that lets
## the game run with zero external data.

## Where the user drops downloaded OSM / elevation data (see README).
const USER_OSM := "user://jax_data/osm/jacksonville.osm"
const USER_OSM_JSON := "user://jax_data/osm/jacksonville.json"
const USER_ELEV := "user://jax_data/elevation/jacksonville.asc"

@onready var player: Player = $Player
@onready var day_night: Node3D = $DayNight
@onready var weather: Node3D = $Weather

var _traffic_spawned := false

func _ready() -> void:
	# Streaming setup.
	TileStreamer.set_target(player)
	player.add_to_group("player")

	# System setup.
	if Game.has_save():
		Game.load_game()
		player.global_position = Game.player_spawn
		print("[Main] Restored player from save at ", Game.player_spawn)

	# Terrain.
	var elev_path := ""
	if ResourceLoader.exists(USER_ELEV) or FileAccess.file_exists(USER_ELEV):
		elev_path = USER_ELEV
	var elevation: ElevationImporter = ElevationImporter.new()
	var terrain := elevation.load_terrain(elev_path)
	World.terrain = terrain

	# OSM data.
	var osm_path := ""
	if FileAccess.file_exists(USER_OSM):
		osm_path = USER_OSM
	elif FileAccess.file_exists(USER_OSM_JSON):
		osm_path = USER_OSM_JSON
	var data: OsmData = OSMImporter.import_file(osm_path) if osm_path != "" else null
	if data == null:
		# Built-in playable prototype district (downtown JAX) so the game
		# runs with zero downloaded data. Replaced once OSM is imported.
		data = PrototypeGen.generate()
	World.set_world_data(data, terrain)
	World.prototype_mode = (osm_path == "")

	# Teleport to an interesting spot if no save: use city center.
	if not Game.has_save():
		var spawn := _find_spawn_point()
		player.global_position = spawn
		player.camera_rig.global_position = spawn
		print("[Main] Spawned at ", spawn)

	# Initial streaming so chunks exist before first player move.
	TileStreamer.refresh()

	# Spawn traffic + pedestrians around the player after streaming.
	call_deferred("_spawn_npcs_around", player.global_position)

func _find_spawn_point() -> Vector3:
	# Prefer a road intersection; else use bounds center.
	if World.osm_data != null and World.osm_data.roads.size() > 0:
		var r: OsmRoad = World.osm_data.roads[0]
		if r.points.size() >= 2:
			var center: Vector3 = (r.points[0] + r.points[r.points.size() - 1]) * 0.5
			center.y = World.world_height_at(center) + 1.0
			return center
	var center_xy: Vector2 = (World.osm_data.bounds_min + World.osm_data.bounds_max) * 0.5 if World.osm_data != null else Vector2.ZERO
	var spawn := Vector3(center_xy.x, 0, center_xy.y)
	spawn.y = World.world_height_at(spawn) + 1.0
	return spawn

func _spawn_npcs_around(center: Vector3) -> void:
	if _traffic_spawned:
		return
	_traffic_spawned = true
	# Drivable vehicles (group "car" so the player can enter them).
	for i in 3:
		var v = preload("res://scenes/Vehicle.tscn").instantiate()
		var off := Vector3(randf_range(-8, 8), 1.2, randf_range(-8, 8))
		v.position = center + Vector3(0, 1, 0) + off
		v.add_to_group("car")
		add_child(v)
	# Traffic cars.
	for i in 5:
		var car := preload("res://scenes/TrafficCar.tscn").instantiate()
		car.position = center + Vector3(randf_range(-100, 100), 1, randf_range(-100, 100))
		add_child(car)
	# Pedestrians.
	for i in 8:
		var p := preload("res://scenes/Pedestrian.tscn").instantiate()
		p.position = center + Vector3(randf_range(-60, 60), 0, randf_range(-60, 60))
		p.add_to_group("pedestrian")
		add_child(p)
	print("[Main] Spawned NPCs around ", center)
