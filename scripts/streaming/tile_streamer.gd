extends Node

## Proximity-based world streaming.
## Divides the imported OSM city into a grid of chunks (default 500 m) and
## keeps only the chunks around the player instantiated, freeing the rest.
##
## Each chunk is tracked in a cache with an explicit state:
##   UNLOADED (not tracked) -> LOADING -> LOADED -> UNLOADING -> UNLOADED
## Building a chunk is split in two phases so it never freezes gameplay:
##   * geometry data pass (WorldGenerator.build_chunk_data) runs on a worker
##     thread (or synchronously when threading is disabled),
##   * node instantiation (WorldGenerator.instantiate_chunk) runs here, on the
##     main thread, spread over a few frames (max_instances_per_frame).
##
## Guarantees:
##   * the chunk containing the player is never unloaded,
##   * a chunk is never requested twice while it is already loading/loaded,
##   * chunks outside `unload_radius` are unloaded (with a short grace period
##     so walking along a chunk border doesn't thrash load/unload).

enum State { UNLOADED, LOADING, LOADED, UNLOADING }

## Chunk edge length in metres; must match World.tile_size.
@export_range(100.0, 2000.0) var tile_size := 500.0
## Chunks loaded around the player (Chebyshev distance).
@export_range(0, 8) var stream_radius := 2
## Chunks kept before unloading; capped at >= stream_radius.
@export_range(0, 8) var unload_radius := 3
## Build chunks on a worker thread instead of the main thread.
@export var background_load := true
## How many finished chunks to instantiate per frame (avoids hitches).
@export_range(1, 60) var max_instances_per_frame := 2

const _UNLOAD_GRACE_FRAMES := 6

## State cache: chunk key (Vector2i) ->
## { "state": int, "node": Node3D, "thread": Thread, "data": Dictionary, "object_count": int }
var _chunks: Dictionary = {}
## Chunks waiting to be freed: key -> Node3D (still in the tree until grace ends).
var _unloading: Dictionary = {}
## Remaining grace frames per unloading chunk.
var _unload_grace: Dictionary = {}

var _target: Node3D = null
var _player_chunk := Vector2i(0, 0)

signal chunk_state_changed(key: Vector2i, new_state: int)

func _ready() -> void:
	_apply_config()
	set_process(true)

## Join any still-running build threads so we exit cleanly.
func _exit_tree() -> void:
	for key in _chunks:
		var th: Thread = _chunks[key]["thread"]
		if th != null and th.is_started():
			th.wait_to_finish()

## Read inspector/project-settings streaming config and sync World's tile size.
func _apply_config() -> void:
	tile_size = ProjectSettings.get_setting("streaming/tile_size", tile_size)
	stream_radius = int(ProjectSettings.get_setting("streaming/stream_radius", stream_radius))
	unload_radius = int(ProjectSettings.get_setting("streaming/unload_radius", unload_radius))
	background_load = bool(ProjectSettings.get_setting("streaming/background_load", background_load))
	max_instances_per_frame = int(ProjectSettings.get_setting("streaming/max_instances_per_frame", max_instances_per_frame))
	unload_radius = maxi(unload_radius, stream_radius)
	World.tile_size = tile_size
	if World.osm_data != null:
		World.build_chunk_index()
	print("[TileStreamer] %dm chunks, stream_radius=%d, unload_radius=%d, background=%s" % [
		World.tile_size, stream_radius, unload_radius, background_load])

## The node (player) the stream follows.
func set_target(node: Node3D) -> void:
	_target = node

func _process(_delta: float) -> void:
	if _target == null or World.osm_data == null:
		return
	_poll_loading()
	_decay_unloads()
	var chunk := World.tile_key_from_pos(_target.global_position)
	if chunk != _player_chunk:
		_player_chunk = chunk
		_update_streaming(chunk)

## Force an immediate streaming pass (used after data load / teleports).
func refresh() -> void:
	if _target == null or World.osm_data == null:
		return
	_player_chunk = World.tile_key_from_pos(_target.global_position)
	_update_streaming(_player_chunk)

## Load the desired radius, cancel unwanted unloads, and schedule far chunks
## for unloading. `player_chunk` is always kept loaded by construction.
func _update_streaming(player_chunk: Vector2i) -> void:
	var desired := {}
	for dz in range(-stream_radius, stream_radius + 1):
		for dx in range(-stream_radius, stream_radius + 1):
			var key: Vector2i = player_chunk + Vector2i(dx, dz)
			if _is_within_bounds(key):
				desired[key] = true

	# Start loading missing chunks; cancel unloads for chunks still desired.
	for key in desired:
		if _chunks.has(key):
			var state: int = _chunks[key]["state"]
			if state == State.UNLOADING:
				_unloading.erase(key)
				_unload_grace.erase(key)
				_chunks[key]["state"] = State.LOADED
				_emit_state(key, State.LOADED)
		else:
			_begin_load(key)

	# Schedule chunks beyond the unload radius for unloading.
	var to_unload: Array = []
	for key in _chunks:
		if _chunks[key]["state"] != State.LOADED:
			continue
		var rel: Vector2i = key - player_chunk
		if maxi(abs(rel.x), abs(rel.y)) > unload_radius:
			to_unload.append(key)
	for key in to_unload:
		_begin_unload(key)

