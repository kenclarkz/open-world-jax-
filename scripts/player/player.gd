class_name Player
extends CharacterBody3D

## Third-person player controller.
## - WASD / left stick to move (relative to camera)
## - Shift to run
## - Space to jump
## - E to enter/exit the nearest vehicle
## Uses a SpringArm camera rig for third-person view.

@export var walk_speed := 4.5
@export var run_speed := 8.5
@export var jump_velocity := 6.5
@export var acceleration := 10.0
@export var gravity := 18.0
@export var mouse_sensitivity := 0.002

var _input_dir := Vector2.ZERO
var _target_velocity := Vector3.ZERO
var _is_on_ground_cache := false

@onready var camera_rig: Node3D = $CameraRig
@onready var spring_arm: SpringArm3D = $CameraRig/SpringArm3D
@onready var model: Node3D = $Model
@onready var camera: Camera3D = $CameraRig/SpringArm3D/Camera3D

## The Vehicle the player is currently driving (null while on foot).
var driving: Vehicle = null

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if Game.has_save():
		var save := Game.load_game()
		global_position = Game.player_spawn
		Game.current_weather = save.get("weather", "clear")
		camera_rig.global_position = global_position

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		camera_rig.rotate_x(-event.relative.y * mouse_sensitivity)
		camera_rig.rotation.x = clampf(camera_rig.rotation.x, -1.3, 1.3)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
			KEY_F5:
				Game.save_game(global_position)
				print("[Player] Game saved at ", global_position)
			KEY_F9:
				_load_checkpoint()
			KEY_E:
				if driving == null:
					_try_enter_vehicle()
				else:
					var v: Vehicle = driving
					v._exit()
			KEY_R:
				_rotate_camera_around()

## Attempt to enter the nearest vehicle within a short radius.
func _try_enter_vehicle() -> void:
	# Ask the world/spawn manager for vehicles near the player.
	var best: Vehicle = null
	var best_dist := 4.5
	for car in get_tree().get_nodes_in_group("car"):
		if not (car is Vehicle):
			continue
		var d := global_position.distance_to(car.global_position)
		if d < best_dist:
			best_dist = d
			best = car as Vehicle
	if best != null:
		best._enter(self)

func _rotate_camera_around() -> void:
	# Reorient the camera rig yaw to match the character body.
	camera_rig.rotation.y = rotation.y

func _physics_process(delta: float) -> void:
	if driving != null:
		# While driving, the vehicle handles movement; keep the camera following.
		_process_camera_follow()
		return

	_input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var is_running := Input.is_action_pressed("run")
	var speed := run_speed if is_running else walk_speed

	# Camera-relative movement.
	var forward := -camera_rig.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right := camera_rig.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()
	var move_dir := (right * _input_dir.x + forward * _input_dir.y).normalized()

	# Apply gravity.
	if not is_on_floor():
		velocity.y -= gravity * delta
	_is_on_ground_cache = is_on_floor()

	# Horizontal movement.
	var target_h := move_dir * speed
	var horiz := velocity
	horiz.y = 0.0
	horiz = horiz.lerp(target_h, acceleration * delta)
	velocity.x = horiz.x
	velocity.z = horiz.z

	# Jump.
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	# Face movement direction.
	if move_dir.length() > 0.1:
		var rot := move_dir.signed_angle_to(Vector3.FORWARD, Vector3.UP)
		model.rotation.y = -rot

	move_and_slide()

func _process_camera_follow() -> void:
	camera_rig.global_position = global_position
	# When driving, face the camera in the vehicle's travel direction.
	if driving != null:
		var forward := -driving.global_transform.basis.z
		forward.y = 0.0
		forward = forward.normalized()
		if forward.length() > 0.01:
			camera_rig.rotation.y = atan2(-forward.x, -forward.z)

func _exit_vehicle() -> void:
	if driving == null:
		return
	var seat: Node3D = driving.get_node_or_null("Seat")
	if seat != null:
		global_position = seat.global_position
	driving = null

## Called by the vehicle system when the player enters it.
func enter_vehicle(vehicle: Vehicle) -> void:
	driving = vehicle
	visible = false

func _load_checkpoint() -> void:
	if Game.has_save():
		Game.load_game()
		global_position = Game.player_spawn
		print("[Player] Teleported to last save: ", Game.player_spawn)
