extends Node

## OpenStreetMap GIS import pipeline.
##
## Reads an OSM extract (XML .osm from Overpass/Geofabrik, or GeoJSON
## .json), parses ways/relations into roads, buildings, parks, waterways
## and POIs, projects them into game-local coordinates, and caches the
## result as a binary OsmData resource. Parsing runs once per dataset.
##
## Usage:
##   OSMImporter.import_file("res://import_data/osm/jacksonville.osm")
##
## Free data sources (see README):
##   - Geofabrik Florida extract (https://download.geofabrik.de)
##     then crop Jacksonville's bbox with osmium/osmosis.
##   - Overpass API (https://overpass-api.de) for a live bbox query.
##     Example Overpass query:
##       [out:json][timeout:90];
##       (
##         way["highway"](30.15,-81.75,30.45,-81.55);
##         way["building"](30.15,-81.75,30.45,-81.55);
##       way["leisure"~"park|garden"](30.15,-81.75,30.45,-81.55);
##         way["natural"~"water|coastline|riverbank"](30.15,-81.75,30.45,-81.55);
##         node["amenity"](30.15,-81.75,30.45,-81.55);
##       ); out body;

signal import_finished(data: OsmData)

const HIGHWAY_WIDTHS := {
	"motorway": 12.0, "trunk": 11.0, "primary": 10.0, "secondary": 9.0,
	"tertiary": 8.0, "residential": 7.0, "service": 5.0, "unclassified": 7.0,
	"living_street": 6.0, "pedestrian": 4.0, "footway": 2.0, "cycleway": 2.0,
	"path": 1.5, "steps": 2.0,
}

func import_file(path: String, cached: bool = true) -> OsmData:
	var cache_path := _cache_path_for(path)
	if cached and ResourceLoader.exists(cache_path):
		print("[OSMImporter] Loading cached import: ", cache_path)
		return load(cache_path) as OsmData

	print("[OSMImporter] Parsing ", path)
	var data: OsmData = null
	if path.get_extension().to_lower() == "json":
		data = _parse_geojson(path)
	else:
		data = _parse_osm_xml(path)

	if data == null:
		push_error("[OSMImporter] Failed to parse " + path)
		return null

	var err := ResourceSaver.save(data, cache_path)
	if err != OK:
		push_warning("[OSMImporter] Could not cache: %s" % err)

	import_finished.emit(data)
	return data

func _cache_path_for(src: String) -> String:
	return src.get_base_dir().path_join(src.get_file().get_basename() + ".tres")

# ---------------------------------------------------------------------------
# OSM XML parsing
# ---------------------------------------------------------------------------

func _parse_osm_xml(path: String) -> OsmData:
	var nodes := {}
	var ways := {}
	var rels := {}
	var parser := XMLParser.new()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Cannot open OSM file: " + path)
		return null
	var text := f.get_as_text()
	f.close()
	var err := parser.open_buffer(text.to_utf8_buffer())
	if err != OK:
		push_error("XML parse error: " + str(err))
		return null

	while parser.read() == OK:
		if parser.get_node_type() != XMLParser.NODE_ELEMENT:
			continue
		var tag := parser.get_node_name()
		var is_empty := parser.is_empty()
		var id := str(parser.get_named_attribute_value_safe("id"))
		if tag == "node":
			var lat: float = parser.get_named_attribute_value_safe("lat").to_float()
			var lon: float = parser.get_named_attribute_value_safe("lon").to_float()
			var tags := {}
			_consume_children(parser, is_empty, tags)
			nodes[id] = {"lat": lat, "lon": lon, "tags": tags}
		elif tag == "way":
			var nds: Array = []
			var tags := {}
			_consume_children(parser, is_empty, tags, nds)
			ways[id] = {"nds": nds, "tags": tags}
		elif tag == "relation":
			var members: Array = []
			var tags := {}
			_consume_children(parser, is_empty, tags, members, true)
			rels[id] = {"members": members, "tags": tags}

	return _assemble(nodes, ways, rels)

