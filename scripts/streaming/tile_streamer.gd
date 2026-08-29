extends Node

## Divides the city into square map tiles (default 500m) and streams them.
## - Tracks the player's tile; spawns all tiles within `stream_radius`
##   tiles of the player, and frees tiles beyond `unload_radius`.
## - Each tile is built procedurally from the global OsmData + terrain via
##   the World generator, so only constructors run at runtime (fast).

const TILE_SIZE := 500.0

@export var stream_radius := 3   # tiles loaded around the player
@export var unload_radius := 5   # tiles beyond this are freed

var _tiles: Dictionary = {}   # Vector2i -> Node3D (tile root)
var _target: Node3D = null

func _ready() -> void:
	# We watch the player node position each frame.
	set_process(true)

func set_target(node: Node3D) -> void:
	_target = node

func _process(_delta: float) -> void:
	if _target == null:
		return
	var player_tile := World.tile_key_from_pos(_target.global_position)
	_update_streaming(player_tile)

## Load/unload tiles based on the player's current tile.
func _update_streaming(player_tile: Vector2i) -> void:
	# Desired loaded tiles.
	var desired: Dictionary = {}
	for dz in range(-stream_radius, stream_radius + 1):
		for dx in range(-stream_radius, stream_radius + 1):
			var key: Vector2i = player_tile + Vector2i(dx, dz)
			# Only stream areas within the city bounds to avoid void.
			if _is_within_bounds(key):
				desired[key] = true

	# Load new tiles.
	for key in desired:
		if not _tiles.has(key):
			_spawn_tile(key)

	# Unload distant tiles (beyond unload_radius) to control memory.
	var to_free: Array = []
	for key in _tiles:
		var rel: Vector2i = key - player_tile
		var dist: int = maxi(abs(rel.x), abs(rel.y))
		if dist > unload_radius:
			to_free.append(key)
	for key in to_free:
		_unload_tile(key)

func _is_within_bounds(tile_key: Vector2i) -> bool:
	if World.osm_data == null:
		# Even without data, allow streaming around the origin for the flat prototype.
		return maxi(abs(tile_key.x), abs(tile_key.y)) <= 8
	var min_t: Vector2i = World.tile_key(Vector3(World.osm_data.bounds_min.x, 0, World.osm_data.bounds_min.y))
	var max_t: Vector2i = World.tile_key(Vector3(World.osm_data.bounds_max.x, 0, World.osm_data.bounds_max.y)) + Vector2i(1, 1)
	return tile_key.x >= min_t.x and tile_key.x <= max_t.x and tile_key.y >= min_t.y and tile_key.y <= max_t.y

func _spawn_tile(key: Vector2i) -> void:
	var origin := Vector3(key.x * TILE_SIZE, 0.0, key.y * TILE_SIZE)
	var tile: Node3D = WorldGenerator.build_tile(origin, TILE_SIZE)
	if tile == null:
		tile = Node3D.new()  # ensure we still track an empty tile
	tile.name = "Tile_%d_%d" % [key.x, key.y]
	add_child(tile)
	_tiles[key] = tile

func _unload_tile(key: Vector2i) -> void:
	var tile: Node = _tiles.get(key)
	if tile != null:
		tile.queue_free()
	_tiles.erase(key)

func tile_count() -> int:
	return _tiles.size()

## For HUD/streaming metrics.
func loaded_tiles() -> int:
	return _tiles.size()
