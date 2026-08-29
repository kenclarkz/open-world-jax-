class_name WorldGenerator

## Static helper that builds one streamed tile (Node3D) from the global
## OsmData + terrain heightmap. Each tile contains:
##   - Terrain mesh (with collision)
##   - Roads (ribbons)
##   - Building footprints (mesh + collision)
##   - Parks (green ground patches)
##   - Water bodies (blue polygons)
## Uses bounding-box culling so only geometry intersecting the tile is built.

const TILE_SIZE := 500.0

const ROAD_COLOR = Color(0.45, 0.47, 0.5)
const PARK_COLOR = Color(0.30, 0.55, 0.25)
const WATER_COLOR = Color(0.20, 0.45, 0.55, 0.9)

## Build a tile rooted at `origin` covering origin..origin+(size,size).
static func build_tile(origin: Vector3, size: float) -> Node3D:
	var tile := Node3D.new()
	var data := World.osm_data

	# 1. Terrain mesh + collision.
	var terrain_mesh := ProceduralGen.build_terrain_mesh(origin, size, World.terrain)
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	ground.mesh = terrain_mesh
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = Color(0.38, 0.50, 0.28)
	ground_mat.roughness = 1.0
	ground.material_override = ground_mat
	tile.add_child(ground)

	var col_mesh := ProceduralGen.terrain_collision(origin, size, World.terrain)
	var col_body := StaticBody3D.new()
	col_body.name = "GroundCollision"
	col_body.collision_layer = 1
	col_body.collision_mask = 1
	var col_shape := CollisionShape3D.new()
	var trimesh := col_mesh.create_trimesh_shape()
	col_shape.shape = trimesh
	col_body.add_child(col_shape)
	tile.add_child(col_body)

	# 2. Roads (ribbons), but only the segments that cross this tile.
	var road_mat := StandardMaterial3D.new()
	road_mat.albedo_color = ROAD_COLOR
	road_mat.roughness = 0.9

	if data != null:
		# Parks
		var park_mat := StandardMaterial3D.new()
		park_mat.albedo_color = PARK_COLOR
		for park in data.parks:
			if _poly_in_tile(park.polygon, origin, size):
				var m := ProceduralGen.flat_poly_mesh(park.polygon, World.terrain, PARK_COLOR, 0.015)
				if m != null:
					var mi := MeshInstance3D.new()
					mi.name = "Park_%d" % park.id
					mi.mesh = m
					mi.material_override = park_mat
					tile.add_child(mi)

		# Water
		var water_mat := StandardMaterial3D.new()
		water_mat.albedo_color = WATER_COLOR
		water_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		for w in data.water_bodies:
			if _poly_in_tile(w.polygon, origin, size):
				var m := ProceduralGen.flat_poly_mesh(w.polygon, World.terrain, WATER_COLOR, 0.1)
				if m != null:
					var mi := MeshInstance3D.new()
					mi.name = "Water_%d" % w.id
					mi.mesh = m
					mi.material_override = water_mat
					tile.add_child(mi)

		# Roads
		for road in data.roads:
			_add_road(tile, road, origin, size, road_mat)

		# Buildings
		var building_mat := StandardMaterial3D.new()
		building_mat.roughness = 0.8
		for b in data.buildings:
			if _poly_in_tile(b.polygon, origin, size):
				var m := ProceduralGen.building_mesh(b.polygon, b.height, World.terrain)
				if m != null:
					var mi := MeshInstance3D.new()
					mi.name = "Building_%d" % b.id
					mi.mesh = m
					var bmat := StandardMaterial3D.new()
					bmat.albedo_color = _building_color(b.id)
					bmat.roughness = 0.85
					mi.material_override = bmat
					tile.add_child(mi)
					var col_body2 := ProceduralGen.building_collision(b.polygon, b.height, World.terrain)
					tile.add_child(col_body2)

	return tile

static func _building_color(id: int) -> Color:
	var palette := [
		Color(0.62, 0.58, 0.52), Color(0.55, 0.50, 0.47),
		Color(0.68, 0.62, 0.55), Color(0.58, 0.51, 0.48),
		Color(0.50, 0.52, 0.56), Color(0.60, 0.55, 0.60),
	]
	return palette[abs(id) % palette.size()]

static func _add_road(tile: Node3D, road, origin: Vector3, size: float, mat: Material) -> void:
	# Only include road segments overlapping this tile's bounds.
	var pts: PackedVector3Array = road.points
	if pts.size() < 2:
		return
	# Build a clipped sub-polyline of points inside/box of this tile.
	var box := Rect2(origin.x, origin.z, size, size)
	var in_tile := false
	for p in pts:
		if box.has_point(Vector2(p.x, p.z)):
			in_tile = true
			break
	if not in_tile:
		# Even if no point is inside, a segment could cross the tile;
		# a cheap conservative check is whether any segment bbox overlaps.
		for i in range(pts.size() - 1):
			if _segment_overlaps_box(pts[i], pts[i + 1], box):
				in_tile = true
				break
	if not in_tile:
		return

	var m := ProceduralGen.road_mesh(pts, road.width, ROAD_COLOR)
	if m != null:
		var mi := MeshInstance3D.new()
		mi.name = "Road_%d" % road.id
		mi.mesh = m
		mi.material_override = mat
		tile.add_child(mi)

static func _segment_overlaps_box(a: Vector3, b: Vector3, box: Rect2) -> bool:
	var min_x: float = minf(a.x, b.x)
	var max_x: float = maxf(a.x, b.x)
	var min_z: float = minf(a.z, b.z)
	var max_z: float = maxf(a.z, b.z)
	return max_x >= box.position.x and min_x <= box.position.x + box.size.x \
		and max_z >= box.position.y and min_z <= box.position.y + box.size.y

static func _poly_in_tile(poly: PackedVector2Array, origin: Vector3, size: float) -> bool:
	if poly.size() < 3:
		return false
	var box := Rect2(origin.x, origin.z, size, size)
	for p in poly:
		if box.has_point(Vector2(p.x, p.y)):
			return true
	return false
