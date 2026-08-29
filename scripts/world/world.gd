extends Node

## World autoload.
## Owns the global OsmData dataset and terrain, and provides coordinate
## utilities used across the game (e.g. which tile a position belongs to).

const TILE_SIZE := 500.0

var osm_data: OsmData = null
var terrain: Dictionary = {}

## Whether we're running the playable built-in prototype district (true)
## vs. the full imported city (once real OSM data is imported).
var prototype_mode: bool = true

func _ready() -> void:
	pass

## Tile origin (Vector3) for a given world position.
func tile_origin(pos: Vector3) -> Vector3:
	var tx: float = floor(pos.x / TILE_SIZE) * TILE_SIZE
	var tz: float = floor(pos.z / TILE_SIZE) * TILE_SIZE
	return Vector3(tx, 0.0, tz)

func tile_key(tile_origin_pos: Vector3) -> Vector2i:
	return Vector2i(round(tile_origin_pos.x / TILE_SIZE), round(tile_origin_pos.z / TILE_SIZE))

func tile_key_from_pos(pos: Vector3) -> Vector2i:
	return tile_key(tile_origin(pos))

func world_height_at(pos: Vector3) -> float:
	return ProceduralGen.terrain_height(terrain, pos)

## Set the active dataset. Called by the importer/generator at startup.
func set_world_data(data: OsmData, terrain_data: Dictionary) -> void:
	osm_data = data
	terrain = terrain_data
