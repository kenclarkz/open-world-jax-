class_name Minimap
extends Control

## Minimap overlaid on the HUD.
## The road network is rendered once into a cached Texture (ImageTexture)
## sized to the city bounds. During play, a camera/player icon is drawn as
## a child Position2D that moves relative to the texture, and the map
## scrolls/positions to follow the player.
##
## Because the full city texture can be large, we render at a fixed
## resolution and sample a window around the player.

@export var map_texture_path: String = "user://jax_data/minimap.png"
@export var player_icon_path: NodePath

var _tex_size := 1024
var _world_min := Vector2.ZERO
var _world_max := Vector2(1000, 1000)
var _road_tex: Texture2D = null
var _roads_dirty := true

var _icon: TextureRect

func _ready() -> void:
	# Background panel.
	var panel := ColorRect.new()
	panel.color = Color(0.1, 0.12, 0.15, 0.6)
	add_child(panel)
	# The road texture.
	var tex_rect := TextureRect.new()
	tex_rect.name = "RoadTexture"
	tex_rect.texture = _road_tex
	add_child(tex_rect)
	# Player icon.
	_icon = TextureRect.new()
	_icon.name = "PlayerIcon"
	_icon.modulate = Color(1, 0.2, 0.2, 1.0)
	var icon_tex := GradientTexture2D.new()
	icon_tex.fill_from = Vector2(0.5, 0.5)
	icon_tex.fill_to = Vector2(0.5, 0.0)
	_icon.texture = icon_tex
	_icon.custom_minimum_size = Vector2(12, 12)
	_icon.position = Vector2(200, 200)
	add_child(_icon)

func _process(_delta: float) -> void:
	if _roads_dirty and World.osm_data != null:
		_generate_road_texture()
		_roads_dirty = false

	# Update player icon position.
	var p := get_tree().get_first_node_in_group("player")
	if p != null and _road_tex != null:
		var pos := _world_to_map(p.global_position)
		_icon.position = pos - _icon.size * 0.5

func _world_to_map(world: Vector3) -> Vector2:
	var span := _world_max - _world_min
	var nx := (world.x - _world_min.x) / span.x
	var nz := (world.z - _world_min.y) / span.y
	return Vector2(nx * _tex_size, nz * _tex_size)

## Render roads into an image and save as a texture (and cache PNG).
func _generate_road_texture() -> void:
	if World.osm_data == null:
		return
	_world_min = World.osm_data.bounds_min
	_world_max = World.osm_data.bounds_max
	var span := _world_max - _world_min
	if span.x <= 0 or span.y <= 0:
		return

	var img := Image.create(_tex_size, _tex_size, false, Image.FORMAT_RGB8)
	img.fill(Color(0.12, 0.16, 0.2))
	var data := World.osm_data
	# Draw roads.
	for road in data.roads:
		var pts := PackedVector2Array()
		for p in road.points:
			var x: float = (p.x - _world_min.x) / span.x * _tex_size
			var y: float = (p.z - _world_min.y) / span.y * _tex_size
			pts.append(Vector2(x, y))
		if pts.size() >= 2:
			_draw_road(img, pts, 3)
	# Draw water in blue.
	for w in data.water_bodies:
		_draw_poly(img, w.polygon, Color(0.2, 0.45, 0.6))
	# Draw parks green.
	for park in data.parks:
		_draw_poly(img, park.polygon, Color(0.25, 0.5, 0.25))

	# Save cached PNG.
	var fpath := ProjectSettings.globalize_path(map_texture_path)
	img.save_png(fpath)
	_road_tex = ImageTexture.create_from_image(img)
	var tex: TextureRect = get_node("RoadTexture")
	tex.texture = _road_tex
	tex.custom_minimum_size = Vector2(_tex_size, _tex_size)
	print("[Minimap] Generated road minimap (%dx%d)" % [_tex_size, _tex_size])

func _draw_road(img: Image, pts: PackedVector2Array, thickness: int) -> void:
	var col := Color(0.85, 0.85, 0.88)
	for i in range(pts.size() - 1):
		_draw_line(img, pts[i], pts[i + 1], col, thickness)

func _draw_line(img: Image, a: Vector2, b: Vector2, col: Color, t: int) -> void:
	# Simple DDA line rasterization.
	var steps := int(max(1, a.distance_to(b)))
	for s in range(steps + 1):
		var f := float(s) / float(steps)
		var p := a.lerp(b, f)
		_set_pixel_radius(img, p, col, t)

func _draw_poly(img: Image, poly: PackedVector2Array, col: Color) -> void:
	# Rasterize a filled polygon via scanline on the small texture.
	if poly.size() < 3:
		return
	var span := _world_max - _world_min
	var pts := PackedVector2Array()
	for p in poly:
		pts.append(Vector2((p.x - _world_min.x) / span.x * _tex_size, (p.y - _world_min.y) / span.y * _tex_size))
	_for_each_pixel_in_poly(pts, func(pos: Vector2):
		img.set_pixel(int(pos.x), int(pos.y), col))

func _for_each_pixel_in_poly(pts: PackedVector2Array, cb: Callable) -> void:
	var min_x := 0
	var max_x := _tex_size - 1
	var min_y := 0
	var max_y := _tex_size - 1
	for p in pts:
		min_x = max(0, min(min_x, int(floor(p.x))))
		max_x = min(_tex_size - 1, max(max_x, int(ceil(p.x))))
		min_y = max(0, min(min_y, int(floor(p.y))))
		max_y = min(_tex_size - 1, max(max_y, int(ceil(p.y))))
	for y in range(min_y, max_y + 1):
		# Collect intersections of horizontal scanline with polygon edges.
		var xs: Array = []
		for i in range(pts.size()):
			var p1 := pts[i]
			var p2 := pts[(i + 1) % pts.size()]
			if (p1.y <= y and p2.y > y) or (p2.y <= y and p1.y > y):
				var t_x := (y - p1.y) / (p2.y - p1.y)
				xs.append(p1.x + t_x * (p2.x - p1.x))
		xs.sort()
		for k in range(0, xs.size() - 1, 2):
			var x0 := int(round(xs[k]))
			var x1 := int(round(xs[k + 1]))
			for x in range(max(0, x0), min(_tex_size, x1 + 1)):
				cb.call(Vector2(x, y))

func _set_pixel_radius(img: Image, p: Vector2, col: Color, radius: int) -> void:
	var cx := int(p.x)
	var cy := int(p.y)
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dx * dx + dy * dy <= radius * radius:
				var x := cx + dx
				var y := cy + dy
				if x >= 0 and x < _tex_size and y >= 0 and y < _tex_size:
					img.set_pixel(x, y, col)
