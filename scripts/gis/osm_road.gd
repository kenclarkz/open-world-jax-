class_name OsmRoad
extends Resource

## A single road/path/waterway center-line from OSM, already projected to
## game-local coordinates (points are XZ as Vector3 with y=0).

@export var id: int = 0
@export var name: String = ""
@export var highway: String = "residential"
@export var oneway: bool = false
@export var points: PackedVector3Array = PackedVector3Array()
@export var width: float = 8.0
@export var is_bridge: bool = false
@export var is_waterway: bool = false