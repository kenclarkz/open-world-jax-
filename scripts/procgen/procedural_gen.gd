extends Node

## Turns parsed GIS data (OsmData + terrain heightmap) into Godot meshes
## and collision: terrain, building footprints, water surfaces, roads and
## parks as ground polygons.

const TILE_SIZE := 500.0

# ---------------------------------------------------------------------------
# Terrain sampling
# ---------------------------------------------------------------------------

func terrain_height(terrain: Dictionary, pos: Vector3) -> float:
	if terrain.is_empty():
		return 0.0
	var size: Vector2i = terrain.get("size", Vector2i(1, 1))
	var heights: PackedFloat32Array = terrain.get("heights", PackedFloat32Array())
	var cellsize: float = terrain.get("cellsize", 30.0)
	if heights.is_empty() or size.x < 2:
		return 0.0
	var half_w := float(size.x) * cellsize * 0.5
	var half_h := float(size.y) * cellsize * 0.5
	var fx := (pos.x + half_w) / (float(size.x - 1) * cellsize)
	var fy := (pos.z + half_h) / (float(size.y - 1) * cellsize)
	fx = clampf(fx, 0.0, 1.0)
	fy = clampf(fy, 0.0, 1.0)
	var x0 := clampi(int(fx * float(size.x - 1)), 0, size.x - 1)
	var y0 := clampi(int(fy * float(size.y - 1)), 0, size.y - 1)
	return heights[y0 * size.x + x0]

# ---------------------------------------------------------------------------
# Mesh building helpers (correct SurfaceTool usage with explicit indices)
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Terrain mesh
# ---------------------------------------------------------------------------

func build_terrain_mesh(origin: Vector3, tile_size: float, terrain: Dictionary) -> ArrayMesh:
	var res := 8
	var step := tile_size / float(res)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	for gz in range(res + 1):
		for gx in range(res + 1):
			var pos := Vector3(origin.x + gx * step, 0.0, origin.z + gz * step)
			pos.y = terrain_height(terrain, pos)
			verts.append(pos)
			uvs.append(Vector2(pos.x / tile_size, pos.z / tile_size))
	var idx := PackedInt32Array()
	for gz in range(res):
		for gx in range(res):
			var a := gz * (res + 1) + gx
			var b := a + 1
			var c := a + (res + 1)
			var d := c + 1
			idx.append_array([a, c, b, b, c, d])
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = idx
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var st := SurfaceTool.new()
	st.create_from(mesh, 0)
	st.generate_normals()
	return st.commit()

# ---------------------------------------------------------------------------
# Terrain collision (reuse the terrain mesh shape)
# ---------------------------------------------------------------------------

## Build a StaticBody3D with collision generated from a heightmap for one tile.
func terrain_collision(origin: Vector3, tile_size: float, terrain: Dictionary) -> ArrayMesh:
	var res := 8
	var step := tile_size / float(res)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	var verts := PackedVector3Array()
	for gz in range(res + 1):
		for gx in range(res + 1):
			var pos := Vector3(origin.x + gx * step, 0.0, origin.z + gz * step)
			pos.y = terrain_height(terrain, pos)
			verts.append(pos)
	var idx := PackedInt32Array()
	for gz in range(res):
		for gx in range(res):
			var a := gz * (res + 1) + gx
			var b := a + 1
			var c := a + (res + 1)
			var d := c + 1
			idx.append_array([a, c, b, b, c, d])
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

# ---------------------------------------------------------------------------
# Building mesh + collision
# ---------------------------------------------------------------------------

func _poly_floor(poly: PackedVector2Array, terrain: Dictionary) -> float:
	if poly.is_empty():
		return 0.0
	var sum := Vector2.ZERO
	for p in poly:
		sum += p
	return terrain_height(terrain, Vector3(sum.x / poly.size(), 0, sum.y / poly.size()))

## Extrude a footprint into a mesh with top, bottom and walls.
func building_mesh(poly: PackedVector2Array, height: float, terrain: Dictionary) -> ArrayMesh:
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var floor_h := _poly_floor(poly, terrain)
	var col := _hash_color(int(poly[0].x * 1000.0) + int(poly[0].y), Color(0.62, 0.57, 0.50), 0.14)
	var _append := func(v: Vector3, c: Color):
		verts.append(v)
		colors.append(c)

	# Walls (two triangles per face) with a simple checker "window" banding
	# so buildings read as skyscrapers/downtown even at low resolution.
	var win_col := col.darkened(0.55)
	var win_h := 1.4   # window band height
	var win_gap := 1.0 # band separation
	var floors := maxi(1, int(height / (win_h + win_gap)))
	for i in range(poly.size()):
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		for f in range(floors):
			var y0 := floor_h + f * (win_h + win_gap)
			var y1 := y0 + win_h
			var v0 := Vector3(a.x, y0, a.y)
			var v1 := Vector3(b.x, y0, b.y)
			var v2 := Vector3(b.x, y1, b.y)
			var v3 := Vector3(a.x, y1, a.y)
			var use_win := (i + f) % 2 == 0
			var c := win_col if use_win else col
			_append.call(v0, c); _append.call(v2, c); _append.call(v1, c)
			_append.call(v0, c); _append.call(v3, c); _append.call(v2, c)
	# Roof.
	var tris := _triangulate(poly)
	var roof_col := col.lightened(0.15)
	for t in tris:
		_append.call(Vector3(t[0].x, height + floor_h, t[0].y), roof_col)
		_append.call(Vector3(t[1].x, height + floor_h, t[1].y), roof_col)
		_append.call(Vector3(t[2].x, height + floor_h, t[2].y), roof_col)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

