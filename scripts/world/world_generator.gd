class_name WorldGenerator

## Builds one streamed chunk (Node3D) from the global OsmData + terrain.
## Works in two phases so streaming never blocks the main thread:
##   1. build_chunk_data(key)     — pure geometry as plain arrays; safe to
##                                  call from a worker thread.
##   2. instantiate_chunk(data)   — creates meshes/materials/collision on the
##                                  main thread (only done for loaded chunks).
## Roads are clipped to the chunk rect so neighbouring chunks share the exact
## same boundary vertices (roads stay connected). Area features (parks, water,
## buildings) and POIs are owned by the single chunk that contains their
## centre/position, so objects crossing chunk borders are never duplicated.

const ROAD_COLOR := Color(0.45, 0.47, 0.5)
const PARK_COLOR := Color(0.30, 0.55, 0.25)
const WATER_COLOR := Color(0.20, 0.45, 0.55, 0.9)

# ---------------------------------------------------------------------------
# Phase 1: geometry data (worker thread safe — no nodes, no RenderingServer)
# ---------------------------------------------------------------------------

static func build_chunk_data(key: Vector2i) -> Dictionary:
	var size: float = World.tile_size
	var origin := World.chunk_origin(key)
	var data := {
		"key": key,
		"origin": origin,
		"size": size,
		"terrain": _build_terrain_data(origin, size),
		"roads": [],
		"parks": [],
		"water": [],
		"buildings": [],
		"pois": [],
		"object_count": 2,  # ground mesh + ground collision body
	}

	var contents := World.chunk_contents(key)
	var box := Rect2(origin.x, origin.z, size, size)

	for road in contents["roads"]:
		_append_road_chains(data, road, box)

	for park in contents["parks"]:
		var verts := _flat_poly_verts(park.polygon, 0.015)
		if not verts.is_empty():
			data["parks"].append({"verts": verts, "id": park.id})
			data["object_count"] += 1

	for w in contents["water"]:
		var verts := _flat_poly_verts(w.polygon, 0.1)
		if not verts.is_empty():
			data["water"].append({"verts": verts, "id": w.id})
			data["object_count"] += 1

	for b in contents["buildings"]:
		var bd := _building_data(b.polygon, b.height)
		bd["id"] = b.id
		data["buildings"].append(bd)
		data["object_count"] += 2  # mesh + collision body

	for poi in contents["pois"]:
		data["pois"].append({"id": poi.id, "kind": poi.kind, "name": poi.name, "position": poi.position})
		data["object_count"] += 1

	return data

static func _build_terrain_data(origin: Vector3, size: float) -> Dictionary:
	var res := 8
	var step := size / float(res)
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	for gz in range(res + 1):
		for gx in range(res + 1):
			var pos := Vector3(origin.x + gx * step, 0.0, origin.z + gz * step)
			pos.y = ProceduralGen.terrain_height(World.terrain, pos)
			verts.append(pos)
			uvs.append(Vector2(pos.x / size, pos.z / size))
	var idx := PackedInt32Array()
	for gz in range(res):
		for gx in range(res):
			var a := gz * (res + 1) + gx
			var b := a + 1
			var c := a + (res + 1)
			var d := c + 1
			idx.append_array([a, c, b, b, c, d])
	return {"verts": verts, "uvs": uvs, "indices": idx}

# --- roads (clipped to the chunk so boundaries connect, never duplicated) ---

static func _append_road_chains(data: Dictionary, road, box: Rect2) -> void:
	var chains := _clip_road_to_box(road.points, box)
	var vert_count := 0
	for chain in chains:
		var verts := _ribbon_verts(chain, road.width)
		if verts.is_empty():
			continue
		data["roads"].append({"verts": verts, "id": road.id})
		vert_count += verts.size()
	if vert_count > 0:
		data["object_count"] += 1

## Split a road polyline into the sub-chains that lie inside a chunk rect.
## Each chain is a continuous run of clipped segments; neighbouring chunks
## compute the exact same boundary points, so ribbons connect seamlessly.
static func _clip_road_to_box(points: PackedVector3Array, box: Rect2) -> Array:
	var chains: Array = []
	if points.size() < 2:
		return chains

	var current := PackedVector3Array()
	for i in range(points.size() - 1):
		var clipped := _segment_clip(points[i], points[i + 1], box)
		if clipped.size() < 2:
			# Fully outside (or just touching): close the current chain.
			if current.size() >= 2:
				chains.append(current)
			current = PackedVector3Array()
			continue
		var c0: Vector3 = clipped[0]
		var c1: Vector3 = clipped[1]
		if current.is_empty():
			current.append(c0)
			current.append(c1)
		else:
			var last: Vector3 = current[current.size() - 1]
			if last.distance_to(c0) < 0.01:
				current.append(c1)
			else:
				# Discontinuity (road left and re-entered): start a new chain.
				chains.append(current)
				current = PackedVector3Array([c0, c1])

	if current.size() >= 2:
		chains.append(current)

	var out: Array = []
	for c in chains:
		if c.size() >= 2:
			out.append(c)
	return out

