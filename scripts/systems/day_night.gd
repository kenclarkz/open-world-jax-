extends Node3D

## Day/night cycle.
## Rotates the directional sun/moon light over 24 game-hours per N real
## minutes, adjusting sky and light color/intensity, and drives the World
## time-of-day value used for saves and weather.
##
## Sun direction (directional light) and sky (ProceduralSkyMaterial) are
## configured on the exported node paths, or a minimal sky is generated.

@export var directional_light_path: NodePath
@export var full_day_minutes := 10.0  # real minutes per full game day
@export var start_hour := 10.0        # game-hour at startup

var _hour: float = 10.0
var _sun: DirectionalLight3D = null
var _sky: Sky = null
var _world_env: Environment = null

func _ready() -> void:
	_hour = start_hour
	Game.time_of_day = start_hour
	if directional_light_path != NodePath():
		_sun = get_node_or_null(directional_light_path) as DirectionalLight3D
	_setup_sky()

func _setup_sky() -> void:
	# Find the world environment from the current scene.
	var env_node := get_tree().current_scene.get_node_or_null("WorldEnvironment")
	if env_node == null:
		return
	_world_env = env_node.get("environment") as Environment
	if _world_env == null:
		return
	# Some rendering backends (headless/dummy) expose a reduced property
	# list on Environment; guard so this never hard-crashes.
	_sky = _world_env.get("background_sky")
	if _sky == null:
		var new_sky := Sky.new()
		_world_env.set("background_mode", Environment.BG_SKY)
		_world_env.set("background_sky", new_sky)
		_sky = _world_env.get("background_sky")

func _process(delta: float) -> void:
	var hours_per_sec := 24.0 / (full_day_minutes * 60.0)
	_hour += delta * hours_per_sec
	if _hour >= 24.0:
		_hour -= 24.0
	Game.time_of_day = _hour
	_update_sun_and_sky()

func _update_sun_and_sky() -> void:
	if _sun == null:
		return
	# Sun elevation angle based on hour (6 = sunrise, 18 = sunset).
	var norm := _hour / 24.0
	var sun_angle := TAU * (norm - 0.25)  # 0 at 6:00 (sunrise east), pi at 18:00
	var elevation := sin(sun_angle)
	var azimuth := cos(sun_angle)
	_sun.rotation_degrees.x = -rad_to_deg(atan2(-elevation, -azimuth))
	_sun.rotation_degrees.y = rad_to_deg(azimuth)

	# Intensity + color with time of day.
	var day := clampf(elevation, 0.0, 1.0)
	_sun.light_energy = lerpf(0.25, 1.2, day)
	_sun.light_color = Color(1.0, (0.7 + day * 0.3), (0.55 + day * 0.45))

	if _sky != null:
		var mat: ProceduralSkyMaterial = _sky.get("sky_material")
		if mat != null and "sky_top_color" in mat:
			mat.set("sky_top_color", Color(0.05 + day * 0.25, 0.05 + day * 0.4, 0.2 + day * 0.6))
			mat.set("sky_horizon_color", Color(0.25 + day * 0.3, 0.3 + day * 0.3, 0.4 + day * 0.3))
			mat.set("sky_energy", lerpf(0.5, 1.4, day))
	if _world_env != null:
		if "ambient_light_energy" in _world_env:
			_world_env.set("ambient_light_energy", lerpf(0.15, 1.0, day))
			_world_env.set("ambient_light_color", Color(0.4 + day * 0.6, 0.4 + day * 0.6, 0.5 + day * 0.6))

func current_hour() -> float:
	return _hour
