class_name Level
extends Node2D
## One home (a map): room shell, team bases, the remote's home rug, furniture
## and everything that can get knocked over. Open a map's .tscn in the editor
## to rearrange it. Anything placed under Entities is depth-sorted, so put
## objects there with their origin where they touch the floor.
##
## Every map needs: Room, Zones/PetsBase, Zones/RobotsBase, Zones/RemoteHome
## and Entities. A Furniture piece with the TV style is optional.

@onready var room: Room = $Room
@onready var entities: Node2D = $Entities
@onready var home: BaseZone = $Zones/RemoteHome
@onready var bases: Array[BaseZone] = [$Zones/PetsBase, $Zones/RobotsBase]

var mess_items: Array[MessItem] = []
var tv: Furniture
var nav_region: NavigationRegion2D

const NAV_CELL := 2.0


func _ready() -> void:
	for n in entities.get_children():
		if n is MessItem:
			n.index = mess_items.size()
			mess_items.append(n)
		elif n is Furniture and n.style == Furniture.Style.TV:
			tv = n
	_build_navigation()


## Where to put this level so the room sits in the middle of a view of `view_size`.
func centered_position(view_size: Vector2) -> Vector2:
	var b := room.bounds()
	var pos := (view_size - b.size) / 2.0 - b.position
	# Nudge down a little (under the scoreboard) when there's room to spare.
	pos.y += clampf((view_size.y - b.size.y) / 2.0, 0.0, 6.0)
	return pos.round()


## Keeps a point inside the floor (margin in tiles).
func clamp_to_floor(p: Vector2, margin: float = 0.4) -> Vector2:
	var t := Iso.local_to_tile(p)
	t.x = clampf(t.x, margin, room.size_tiles.x - margin)
	t.y = clampf(t.y, margin, room.size_tiles.y - margin)
	return Iso.tile_to_local(t)


## Bakes a navigation mesh for the bots: the whole floor minus solid furniture.
func _build_navigation() -> void:
	# A coarser 2 px grid keeps the mesh simple enough to merge cleanly.
	NavigationServer2D.map_set_cell_size(get_world_2d().navigation_map, NAV_CELL)
	var nav_poly := NavigationPolygon.new()
	nav_poly.cell_size = NAV_CELL
	nav_poly.agent_radius = 5.0
	var source := NavigationMeshSourceGeometryData2D.new()
	var w := float(room.size_tiles.x)
	var d := float(room.size_tiles.y)
	source.add_traversable_outline(PackedVector2Array([
		Iso.tile_to_local(Vector2(0, 0)), Iso.tile_to_local(Vector2(w, 0)),
		Iso.tile_to_local(Vector2(w, d)), Iso.tile_to_local(Vector2(0, d))]))
	# Neighbouring pieces (counter runs, wall segments) are merged into one
	# outline first; separate touching outlines leave slivers in the mesh.
	var obstacles: Array[PackedVector2Array] = []
	for n in entities.get_children():
		if n is Furniture and n.solid:
			var merged := Transform2D(0, n.position) * Iso.footprint(n.size + Vector2(0.1, 0.1))
			var k := 0
			while k < obstacles.size():
				var union := Geometry2D.merge_polygons(merged, obstacles[k])
				if union.size() == 1:
					merged = union[0]
					obstacles.remove_at(k)
					k = 0
				else:
					k += 1
			obstacles.append(merged)
	for outline in obstacles:
		source.add_obstruction_outline(_simplify(outline))
	NavigationServer2D.bake_from_source_geometry_data(nav_poly, source)
	nav_region = NavigationRegion2D.new()
	nav_region.name = "Navigation"
	nav_region.navigation_polygon = nav_poly
	add_child(nav_region)


## Drops points that sit on a straight line between their neighbours.
static func _simplify(outline: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := outline.size()
	for k in n:
		var prev := outline[(k + n - 1) % n]
		var cur := outline[k]
		var next := outline[(k + 1) % n]
		if absf((cur - prev).cross(next - cur)) > 0.5:
			out.append(cur)
	return out


## A walking route between two points in this level's coordinates (empty if none yet).
func find_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	var map := nav_region.get_navigation_map()
	if NavigationServer2D.map_get_iteration_id(map) == 0:
		return PackedVector2Array()
	var path := NavigationServer2D.map_get_path(map, to_global(from), to_global(to), true)
	var local := PackedVector2Array()
	for p in path:
		local.append(to_local(p))
	return local