static func _point_in_box(p: Vector3, box: Rect2) -> bool:
	return p.x >= box.position.x and p.x <= box.position.x + box.size.x \
		and p.z >= box.position.y and p.z <= box.position.y + box.size.y

## The road-segment portion clipped into the chunk rect (0 or 2 points).
static func _segment_clip(a: Vector3, b: Vector3, box: Rect2) -> PackedVector3Array:
	return ProceduralGen.clip_seg_to_rect(a, b, box)

## Ribbon (road surface) triangle vertices for a clipped chain.
static func _ribbon_verts(chain: PackedVector3Array, width: float) -> PackedVector3Array:
	var verts := PackedVector3Array()
	var lift := 0.05
	for i in range(chain.size() - 1):
		var a := chain[i]
		var b := chain[i + 1]
		var dir := Vector3(b.x - a.x, 0.0, b.z - a.z)
		if dir.length() < 0.01:
			continue
		dir = dir.normalized()
		var perp := Vector3(-dir.z, 0.0, dir.x) * (width * 0.5)
		var v0 := Vector3(a.x + perp.x, lift, a.z + perp.z)
		var v1 := Vector3(a.x - perp.x, lift, a.z - perp.z)
		var v2 := Vector3(b.x - perp.x, lift, b.z - perp.z)
		var v3 := Vector3(b.x + perp.x, lift, b.z + perp.z)
		verts.append(v0); verts.append(v1); verts.append(v2)
		verts.append(v0); verts.append(v2); verts.append(v3)
	return verts

# --- water / parks (flat ground polygons) ---

static func _flat_poly_verts(poly: PackedVector2Array, lift: float) -> PackedVector3Array:
	if poly.size() < 3:
		return PackedVector3Array()
	var floor_h: float = ProceduralGen.poly_floor_height(poly, World.terrain) + lift
	var tris := ProceduralGen.triangulate(poly)
	var verts := PackedVector3Array()
	for t in tris:
		verts.append(Vector3(t[0].x, floor_h, t[0].y))
		verts.append(Vector3(t[1].x, floor_h, t[1].y))
		verts.append(Vector3(t[2].x, floor_h, t[2].y))
	return verts

# --- buildings (extruded walls + roof + box collision) ---

static func _building_data(poly: PackedVector2Array, height: float) -> Dictionary:
	var floor_h: float = ProceduralGen.poly_floor_height(poly, World.terrain)
	var verts := PackedVector3Array()
	# Walls.
	for i in range(poly.size()):
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var v0 := Vector3(a.x, floor_h, a.y)
		var v1 := Vector3(b.x, floor_h, b.y)
		var v2 := Vector3(b.x, height + floor_h, b.y)
		var v3 := Vector3(a.x, height + floor_h, a.y)
		verts.append(v0); verts.append(v2); verts.append(v1)
		verts.append(v0); verts.append(v3); verts.append(v2)
	# Roof.
	var tris := ProceduralGen.triangulate(poly)
	for t in tris:
		verts.append(Vector3(t[0].x, height + floor_h, t[0].y))
		verts.append(Vector3(t[1].x, height + floor_h, t[1].y))
		verts.append(Vector3(t[2].x, height + floor_h, t[2].y))
	# Approximate box collision (matches ProceduralGen.building_collision).
	var bounds: Rect2 = _poly_bounds(poly)
	var col_center := Vector3(
		bounds.position.x + bounds.size.x * 0.5,
		height * 0.5 + floor_h,
		bounds.position.y + bounds.size.y * 0.5)
	var col_size := Vector3(bounds.size.x + 0.4, height, bounds.size.y + 0.4)
	return {"verts": verts, "col_center": col_center, "col_size": col_size}

static func _poly_bounds(poly: PackedVector2Array) -> Rect2:
	var r := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		r = r.expand(p)
	return r

# ---------------------------------------------------------------------------
# Phase 2: instantiate nodes on the main thread
# ---------------------------------------------------------------------------

