class_name OsmPoI
extends Resource

## A point of interest from OSM, projected to game-local coordinates.

@export var id: int = 0
@export var kind: String = "misc"
@export var name: String = ""
@export var position: Vector3 = Vector3.ZERO