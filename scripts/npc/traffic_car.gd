class_name TrafficCar
extends Node3D

## Traffic vehicle that follows the road network.
## Simple approach: cars pick a random road (from the loaded OSM data),
## traverse its center-line points, then pick a new random road near the
## end. Uses a lightweight kinematic model riding on the terrain.

@export var speed := 8.0
@export var body : Node3D

var _path: PackedVector3Array = PackedVector3Array()
var _path_index := 0
var _cached_paths: Array = []

func _ready() -> void:
	_build_basic_body()
	call_deferred("_pick_new_road")

func _build_basic_body() -> void:
	if body != null:
		return
	body = MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(2.2, 1.2, 4.4)
	body.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(randf() * 0.6, randf() * 0.6, randf() * 0.6 + 0.2)
	body.material_override = mat
	body.position.y = 0.7
	add_child(body)

	# Simple collision so player can bump into it.
	var col := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.2, 1.4, 4.4)
	shape.shape = box
	shape.position.y = 0.7
	col.add_child(shape)
	add_child(col)

func _physics_process(delta: float) -> void:
	if _path.size() < 2:
		call_deferred("_pick_new_road")
		return
	var target: Vector3 = _path[_path_index]
	var h := World.world_height_at(target)
	target.y = h + 0.75
	var to := target - global_position
	to.y = 0.0
	if to.length() < 1.0:
		_path_index += 1
		if _path_index >= _path.size():
			call_deferred("_pick_new_road")
			return
		return
	to = to.normalized()
	var desired := to * speed
	global_position += desired * delta
	# Face direction of travel.
	if to.length() > 0.1:
		global_rotation.y = -atan2(to.x, to.z)

func _pick_new_road() -> void:
	if World.osm_data == null or World.osm_data.roads.is_empty():
		_reset_to_origin()
		return
	# Pick a road near the car.
	var best := PackedVector3Array()
	var best_dist: float = INF
	for road in World.osm_data.roads:
		if road.points.size() < 2:
			continue
		var first: Vector3 = road.points[0]
		var d: float = first.distance_to(global_position)
		if d < best_dist:
			best_dist = d
			best = road.points
	if best.is_empty():
		_reset_to_origin()
		return
	_path = best
	_path_index = 0
	# If the road starts far away, begin at the closest segment.
	var min_d := INF
	var start_i := 0
	for i in range(_path.size()):
		var d := _path[i].distance_to(global_position)
		if d < min_d:
			min_d = d
			start_i = i
	_path_index = max(0, start_i)

func _reset_to_origin() -> void:
	_path = PackedVector3Array([global_position, global_position + Vector3(0, 0, -20)])
	_path_index = 0
