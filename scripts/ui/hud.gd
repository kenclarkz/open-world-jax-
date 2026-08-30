class_name HUD
extends CanvasLayer

## On-screen UI: position, speed, time/weather, streaming stats, and a
## quick-controls hint. Purely informational.

var _pos_label: Label
var _info_label: Label
var _speed_label: Label
var _stream_label: Label

func _ready() -> void:
	var root := Control.new()
	root.name = "HUD"
	add_child(root)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 16)
	root.add_child(margin)

	var vbox := VBoxContainer.new()
	margin.add_child(vbox)

	_pos_label = Label.new()
	_pos_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	_pos_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_pos_label.add_theme_constant_override("outline_size", 6)
	vbox.add_child(_pos_label)

	_speed_label = Label.new()
	_speed_label.add_theme_color_override("font_color", Color(1, 1, 0.9, 0.9))
	_speed_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_speed_label.add_theme_constant_override("outline_size", 6)
	vbox.add_child(_speed_label)

	_stream_label = Label.new()
	_stream_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.7, 0.9))
	_stream_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_stream_label.add_theme_constant_override("outline_size", 6)
	vbox.add_child(_stream_label)

	_info_label = Label.new()
	_info_label.add_theme_color_override("font_color", Color(0.9, 0.9, 1, 0.85))
	_info_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_info_label.add_theme_constant_override("outline_size", 6)
	vbox.add_child(_info_label)

	var hint := Label.new()
	hint.text = "WASD move  |  Shift run  |  Space jump  |  E get in/out car  |  F5 save  |  F9 load  |  Esc cursor"
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	hint.add_theme_constant_override("outline_size", 6)
	hint.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	root.add_child(hint)
	hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hint.position.y -= 12

func _process(_delta: float) -> void:
	var p := get_tree().get_first_node_in_group("player")
	if p == null:
		return
	var pos: Vector3 = p.global_position
	var geo := GeoUtils.local_to_geo(Vector2(pos.x, pos.z))
	_pos_label.text = "Local %d,%d,%d  |  Lat %.5f Lon %.5f" % [pos.x, pos.y, pos.z, geo.x, geo.y]

	var speed := 0.0
	if p is Player:
		var pnode: Player = p
		if pnode.driving is RigidBody3D:
			var body := pnode.driving as RigidBody3D
			speed = body.linear_velocity.length()
		else:
			speed = 0.0
	elif p is RigidBody3D:
		speed = (p as RigidBody3D).linear_velocity.length()
	var kmh := speed * 3.6
	_speed_label.text = "Speed: %.0f km/h" % kmh

	var hour := int(Game.time_of_day)
	var mins := int((Game.time_of_day - hour) * 60)
	var weather_str := Game.current_weather
	_info_label.text = "Time %02d:%02d   Weather: %s   Tiles: %d" % [
		hour, mins, weather_str, TileStreamer.loaded_tiles()]

	var chunk := TileStreamer.current_chunk_key()
	var radius := TileStreamer.stream_radius
	var streams := "Streaming chunk (%d, %d)  |  %d m  |  R %d" % [chunk.x, chunk.y, int(TileStreamer.tile_size), radius]
	if TileStreamer.unload_radius != radius:
		streams += "/%d" % TileStreamer.unload_radius
	_stream_label.text = "%s\nLoaded %d  |  loading %d  |  unloading %d  |  tracked %d\nActive objects ~%d" % [
		streams,
		TileStreamer.loaded_chunk_count(),
		TileStreamer.loading_chunk_count(),
		TileStreamer.unloading_chunk_count(),
		TileStreamer.tracked_chunk_count(),
		TileStreamer.active_object_count()]
