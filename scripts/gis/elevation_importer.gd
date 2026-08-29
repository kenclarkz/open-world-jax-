class_name ElevationImporter
extends Node

## Elevation / terrain import pipeline.
##
## Jacksonville, FL is nearly flat (elevation ~1-10m), so we support:
##   1. A real SRTM GeoTIFF/ASC tile (free, NASA/USGS) when provided.
##   2. A built-in flat-with-gentle-slope fallback so the prototype runs
##      with zero datasets, while the real terrain can be swapped in.
##
## Data format: a simple 2D raster grid of heights. We accept:
##   - .asc (ESRI ASCII Grid) — plain text, easy to parse.
##   - .png heightmap (single-channel, 16-bit grayscale) exported from a
##     SRTM tool/GIS.
##   - Nothing → generates flat terrain with a gradual slope toward the
##     St. Johns River on the east side.
##
## Free sources (see README):
##   - OpenTopography SRTM 1-arcsecond (~30m) tiles:
##     https://portal.opentopography.org/raster?opentopoID=OTSRTM.082015.4326.1
##   - USGS 3DEP (public domain).

signal terrain_loaded(data: Dictionary)

## Return a heightmap dictionary: {"size": Vector2i (cells), "heights": PackedFloat32Array}
func load_terrain(path: String = "") -> Dictionary:
	if path != "" and FileAccess.file_exists(path):
		var data := _load_file(path)
		if not data.is_empty():
			terrain_loaded.emit(data)
			return data
	print("[ElevationImporter] No terrain dataset; using procedural flat terrain for JAX.")
	var data := _generate_jax_terrain()
	terrain_loaded.emit(data)
	return data

func _load_file(path: String) -> Dictionary:
	var ext := path.get_extension().to_lower()
	if ext == "asc" or ext == "txt":
		return _parse_asc(path)
	elif ext == "png" or ext == "tif":
		return _parse_png_height(path)
	return {}

## Parse ESRI ASCII Grid (.asc). Header: ncols nrows xllcorner yllcorner cellsize NODATA_value.
func _parse_asc(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var ncols := 0
	var nrows := 0
	var cellsize := 1.0
	var nodata := -9999.0
	var values := PackedFloat32Array()
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line == "":
			continue
		var parts := line.split(" ", false)
		var key: String = parts[0].to_lower()
		if key == "ncols":
			ncols = int(parts[1])
		elif key == "nrows":
			nrows = int(parts[1])
		elif key == "cellsize":
			cellsize = float(parts[1])
		elif key == "nodata_value":
			nodata = float(parts[1])
		else:
			for p in parts:
				values.append(float(p))
	f.close()
	if ncols <= 0 or nrows <= 0 or values.size() < ncols * nrows:
		push_warning("[ElevationImporter] Bad ASC file: %s" % path)
		return {}
	# Reorder rows so row 0 is north (top of the map).
	var heights := PackedFloat32Array()
	for r in range(nrows - 1, -1, -1):
		for c in range(ncols):
			var v := values[r * ncols + c]
			heights.append(0.0 if v == nodata else v)
	return {"size": Vector2i(ncols, nrows), "heights": heights, "cellsize": cellsize}

## Parse a 16-bit grayscale PNG heightmap (0=low, 65535=high) mapped to a range.
func _parse_png_height(path: String) -> Dictionary:
	var img := Image.load_from_file(path)
	if img == null:
		return {}
	img.convert(Image.FORMAT_L8)
	var w := img.get_width()
	var h := img.get_height()
	var heights := PackedFloat32Array()
	for y in range(h):
		for x in range(w):
			heights.append(float(img.get_pixel(x, y).r) * 20.0)  # scale 0..1 -> 0..20m
	return {"size": Vector2i(w, h), "heights": heights, "cellsize": 30.0}

## Generate a plausible flat-but-sloped terrain for Jacksonville.
## Elevation rises gently inland (west) and dips toward the river/coast (east).
func _generate_jax_terrain() -> Dictionary:
	var size := Vector2i(256, 256)
	var heights := PackedFloat32Array()
	var ext := 12000.0  # half-world extent in meters
	for z in range(size.y):
		for x in range(size.x):
			var nx := (float(x) / float(size.x - 1)) * 2.0 - 1.0  # -1..1 (west..east)
			var nz := (float(z) / float(size.y - 1)) * 2.0 - 1.0
			# Gentle east-west slope (higher in west), baseline ~4m.
			var h := 4.0 + (1.0 - nx) * 6.0
			# Low river valley along the St. Johns running north-south through the city.
			var river_x := -0.15
			var dist_to_river: float = absf(nx - river_x)
			h -= max(0.0, 2.5 * (1.0 - dist_to_river * 4.0))
			# Tiny natural undulation.
			h += sin(nx * 6.0 + nz * 4.0) * 0.3
			heights.append(h)
	return {"size": size, "heights": heights, "cellsize": ext * 2.0 / float(size.x)}

## Sample terrain height at local XZ coordinates given a terrain dict.
func sample_height(terrain: Dictionary, pos: Vector3) -> float:
	var size: Vector2i = terrain.get("size", Vector2i(1, 1))
	var heights: PackedFloat32Array = terrain.get("heights", PackedFloat32Array())
	var cellsize: float = terrain.get("cellsize", 30.0)
	var half_w := float(size.x) * cellsize * 0.5
	var half_h := float(size.y) * cellsize * 0.5
	var fx := (pos.x + half_w) / (float(size.x - 1) * cellsize)
	var fy := (pos.z + half_h) / (float(size.y - 1) * cellsize)
	fx = clamp(fx, 0.0, 1.0)
	fy = clamp(fy, 0.0, 1.0)
	var x0 := int(fx * float(size.x - 1))
	var y0 := int(fy * float(size.y - 1))
	x0 = clampi(x0, 0, size.x - 1)
	y0 = clampi(y0, 0, size.y - 1)
	return heights[y0 * size.x + x0]
