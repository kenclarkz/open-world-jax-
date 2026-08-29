class_name Vehicle
extends RigidBody3D

## Arcade-style drivable car built on RigidBody3D.
## - WASD / arrow keys to accelerate/steer/brake
## - Space / E to exit when driving
## - The player "enters" by becoming a child the vehicle stays positioned
##   at the Seat node, and the player camera follows via Player logic.
##
## The model is a simple BoxMesh car built procedurally so no external
## assets are required.

@export var engine_power := 1600.0
@export var max_steer := 0.6
@export var brake_power := 1200.0
@export var linear_damping_val := 2.0
@export var max_speed := 30.0

var player: Node = null
var _forward_vel := 0.0
var _steer := 0.0

@onready var model: Node3D = $Model
@onready var seat: Node3D = $Seat

func _ready() -> void:
	gravity_scale = 1.0
	linear_damp = linear_damping_val
	angular_damp = 1.2
	# Add basic collision shape if none exists (built in scene).

func _physics_process(delta: float) -> void:
	if player == null:
		return  # not being driven

	var throttle := Input.get_axis("vehicle_back", "vehicle_forward")
	var steer_input := Input.get_axis("vehicle_right", "vehicle_left")
	var brake := Input.is_action_pressed("vehicle_brake")

	_steer = lerpf(_steer, steer_input * max_steer, delta * 6.0)

	# Compute forward direction of the car.
	var forward := -global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()

	# Current forward speed.
	_forward_vel = linear_velocity.dot(forward)

	# Apply steering as angular velocity around local Y.
	angular_velocity.y = _steer * clampf(_forward_vel / 6.0, -1.0, 1.0) * 3.0

	if brake:
		apply_central_force(-forward * brake_power * delta)
	else:
		# Throttle power proportional to how aligned the motion is.
		apply_central_force(forward * engine_power * throttle * delta)

	# Cap speed.
	if _forward_vel > max_speed:
		apply_central_impulse(-forward * (_forward_vel - max_speed) * 0.1)
	elif _forward_vel < -max_speed * 0.6:
		apply_central_impulse(forward * (-_forward_vel - max_speed * 0.6) * 0.1)

	# Exit.
	if Input.is_action_just_pressed("interact"):
		_exit()

	# Keep the player attached to the seat and update camera.
	if player != null:
		player.global_position = seat.global_position
		var p: Player = player
		p.camera_rig.global_position = player.global_position

func _enter(p: Player) -> void:
	player = p
	p.driving = self
	p.visible = false
	p.collision_layer = 0
	p.collision_mask = 0
	p.global_position = seat.global_position
	print("[Vehicle] Entered vehicle")

func _exit() -> void:
	if player == null:
		return
	var p: Player = player
	p.driving = null
	p.visible = true
	p.collision_layer = 1
	p.collision_mask = 1
	# Place player beside the car.
	var dir := global_transform.basis.x
	player = null
	p.global_position = global_position + dir * 2.5
	p.velocity = Vector3.ZERO
	print("[Vehicle] Exited vehicle")