func _begin_load(key: Vector2i) -> void:
	var entry := {"state": State.LOADING, "node": null, "thread": null, "data": {}, "object_count": 0}
	_chunks[key] = entry
	_emit_state(key, State.LOADING)
	if background_load:
		var th := Thread.new()
		var err := th.start(_build_chunk.bind(key))
		if err == OK:
			entry["thread"] = th
			return
		push_warning("[TileStreamer] Thread start failed (%d); building synchronously." % err)
	entry["data"] = WorldGenerator.build_chunk_data(key)
	_instantiate(key, entry)

func _build_chunk(key: Vector2i) -> Dictionary:
	return WorldGenerator.build_chunk_data(key)

## Instantiate finished chunks on the main thread, respecting the per-frame budget.
func _poll_loading() -> void:
	var done: Array = []
	for key in _chunks:
		var entry: Dictionary = _chunks[key]
		if entry["state"] == State.LOADING and entry["thread"] != null:
			var th: Thread = entry["thread"]
			if not th.is_alive():
				done.append(key)
	var budget := maxi(max_instances_per_frame, 1)
	for key in done:
		if budget <= 0:
			break
		budget -= 1
		var entry: Dictionary = _chunks[key]
		var th: Thread = entry["thread"]
		entry["thread"] = null
		entry["data"] = th.wait_to_finish()
		_instantiate(key, entry)

func _instantiate(key: Vector2i, entry: Dictionary) -> void:
	var node := WorldGenerator.instantiate_chunk(entry["data"])
	entry["node"] = node
	entry["object_count"] = int(entry["data"].get("object_count", 0))
	node.name = "Chunk_%d_%d" % [key.x, key.y]
	add_child(node)
	entry["state"] = State.LOADED
	_emit_state(key, State.LOADED)

func _begin_unload(key: Vector2i) -> void:
	_chunks[key]["state"] = State.UNLOADING
	_unloading[key] = _chunks[key]["node"]
	_unload_grace[key] = _UNLOAD_GRACE_FRAMES
	_emit_state(key, State.UNLOADING)

func _decay_unloads() -> void:
	if _unload_grace.is_empty():
		return
	for key in _unload_grace.keys():
		_unload_grace[key] = int(_unload_grace[key]) - 1
	var to_free: Array = []
	for key in _unload_grace:
		if int(_unload_grace[key]) <= 0:
			to_free.append(key)
	for key in to_free:
		var node: Node3D = _unloading.get(key)
		if node != null and is_instance_valid(node):
			if node.get_parent() != null:
				remove_child(node)
			node.queue_free()
		_unloading.erase(key)
		_unload_grace.erase(key)
		_chunks.erase(key)
		_emit_state(key, State.UNLOADED)

func _is_within_bounds(tile_key: Vector2i) -> bool:
	if World.osm_data == null:
		# Even without data, allow streaming around the origin for the prototype.
		return maxi(abs(tile_key.x), abs(tile_key.y)) <= 8
	var min_b := World.osm_data.bounds_min
	var max_b := World.osm_data.bounds_max
	var min_t := Vector2i(floor(min_b.x / World.tile_size), floor(min_b.y / World.tile_size))
	var max_t := Vector2i(floor(max_b.x / World.tile_size), floor(max_b.y / World.tile_size)) + Vector2i(1, 1)
	return tile_key.x >= min_t.x and tile_key.x <= max_t.x \
		and tile_key.y >= min_t.y and tile_key.y <= max_t.y

func _emit_state(key: Vector2i, new_state: int) -> void:
	chunk_state_changed.emit(key, new_state)

# ---------------------------------------------------------------------------
# Debug / HUD stats
# ---------------------------------------------------------------------------

func current_chunk_key() -> Vector2i:
	return _player_chunk

func loaded_chunk_count() -> int:
	var n := 0
	for entry in _chunks.values():
		if entry["state"] == State.LOADED:
			n += 1
	return n

## Chunks still being built (async or instantiation queue).
func loading_chunk_count() -> int:
	var n := 0
	for entry in _chunks.values():
		if entry["state"] == State.LOADING:
			n += 1
	return n

func unloading_chunk_count() -> int:
	return _unloading.size()

## Total chunks currently tracked (loading + loaded + unloading).
func tracked_chunk_count() -> int:
	return _chunks.size()

## Approximate number of scene objects (meshes + collision bodies) instantiated.
func active_object_count() -> int:
	var n := 0
	for entry in _chunks.values():
		if entry["state"] == State.LOADED:
			n += int(entry["object_count"])
	return n

func loaded_tiles() -> int:
	return loaded_chunk_count()

func tile_count() -> int:
	return _chunks.size()