## Consume children of the current element (tags and node refs).
## Empty (self-closing) elements have no children and no END marker, so
## we return immediately for them.
func _consume_children(parser: XMLParser, is_empty_parent: bool, tags: Dictionary, node_refs: Array = [], collect_members: bool = false) -> void:
	if is_empty_parent:
		return
	while true:
		if parser.read() != OK:
			return
		var type := parser.get_node_type()
		if type == XMLParser.NODE_ELEMENT:
			var tag := parser.get_node_name()
			if tag == "tag":
				tags[parser.get_named_attribute_value_safe("k")] = parser.get_named_attribute_value_safe("v")
			elif tag == "nd" and not collect_members:
				node_refs.append(parser.get_named_attribute_value_safe("ref"))
			elif tag == "member" and collect_members:
				node_refs.append({
					"type": parser.get_named_attribute_value_safe("type"),
					"ref": parser.get_named_attribute_value_safe("ref"),
					"role": parser.get_named_attribute_value_safe("role"),
				})
		elif type == XMLParser.NODE_ELEMENT_END:
			return

# ---------------------------------------------------------------------------
# GeoJSON parsing (Overpass JSON / exports)
# ---------------------------------------------------------------------------

func _parse_geojson(path: String) -> OsmData:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Cannot open GeoJSON: " + path)
		return null
	var text := f.get_as_text()
	f.close()
	var root = JSON.parse_string(text)
	if root == null or not root.has("elements"):
		# Try top-level FeatureCollection
		if root is Dictionary and root.has("features"):
			return _assemble_geojson_features(root["features"])
		push_error("GeoJSON missing 'elements' or 'features'.")
		return null
	return _assemble_overpass_json(root["elements"])

func _assemble_overpass_json(elements: Array) -> OsmData:
	var nodes := {}
	var ways := {}
	var rels := {}
	for el in elements:
		if not (el is Dictionary):
			continue
		var type: String = el.get("type", "")
		var id := str(el.get("id", 0))
		var tags: Dictionary = el.get("tags", {})
		if type == "node":
			nodes[id] = {"lat": float(el.get("lat", 0.0)), "lon": float(el.get("lon", 0.0)), "tags": tags}
		elif type == "way":
			var nds: Array = []
			for ref in el.get("nodes", []):
				nds.append(str(ref))
			ways[id] = {"nds": nds, "tags": tags}
		elif type == "relation":
			var members: Array = []
			for m in el.get("members", []):
				members.append({
					"type": m.get("type", ""),
					"ref": str(m.get("ref", 0)),
					"role": m.get("role", ""),
				})
			rels[id] = {"members": members, "tags": tags}
	return _assemble(nodes, ways, rels)

func _assemble_geojson_features(features: Array) -> OsmData:
	var data := OsmData.new()
	var geoms: Array = []
	for feat in features:
		var props: Dictionary = feat.get("properties", {})
		var geom: Dictionary = feat.get("geometry", {})
		geoms.append({"geom": geom, "tags": props})
	_process_geometries(data, geoms)
	_finalize(data)
	return data

# ---------------------------------------------------------------------------
# Assemble nodes/ways/relations into OsmData
# ---------------------------------------------------------------------------

