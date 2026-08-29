class_name OsmPark
extends Resource

## A park / green area polygon from OSM, projected to game-local coordinates.

@export var id: int = 0
@export var name: String = ""
@export var polygon: PackedVector2Array = PackedVector2Array()