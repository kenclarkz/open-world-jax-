extends Node

## World autoload.
## Owns the global OsmData dataset and terrain, and provides coordinate
## utilities used across the game (e.g. which chunk a position belongs to).
## Also keeps a spatial chunk index (one bucket per chunk) so the streamer
## only ever builds/instantiates the chunks near the player instead of the
## entire city.

var tile_size: float = 500.0

var osm_data: OsmData = null
var terrain: Dictionary = {}

## Spatial index: chunk key (Vector2i) -> {"roads": [], "buildings": [],
## "parks": [], "water": [], "pois": []}. Built once per dataset.
## Roads are bucketed into every chunk their bbox crosses (and then clipped
## per chunk); areas/POIs belong to the single chunk owning their center.
var chunk_index: Dictionary = {}

## Whether we're running the playable built-in prototype district (true)
## vs. the full imported city (once real OSM data is imported).
var prototype_mode: bool = true

func _ready() -> void:
	pass

## Tile origin (Vector3) for a given world position.
func tile_origin(pos: Vector3) -> Vector3:
	var tx: float = floor(pos.x / tile_size) * tile_size
	var tz: float = floor(pos.z / tile_size) * tile_size
	return Vector3(tx, 0.0, tz)

## Bottom-left world corner of a chunk key.
func chunk_origin(key: Vector2i) -> Vector3:
	return Vector3(key.x * tile_size, 0.0, key.y * tile_size)

## Chunk key for a position (floor, so chunk borders are stable).
func chunk_key_from_pos(pos: Vector3) -> Vector2i:
	return Vector2i(floor(pos.x / tile_size), floor(pos.z / tile_size))

func tile_key(tile_origin_pos: Vector3) -> Vector2i:
	return Vector2i(round(tile_origin_pos.x / tile_size), round(tile_origin_pos.z / tile_size))

func tile_key_from_pos(pos: Vector3) -> Vector2i:
	return tile_key(tile_origin(pos))

func world_height_at(pos: Vector3) -> float:
	return ProceduralGen.terrain_height(terrain, pos)

## Set the active dataset and (re)build the chunk spatial index.
func set_world_data(data: OsmData, terrain_data: Dictionary) -> void:
	osm_data = data
	terrain = terrain_data
	build_chunk_index()

## Assign every OSM feature to the chunk(s) it belongs to.
func build_chunk_index() -> void:
	chunk_index.clear()
	if osm_data == null:
		return

	for road in osm_data.roads:
		if road.points.size() < 2:
			continue
		var min_k := _key_of(road.points[0])
		var max_k := min_k
		for p in road.points:
			var k := _key_of(p)
			min_k.x = mini(min_k.x, k.x)
			min_k.y = mini(min_k.y, k.y)
			max_k.x = maxi(max_k.x, k.x)
			max_k.y = maxi(max_k.y, k.y)
		for z in range(min_k.y, max_k.y + 1):
			for x in range(min_k.x, max_k.x + 1):
				_add_to_chunk(Vector2i(x, z), "roads", road)

	for b in osm_data.buildings:
		if b.polygon.size() >= 3:
			_add_to_chunk(_key_of(_poly_center(b.polygon)), "buildings", b)

	for w in osm_data.water_bodies:
		if w.polygon.size() >= 3:
			_add_to_chunk(_key_of(_poly_center(w.polygon)), "water", w)

	for pk in osm_data.parks:
		if pk.polygon.size() >= 3:
			_add_to_chunk(_key_of(_poly_center(pk.polygon)), "parks", pk)

	for poi in osm_data.pois:
		_add_to_chunk(_key_of(poi.position), "pois", poi)

## Returns the pre-indexed features for a chunk key (never null).
func chunk_contents(key: Vector2i) -> Dictionary:
	var c: Dictionary = chunk_index.get(key, {})
	if c.is_empty():
		return {"roads": [], "buildings": [], "parks": [], "water": [], "pois": []}
	return c

func _key_of(pos: Vector3) -> Vector2i:
	return Vector2i(floor(pos.x / tile_size), floor(pos.z / tile_size))

func _poly_center(poly: PackedVector2Array) -> Vector3:
	if poly.is_empty():
		return Vector3.ZERO
	var sum := Vector2.ZERO
	for p in poly:
		sum += p
	return Vector3(sum.x / poly.size(), 0.0, sum.y / poly.size())

func _add_to_chunk(key: Vector2i, cat: String, obj) -> void:
	if not chunk_index.has(key):
		chunk_index[key] = {"roads": [], "buildings": [], "parks": [], "water": [], "pois": []}
	chunk_index[key][cat].append(obj)