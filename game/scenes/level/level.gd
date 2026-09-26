class_name Level
extends Node2D
## The living room: room shell, team bases, the remote's home rug, furniture
## and everything that can get knocked over. Open living_room.tscn in the
## editor to rearrange it. Anything placed under Entities is depth-sorted, so
## put objects there with their origin where they touch the floor.

@onready var room: Room = $Room
@onready var entities: Node2D = $Entities
@onready var home: BaseZone = $Zones/RemoteHome
@onready var bases: Array[BaseZone] = [$Zones/PetsBase, $Zones/RobotsBase]

var mess_items: Array[MessItem] = []
var tv: Furniture


func _ready() -> void:
	for n in entities.get_children():
		if n is MessItem:
			n.index = mess_items.size()
			mess_items.append(n)
		elif n is Furniture and n.style == Furniture.Style.TV:
			tv = n


## Keeps a point inside the floor (margin in tiles).
func clamp_to_floor(p: Vector2, margin: float = 0.4) -> Vector2:
	var t := Iso.local_to_tile(p)
	t.x = clampf(t.x, margin, room.size_tiles.x - margin)
	t.y = clampf(t.y, margin, room.size_tiles.y - margin)
	return Iso.tile_to_local(t)
