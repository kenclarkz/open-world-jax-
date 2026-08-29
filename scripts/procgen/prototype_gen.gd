class_name PrototypeGen

## Generates a built-in playable prototype "district" of downtown
## Jacksonville, FL as an OsmData dataset (so the game runs with zero
## downloaded data). This exercises the full pipeline (roads, buildings,
## water, parks, minimap, traffic).
##
## When the user imports real OSM data (see README), this fallback is
## replaced automatically by main.gd.
##
## The layout mimics downtown Jacksonville: a street grid with real street
## names (Bay St, Main St, Laura St, Hogan St, Forsyth St, Hemming Lane)
## near the St. Johns River (south), with Hemming Park.

static func generate() -> OsmData:
	var data := OsmData.new()
	_downtown_grid(data)
	_hemming_park(data)
	_st_johns_river(data)
	_buildings_along_roads(data)
	_pois(data)
	_finalize(data)
	print("[PrototypeGen] Built downtown JAX prototype district")
	return data

## Two main arterials cross; a small one-way grid downtown.
static func _downtown_grid(data: OsmData) -> void:
	# Coordinate space: meters, city-center origin. Streets run E-W and N-S.
	var arterials := [
		{"name": "Bay Street",   "axis": "x", "v": 40.0,  "hw": "primary",   "w": 10.0},
		{"name": "Forsyth Street","axis": "x", "v": -40.0, "hw": "secondary", "w": 9.0},
		{"name": "Adams Street",  "axis": "x", "v": -120.0, "hw": "residential", "w": 7.0},
		{"name": "Main Street",   "axis": "z", "v": 90.0, "hw": "primary",   "w": 10.0},
		{"name": "Laura Street",  "axis": "z", "v": 10.0, "hw": "secondary", "w": 9.0},
		{"name": "Hogan Street",  "axis": "z", "v": -80.0, "hw": "residential", "w": 7.0},
	]
	var half := 350.0
	for road in arterials:
		var r := OsmRoad.new()
		r.name = road["name"]
		r.highway = road["hw"]
		r.width = road["w"]
		r.oneway = (road["hw"] == "residential")
		var pts := PackedVector3Array()
		if road["axis"] == "x":
			for step in range(-1, 2):
				pts.append(Vector3(step * half, 0.0, road["v"]))
		else:
			for step in range(-1, 2):
				pts.append(Vector3(road["v"], 0.0, step * half))
		r.points = pts
		data.roads.append(r)

	# A few cross streets to make a recognizable grid downtown.
	var cross := [
		{"name": "Hogan St crossing", "v": -80.0},
	]
	# Short connecting streets for a block-ish grid feel.
	var connector_pts := [
		PackedVector3Array([Vector3(-160, 0, 90), Vector3(-160, 0, -160)]),
		PackedVector3Array([Vector3(160, 0, 90), Vector3(160, 0, -160)]),
	]
	for pts in connector_pts:
		var r := OsmRoad.new()
		r.name = "Connector"
		r.highway = "residential"
		r.width = 7.0
		r.points = pts
		data.roads.append(r)

## Downtown Jacksonville's real park: Hemming Park, one block between
## Hogan and Laura at Adams St.
static func _hemming_park(data: OsmData) -> void:
	var p := OsmPark.new()
	p.id = 9001
	p.name = "Hemming Park"
	p.polygon = PackedVector2Array([
		Vector2(-30, -100), Vector2(10, -100), Vector2(10, -70), Vector2(-30, -70),
	])
	data.parks.append(p)

## The St. Johns River runs along the city's south edge.
static func _st_johns_river(data: OsmData) -> void:
	var w := OsmWaterBody.new()
	w.id = 8001
	w.name = "St. Johns River"
	# A wide band running E-W at z=150, spanning the full map width.
	w.polygon = PackedVector2Array([
		Vector2(-500, 150), Vector2(500, 150), Vector2(500, 330), Vector2(-500, 330),
	])
	data.water_bodies.append(w)

## Drop a scattering of simple square buildings along the streets.
static func _buildings_along_roads(data: OsmData) -> void:
	var id := 5000
	var blocks := [
		# row 1 (north of Bay)
		Vector2(-200, 60), Vector2(-150, 60), Vector2(-100, 60), Vector2(-50, 60),
		Vector2(20, 60), Vector2(70, 60), Vector2(120, 60), Vector2(170, 60),
		# row 2 (between Bay and Forsyth)
		Vector2(-200, 0), Vector2(-150, 0), Vector2(-100, 0), Vector2(-50, 0),
		Vector2(20, 0), Vector2(70, 0), Vector2(120, 0), Vector2(170, 0),
		# row 3 (between Forsyth and Adams)
		Vector2(-200, -80), Vector2(-150, -80), Vector2(-100, -80), Vector2(-50, -80),
		Vector2(20, -80), Vector2(70, -80), Vector2(120, -80), Vector2(170, -80),
		# row 4 (south of Adams, north of river)
		Vector2(-200, -160), Vector2(-150, -160), Vector2(-100, -160), Vector2(-50, -160),
		Vector2(20, -160), Vector2(70, -160), Vector2(120, -160), Vector2(170, -160),
	]
	for center in blocks:
		var b := OsmBuilding.new()
		b.id = id
		id += 1
		var w := randf_range(14.0, 24.0)
		var h := randf_range(14.0, 24.0)
		b.height = randf_range(4.0, 18.0)
		b.polygon = PackedVector2Array([
			Vector2(center.x - w * 0.5, center.y - h * 0.5),
			Vector2(center.x + w * 0.5, center.y - h * 0.5),
			Vector2(center.x + w * 0.5, center.y + h * 0.5),
			Vector2(center.x - w * 0.5, center.y + h * 0.5),
		])
		data.buildings.append(b)

static func _pois(data: OsmData) -> void:
	var p := OsmPoI.new()
	p.id = 7001
	p.kind = "attraction"
	p.name = "Florida Theatre"
	var xz := Vector2(40, 0)
	p.position = Vector3(xz.x, 0, xz.y)
	data.pois.append(p)
	var p2 := OsmPoI.new()
	p2.id = 7002
	p2.kind = "government"
	p2.name = "Duval County Courthouse"
	p2.position = Vector3(-60, 0, 90)
	data.pois.append(p2)

static func _finalize(data: OsmData) -> void:
	var minv := Vector2(INF, INF)
	var maxv := Vector2(-INF, -INF)
	for r in data.roads:
		for pt in r.points:
			minv.x = minf(minv.x, pt.x); minv.y = minf(minv.y, pt.z)
			maxv.x = maxf(maxv.x, pt.x); maxv.y = maxf(maxv.y, pt.z)
	for b in data.buildings:
		for p in b.polygon:
			minv.x = minf(minv.x, p.x); minv.y = minf(minv.y, p.y)
			maxv.x = maxf(maxv.x, p.x); maxv.y = maxf(maxv.y, p.y)
	for w in data.water_bodies:
		for p in w.polygon:
			minv.x = minf(minv.x, p.x); minv.y = minf(minv.y, p.y)
			maxv.x = maxf(maxv.x, p.x); maxv.y = maxf(maxv.y, p.y)
	for pk in data.parks:
		for p in pk.polygon:
			minv.x = minf(minv.x, p.x); minv.y = minf(minv.y, p.y)
			maxv.x = maxf(maxv.x, p.x); maxv.y = maxf(maxv.y, p.y)
	data.bounds_min = minv
	data.bounds_max = maxv