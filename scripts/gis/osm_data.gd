class_name OsmData
extends Resource

## Container holding parsed and projected OpenStreetMap data for one import.
## All coordinates are already converted to game-local XZ space via GeoUtils.

@export var roads: Array[OsmRoad] = []
@export var buildings: Array[OsmBuilding] = []
@export var parks: Array[OsmPark] = []
@export var water_bodies: Array[OsmWaterBody] = []
@export var pois: Array[OsmPoI] = []
@export var bounds_min: Vector2 = Vector2.ZERO
@export var bounds_max: Vector2 = Vector2.ZERO
@export var point_count: int = 0