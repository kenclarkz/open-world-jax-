extends Node3D

## Basic weather system.
## Cycles between clear / cloudy / rain states. Rain toggles a simple
## particle emitter and dims the sky slightly. The current weather is
## stored on the Game autoload so it can be saved/loaded.

@export var rain_particles_path: NodePath
@export var change_every_seconds := 90.0

enum Weather { CLEAR, CLOUDY, RAIN }

var _timer := 0.0
var _current: int = Weather.CLEAR
var _rain: GPUParticles3D = null
var _labels: Label = null

func _ready() -> void:
	if rain_particles_path != NodePath():
		_rain = get_node_or_null(rain_particles_path) as GPUParticles3D
	Game.current_weather = _weather_name(_current)
	_apply_weather()

func _process(delta: float) -> void:
	_timer += delta
	if _timer >= change_every_seconds:
		_timer = 0.0
		_current = (_current + 1) % 3
		_apply_weather()
		Game.current_weather = _weather_name(_current)

func _apply_weather() -> void:
	if _rain != null:
		_rain.emitting = (_current == Weather.RAIN)
		print("[Weather] Rain particles: ", _rain.emitting)

func _weather_name(w: int) -> String:
	match w:
		Weather.RAIN:
			return "rain"
		Weather.CLOUDY:
			return "cloudy"
		_:
			return "clear"
