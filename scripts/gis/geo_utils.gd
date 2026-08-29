class_name GeoUtils
extends RefCounted

## Converts real-world geographic coordinates (WGS84 lat/lon) into a
## game-friendly local coordinate system.
##
## We use an equirectangular projection centered on Jacksonville, FL.
## 1 degree of latitude ~= 111,320 m; longitude scaled by cos(latitude).
## The game world origin (0,0) corresponds to the city center.

const CENTER_LAT := 30.3322  # Jacksonville city center
const CENTER_LON := -81.6557
const METERS_PER_DEG_LAT := 111320.0

static var center_lat: float = CENTER_LAT
static var center_lon: float = CENTER_LON

## Meters per pixel used for the generated minimap texture.
const MAP_SCALE := 1.0

static func _lon_scale() -> float:
	return cos(deg_to_rad(center_lat))

## Convert lat/lon to local game XZ coordinates (X = east, Z = south).
static func geo_to_local(lat: float, lon: float) -> Vector2:
	var dy := (lat - center_lat) * METERS_PER_DEG_LAT
	var dx := (lon - center_lon) * METERS_PER_DEG_LAT * _lon_scale()
	return Vector2(dx, dy)

## Convert a Vector2 (x, z) into a full 3D coordinate with given height.
static func to_vec3(xz: Vector2, y: float = 0.0) -> Vector3:
	return Vector3(xz.x, y, xz.y)

## Degrees-based distance helper between two lat/lon points (approx, meters).
static func geo_distance(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
	var dy := (lat2 - lat1) * METERS_PER_DEG_LAT
	var dx := (lon2 - lon1) * METERS_PER_DEG_LAT * _lon_scale()
	return Vector2(dx, dy).length()

## Inverse: local back to geographic.
static func local_to_geo(xz: Vector2) -> Vector2:
	var x := xz.x
	var z := xz.y
	var lat := z / METERS_PER_DEG_LAT + center_lat
	var lon := x / (METERS_PER_DEG_LAT * _lon_scale()) + center_lon
	return Vector2(lat, lon)