func _assemble(nodes: Dictionary, ways: Dictionary, rels: Dictionary) -> OsmData:
	var data := OsmData.new()
	var key := func(id: String) -> Vector2:
		var n: Dictionary = nodes[id]
		return GeoUtils.geo_to_local(float(n["lat"]), float(n["lon"]))

	# Build water relations (multipolygons) so rivers/lakes/coastline render.
	var water_rels: Array = []
	for rid in rels:
		var r: Dictionary = rels[rid]
		var tags: Dictionary = r["tags"]
		if _is_water_tag(tags):
			# Collect outer ways.
			var outer_polys: Array = []
			var inner_polys: Array = []
			for m in r["members"]:
				if m["type"] != "way":
					continue
				var wid: String = m["ref"]
				if not ways.has(wid):
					continue
				var w: Dictionary = ways[wid]
				var pts := _way_points(w, key)
				if pts.size() >= 3:
					if m["role"] == "inner":
						inner_polys.append(pts)
					else:
						outer_polys.append(pts)
			if outer_polys.is_empty():
				continue
			var water := OsmWaterBody.new()
			water.id = int(rid)
			water.name = tags.get("name", "")
			water.polygon = outer_polys[0]
			data.water_bodies.append(water)

	for wid in ways:
		var w: Dictionary = ways[wid]
		var tags: Dictionary = w["tags"]
		var pts := _way_points(w, key)
		if pts.size() < 2:
			continue
		_classify_way(data, int(wid), tags, pts)

	# POI nodes.
	for nid in nodes:
		var n: Dictionary = nodes[nid]
		for k in NODE_POI_KEYS():
			if n["tags"].has(k):
				var poi := OsmPoI.new()
				poi.id = int(nid)
				poi.kind = k
				poi.name = n["tags"].get("name", n["tags"].get(k, k))
				var xz := GeoUtils.geo_to_local(float(n["lat"]), float(n["lon"]))
				poi.position = Vector3(xz.x, 0.0, xz.y)
				data.pois.append(poi)
				break

	_finalize(data)
	return data

func _way_points(w: Dictionary, key: Callable) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for nd_id in w["nds"]:
		var xz: Vector2 = key.call(nd_id)
		pts.append(Vector3(xz.x, 0.0, xz.y))
	return pts

func _classify_way(data: OsmData, id: int, tags: Dictionary, pts: PackedVector3Array) -> void:
	if tags.has("highway"):
		var highway: String = tags["highway"]
		var road := OsmRoad.new()
		road.id = id
		road.name = tags.get("name", "")
		road.highway = highway
		road.oneway = tags.get("oneway", "") == "yes" or tags.get("oneway", "") == "true" or tags.get("oneway", "") == "1"
		road.points = pts
		road.width = HIGHWAY_WIDTHS.get(highway, 5.0)
		road.is_bridge = tags.has("bridge") or tags.has("man_made") and tags["man_made"] == "bridge"
		road.is_waterway = tags.has("waterway")
		data.roads.append(road)
		return

	if tags.has("building"):
		var b := OsmBuilding.new()
		b.id = id
		b.name = tags.get("name", "")
		var levels: float = tags.get("building:levels", "1").to_float()
		b.height = levels * 3.2 + tags.get("height", "").to_float()
		if b.height <= 0.1:
			b.height = 6.0
		b.polygon = _to_poly(pts)
		if b.polygon.size() >= 3:
			data.buildings.append(b)
		return

	if _is_water_tag(tags):
		var water := OsmWaterBody.new()
		water.id = id
		water.name = tags.get("name", "")
		water.polygon = _to_poly(pts)
		data.water_bodies.append(water)
		return

	if tags.has("leisure") or tags.has("landuse"):
		var leisure: String = str(tags.get("leisure", tags.get("landuse", "")))
		if leisure in ["park", "garden", "recreation_ground", "common", "grass", "nature_reserve", "forest", "wood"]:
			var park := OsmPark.new()
			park.id = id
			park.name = tags.get("name", "")
			park.polygon = _to_poly(pts)
			data.parks.append(park)
			return

func _to_poly(pts: PackedVector3Array) -> PackedVector2Array:
	var poly := PackedVector2Array()
	for p in pts:
		if poly.size() > 0 and poly[poly.size() - 1] == Vector2(p.x, p.z):
			continue
		poly.append(Vector2(p.x, p.z))
	return poly

func _is_water_tag(tags: Dictionary) -> bool:
	if tags.has("natural") and tags["natural"] in ["water", "coastline", "riverbank", "bay", "wetland"]:
		return true
	if tags.has("waterway") and tags["waterway"] in ["river", "canal", "stream"]:
		return true
	if tags.has("water"):
		return true
	return false

func NODE_POI_KEYS() -> Array:
	return ["amenity", "shop", "tourism", "historic", "leisure", "sport"]

