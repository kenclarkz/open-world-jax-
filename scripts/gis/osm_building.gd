class_name OsmBuilding
extends Resource

## A building footprint from OSM, projected to game-local coordinates.
## polygon is a closed XZ loop (Vector2 x = x, y = z).

@export var id: int = 0
@export var name: String = ""
@export var height: float = 6.0
@export var polygon: PackedVector2Array = PackedVector2Array()