static func instantiate_chunk(data: Dictionary) -> Node3D:
	var chunk := Node3D.new()
	var origin: Vector3 = data["origin"]

	# Terrain mesh + collision.
	var tdata: Dictionary = data["terrain"]
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	ground.mesh = _terrain_mesh(tdata, true)
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = Color(0.38, 0.50, 0.28)
	ground_mat.roughness = 1.0
	ground.material_override = ground_mat
	chunk.add_child(ground)

	var col_mesh := _terrain_mesh(tdata, false)
	var col_body := StaticBody3D.new()
	col_body.name = "GroundCollision"
	col_body.collision_layer = 1
	col_body.collision_mask = 1
	var col_shape := CollisionShape3D.new()
	col_shape.shape = col_mesh.create_trimesh_shape()
	col_body.add_child(col_shape)
	chunk.add_child(col_body)

	# Roads.
	var road_mat := StandardMaterial3D.new()
	road_mat.albedo_color = ROAD_COLOR
	road_mat.roughness = 0.9
	for r in data["roads"]:
		chunk.add_child(_mesh_instance("Road_%d" % r["id"], r["verts"], road_mat))

	# Parks.
	var park_mat := StandardMaterial3D.new()
	park_mat.albedo_color = PARK_COLOR
	park_mat.roughness = 1.0
	for p in data["parks"]:
		chunk.add_child(_mesh_instance("Park_%d" % p["id"], p["verts"], park_mat))

	# Water.
	var water_mat := StandardMaterial3D.new()
	water_mat.albedo_color = WATER_COLOR
	water_mat.roughness = 0.2
	water_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for w in data["water"]:
		chunk.add_child(_mesh_instance("Water_%d" % w["id"], w["verts"], water_mat))

	# Buildings + collision.
	for b in data["buildings"]:
		var bmat := StandardMaterial3D.new()
		bmat.albedo_color = _building_color(b["id"])
		bmat.roughness = 0.85
		var mi := _mesh_instance("Building_%d" % b["id"], b["verts"], bmat)
		chunk.add_child(mi)
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 1
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = b["col_size"]
		shape.shape = box
		shape.position = b["col_center"]
		body.add_child(shape)
		chunk.add_child(body)

	# POI markers.
	for poi in data["pois"]:
		chunk.add_child(_poi_instance(poi))

	return chunk

static func _mesh_instance(name: String, verts: PackedVector3Array, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = _verts_mesh(verts)
	mi.material_override = mat
	return mi

static func _verts_mesh(verts: PackedVector3Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

static func _terrain_mesh(tdata: Dictionary, with_normals: bool) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = tdata["verts"]
	arrays[Mesh.ARRAY_INDEX] = tdata["indices"]
	arrays[Mesh.ARRAY_TEX_UV] = tdata["uvs"]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if with_normals:
		var st := SurfaceTool.new()
		st.create_from(mesh, 0)
		st.generate_normals()
		return st.commit()
	return mesh

static func _poi_instance(poi: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "POI_%d_%s" % [poi["id"], str(poi["kind"])]
	var y: float = ProceduralGen.terrain_height(World.terrain, poi["position"]) + 1.1
	var marker := MeshInstance3D.new()
	marker.name = "Marker"
	var capsule := CapsuleMesh.new()
	capsule.height = 2.4
	capsule.radius = 0.35
	marker.mesh = capsule
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _poi_color(poi["kind"])
	marker.material_override = mat
	marker.position = Vector3(poi["position"].x, y, poi["position"].z)
	root.add_child(marker)
	return root

static func _building_color(id: int) -> Color:
	var palette := [
		Color(0.62, 0.58, 0.52), Color(0.55, 0.50, 0.47),
		Color(0.68, 0.62, 0.55), Color(0.58, 0.51, 0.48),
		Color(0.50, 0.52, 0.56), Color(0.60, 0.55, 0.60),
	]
	return palette[abs(id) % palette.size()]

static func _poi_color(kind: String) -> Color:
	var palette := [
		Color(1.0, 0.85, 0.15), Color(0.95, 0.35, 0.35),
		Color(0.35, 0.75, 1.0), Color(0.55, 0.85, 0.35),
		Color(0.9, 0.55, 0.9), Color(0.95, 0.6, 0.35),
		Color(0.5, 0.9, 0.8),
	]
	var h := 0
	for i in kind.length():
		h = (h * 31 + kind.unicode_at(i)) % palette.size()
	return palette[h]

## Synchronous convenience wrapper (used by tests / debugging).
static func build_tile(origin: Vector3, size: float) -> Node3D:
	var old_size := World.tile_size
	World.tile_size = size
	var key := World.chunk_key_from_pos(origin)
	var data := build_chunk_data(key)
	World.tile_size = old_size
	return instantiate_chunk(data)