## Build an approximate collision body from a footprint bounding box.
func building_collision(poly: PackedVector2Array, height: float, terrain: Dictionary) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 1
	var shape := CollisionShape3D.new()
	var bb := _poly_bounds(poly)
	var box := BoxShape3D.new()
	var cx: float = bb.position.x + bb.size.x * 0.5
	var cz: float = bb.position.y + bb.size.y * 0.5
	box.size = Vector3(bb.size.x + 0.4, height, bb.size.y + 0.4)
	var floor_h := _poly_floor(poly, terrain)
	shape.shape = box
	shape.position = Vector3(cx, height * 0.5 + floor_h, cz)
	body.add_child(shape)
	return body

func _poly_bounds(poly: PackedVector2Array) -> Rect2:
	var r := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		r = r.expand(p)
	return r

func _hash_color(seed_: int, base: Color, jitter: float) -> Color:
	var h := float(abs(hash(seed_)) % 1000) / 1000.0
	return Color(
		clampf(base.r + (h - 0.5) * jitter, 0.0, 1.0),
		clampf(base.g + (h - 0.5) * jitter, 0.0, 1.0),
		clampf(base.b + (h - 0.5) * jitter, 0.0, 1.0),
		base.a)

# ---------------------------------------------------------------------------
# Water / park / road ground meshes
# ---------------------------------------------------------------------------

func flat_poly_mesh(poly: PackedVector2Array, terrain: Dictionary, col: Color, lift: float) -> ArrayMesh:
	if poly.size() < 3:
		return null
	var floor_h := _poly_floor(poly, terrain) + lift
	var tris := _triangulate(poly)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	var verts := PackedVector3Array()
	for t in tris:
		verts.append(Vector3(t[0].x, floor_h, t[0].y))
		verts.append(Vector3(t[1].x, floor_h, t[1].y))
		verts.append(Vector3(t[2].x, floor_h, t[2].y))
	var colors := PackedColorArray()
	for i in range(verts.size()):
		colors.append(col)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

## Extrude a road centerline into a flat, slightly-raised ribbon.
func road_mesh(points: PackedVector3Array, width: float, col: Color) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	var verts := PackedVector3Array()
	var lift := 0.05
	for i in range(points.size() - 1):
		var a := points[i]
		var b := points[i + 1]
		var dir := Vector3(b.x - a.x, 0, b.z - a.z)
		if dir.length() < 0.01:
			continue
		dir = dir.normalized()
		var perp := Vector3(-dir.z, 0, dir.x) * (width * 0.5)
		var v0 := Vector3(a.x + perp.x, lift, a.z + perp.z)
		var v1 := Vector3(a.x - perp.x, lift, a.z - perp.z)
		var v2 := Vector3(b.x - perp.x, lift, b.z - perp.z)
		var v3 := Vector3(b.x + perp.x, lift, b.z + perp.z)
		verts.append(v0); verts.append(v1); verts.append(v2)
		verts.append(v0); verts.append(v2); verts.append(v3)
	var colors := PackedColorArray()
	for i in range(verts.size()):
		colors.append(col)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

# ---------------------------------------------------------------------------
# Polygon triangulation (ear clipping)
# ---------------------------------------------------------------------------

func _triangulate(poly: PackedVector2Array) -> Array:
	var result: Array = []
	if poly.size() < 3:
		return result
	var pts := PackedVector2Array(poly)
	if _signed_area(pts) < 0.0:
		var inv := PackedVector2Array()
		for i in range(pts.size() - 1, -1, -1):
			inv.append(pts[i])
		pts = inv
	var i := 0
	var guard := 0
	while pts.size() > 3 and guard < 10000:
		guard += 1
		var pi := (i + pts.size() - 1) % pts.size()
		var ni := (i + 1) % pts.size()
		var a := pts[pi]
		var b := pts[i]
		var c := pts[ni]
		if _is_ear(pts, pi, i, ni):
			result.append([a, b, c])
			pts.remove_at(i)
			i = 0
		else:
			i = (i + 1) % pts.size()
			if i == 0:
				break
	if pts.size() == 3:
		result.append([pts[0], pts[1], pts[2]])
	return result

func _signed_area(pts: PackedVector2Array) -> float:
	var a := 0.0
	for i in range(pts.size()):
		var p1 := pts[i]
		var p2 := pts[(i + 1) % pts.size()]
		a += p1.x * p2.y - p2.x * p1.y
	return a * 0.5

func _is_ear(pts: PackedVector2Array, pi: int, i: int, ni: int) -> bool:
	var a := pts[pi]
	var b := pts[i]
	var c := pts[ni]
	var cross := (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
	if cross <= 0.0:
		return false
	for k in range(pts.size()):
		if k == pi or k == i or k == ni:
			continue
		if _point_in_tri(pts[k], a, b, c):
			return false
	return true

func _point_in_tri(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var d1 := _cross2(b - a, p - a)
	var d2 := _cross2(c - b, p - b)
	var d3 := _cross2(a - c, p - c)
	var has_neg := d1 < 0.0 or d2 < 0.0 or d3 < 0.0
	var has_pos := d1 > 0.0 or d2 > 0.0 or d3 > 0.0
	return not (has_neg and has_pos)

func _cross2(a: Vector2, b: Vector2) -> float:
	return a.x * b.y - a.y * b.x
