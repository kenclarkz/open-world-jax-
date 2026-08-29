class_name OsmWaterBody
extends Resource

## A river / lake / coastline polygon from OSM, projected to local coords.

@export var id: int = 0
@export var name: String = ""
@export var polygon: PackedVector2Array = PackedVector2Array()