func _process_geometries(data: OsmData, geoms: Array) -> void:
	var id := 0
	for g in geoms:
		id += 1
		var tags: Dictionary = g["tags"]
		var geom: Dictionary = g["geom"]
		var gtype: String = geom.get("type", "")
		# Expand GeoJSON geometries into coordinate arrays.
		var coords: Array = []
		if gtype == "Polygon":
			coords = [geom["coordinates"][0]]
		elif gtype == "MultiPolygon":
			for poly in geom["coordinates"]:
				coords.append(poly[0])
		elif gtype == "LineString":
			coords = [geom["coordinates"]]
		elif gtype == "MultiLineString":
			for line in geom["coordinates"]:
				coords.append(line)
		elif gtype == "Point":
			var c: Array = geom["coordinates"]
			var xz := GeoUtils.geo_to_local(float(c[1]), float(c[0]))
			var poi := OsmPoI.new()
			poi.id = id
			poi.kind = str(tags.keys().size())
			poi.name = tags.get("name", "POI")
			poi.position = Vector3(xz.x, 0.0, xz.y)
			data.pois.append(poi)
			continue

		for crd_set in coords:
			var pts := PackedVector3Array()
			var poly := PackedVector2Array()
			for c in crd_set:
				# GeoJSON order is [lon, lat].
				var xz := GeoUtils.geo_to_local(float(c[1]), float(c[0]))
				pts.append(Vector3(xz.x, 0.0, xz.y))
				poly.append(Vector2(xz.x, xz.y))
			if tags.has("highway"):
				var road := OsmRoad.new()
				road.id = id
				road.name = tags.get("name", "")
				road.highway = tags["highway"]
				road.oneway = tags.get("oneway", "") == "yes"
				road.points = pts
				road.width = HIGHWAY_WIDTHS.get(tags["highway"], 5.0)
				data.roads.append(road)
			elif tags.has("building"):
				if poly.size() >= 3:
					var b := OsmBuilding.new()
					b.id = id
					b.name = tags.get("name", "")
					var levels: float = tags.get("building:levels", "1").to_float()
					b.height = max(levels * 3.2, 3.0)
					b.polygon = poly
					data.buildings.append(b)
			elif _is_water_tag(tags):
				if poly.size() >= 3:
					var water := OsmWaterBody.new()
					water.id = id
					water.name = tags.get("name", "")
					water.polygon = poly
					data.water_bodies.append(water)
			elif tags.has("leisure") or tags.has("landuse"):
				if poly.size() >= 3:
					var park := OsmPark.new()
					park.id = id
					park.name = tags.get("name", "")
					park.polygon = poly
					data.parks.append(park)

func _finalize(data: OsmData) -> void:
	# Compute bounds over all roads/areas for later tiling and minimap.
	var minv := Vector2(INF, INF)
	var maxv := Vector2(-INF, -INF)
	var consider := func(p: Vector3):
		minv.x = min(minv.x, p.x); minv.y = min(minv.y, p.z)
		maxv.x = max(maxv.x, p.x); maxv.y = max(maxv.y, p.z)
	for r in data.roads:
		for p in r.points:
			consider.call(p)
	for b in data.buildings:
		for p in b.polygon:
			consider.call(Vector3(p.x, 0, p.y))
	for w in data.water_bodies:
		for p in w.polygon:
			consider.call(Vector3(p.x, 0, p.y))
	for pk in data.parks:
		for p in pk.polygon:
			consider.call(Vector3(p.x, 0, p.y))
	if minv.x < INF:
		data.bounds_min = minv
		data.bounds_max = maxv
	else:
		data.bounds_min = Vector2(-5000, -5000)
		data.bounds_max = Vector2(5000, 5000)
	print("[OSMImporter] Imported %d roads, %d buildings, %d water, %d parks, %d POIs" % [
		data.roads.size(), data.buildings.size(), data.water_bodies.size(),
		data.parks.size(), data.pois.size(),
	])
