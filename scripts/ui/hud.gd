class_name HUD
extends CanvasLayer

## On-screen UI in a GTA-style layout: wanted stars (top-right), a money /
## stunt score, speedometer, coordinates, time/weather, and control hints.

var _pos_label: Label
var _info_label: Label
var _speed_label: Label
var _money_label: Label
var _wanted_label: Label
var _district_label: Label

## Tracks a GTA-style score/money that grows while driving fast or jumping.
var money := 0

func _ready() -> void:
	var root := Control.new()
	root.name = "HUD"
	add_child(root)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
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

	_info_label = Label.new()
	_info_label.add_theme_color_override("font_color", Color(0.9, 0.9, 1, 0.85))
	_info_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_info_label.add_theme_constant_override("outline_size", 6)
	vbox.add_child(_info_label)

	# Money / score (GTA signature) bottom-left.
	_money_label = Label.new()
	_money_label.text = "$0"
	_money_label.add_theme_color_override("font_color", Color(0.35, 1.0, 0.4, 0.95))
	_money_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_money_label.add_theme_constant_override("outline_size", 8)
	root.add_child(_money_label)
	_money_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_money_label.position += Vector2(16, -170)
	_money_label.add_theme_font_size_override("font_size", 26)

	# District / location name (GTA signature) top-center.
	_district_label = Label.new()
	_district_label.text = "DOWNTOWN JACKSONVILLE"
	_district_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	_district_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_district_label.add_theme_constant_override("outline_size", 8)
	_district_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_district_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_district_label.position = Vector2(-4000, 10)
	_district_label.custom_minimum_size = Vector2(8000, 40)
	root.add_child(_district_label)

	# Wanted stars (GTA signature) top-right, under the minimap.
	_wanted_label = Label.new()
	_wanted_label.text = "CLEAR"
	_wanted_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	_wanted_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_wanted_label.add_theme_constant_override("outline_size", 8)
	root.add_child(_wanted_label)
	_wanted_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_wanted_label.position -= Vector2(12, 0)
	_wanted_label.position.y += 320

	var hint := Label.new()
	hint.text = "WASD move  |  Shift run  |  Space jump  |  E get in/out car  |  F5 save  |  F9 load  |  Esc cursor"
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	hint.add_theme_constant_override("outline_size", 6)
	hint.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	root.add_child(hint)
	hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hint.position.y -= 12

func _process(delta: float) -> void:
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

	# GTA-style stunt score: driving fast or mid-jump earns money.
	if kmh > 60.0:
		money += int(delta * (kmh - 60.0))
	_money_label.text = "$%d" % money

	# Wanted level derived from sustained speeding (GTA police-chase feel).
	var wanted := 0
	if kmh > 90.0:
		wanted = 1
	if kmh > 120.0:
		wanted = 2
	if kmh > 150.0:
		wanted = 3
	if kmh > 180.0:
		wanted = 4
	_wanted_label.text = "WANTED %s" % (_stars(wanted) if wanted > 0 else "CLEAR")
	_wanted_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.95) if wanted == 0 else Color(1, 0.4, 0.3, 1))

	var hour := int(Game.time_of_day)
	var mins := int((Game.time_of_day - hour) * 60)
	var weather_str := Game.current_weather
	_info_label.text = "Time %02d:%02d   Weather: %s   Tiles: %d" % [
		hour, mins, weather_str, TileStreamer.loaded_tiles()]

func _stars(n: int) -> String:
	var s := ""
	for i in n:
		s += "\u2605 "
	return s
