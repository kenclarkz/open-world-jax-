class_name Pedestrian
extends CharacterBody3D

## Pedestrian NPC that wanders along sidewalks/paths near roads, or just
## strolls randomly near its spawn point if no road data is available.

@export var walk_speed := 2.5
@export var wander_range := 40.0

var _target: Vector3
var _origin: Vector3
var _mat: StandardMaterial3D

func _ready() -> void:
	_origin = global_position
	_build_body()
	_pick_target()

func _build_body() -> void:
	# Cylinder-ish capsule so it looks vaguely humanoid from a distance.
	var col := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.7
	col.shape = capsule
	col.position.y = 0.85
	add_child(col)

	var mesh := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.35
	cap.height = 1.7
	mesh.mesh = cap
	mesh.position.y = 0.85
	_mesh_mat(mesh)
	add_child(mesh)

func _mesh_mat(mesh: MeshInstance3D) -> void:
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(randf() * 0.6, randf() * 0.5, randf() * 0.6)
	mesh.material_override = _mat

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= 16.0 * delta
	var dir := _target - global_position
	dir.y = 0.0
	if dir.length() < 1.2:
		_pick_target()
		return
	dir = dir.normalized()
	velocity.x = dir.x * walk_speed
	velocity.z = dir.z * walk_speed
	move_and_slide()

	# Keep at terrain level loosely.
	var h := World.world_height_at(global_position)
	global_position.y = lerpf(global_position.y, h, 0.2)

func _pick_target() -> void:
	var angle := randf() * TAU
	var dist := randf() * wander_range
	_target = _origin + Vector3(cos(angle), 0, sin(angle)) * dist
