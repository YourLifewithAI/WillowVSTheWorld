class_name Level
extends Node2D
## One home (a map): room shell, team bases, the remote's home rug, furniture
## and everything that can get knocked over. Open a map's .tscn in the editor
## to rearrange it. Anything placed under Entities is depth-sorted, so put
## objects there with their origin where they touch the floor.
##
## Every map needs: Room, Zones/PetsBase, Zones/RobotsBase, Zones/RemoteHome
## and Entities. A Furniture piece with the TV style is optional. Homes with
## several rooms add WallRuns under a "Walls" node (see WallRun), and name
## their rooms with FloorZone.room_name.

@onready var room: Room = $Room
@onready var entities: Node2D = $Entities
@onready var home: BaseZone = $Zones/RemoteHome
@onready var bases: Array[BaseZone] = [$Zones/PetsBase, $Zones/RobotsBase]

var mess_items: Array[MessItem] = []
var furniture: Array[Furniture] = []
var wall_panels: Array[WallPanel] = []
var rooms: Array[FloorZone] = []
var tv: Furniture
var nav_region: NavigationRegion2D

const NAV_CELL := 2.0


func _ready() -> void:
	# Walls first, so their panels come after the scene's own furniture in the
	# indexes below, the same on every machine.
	var walls := get_node_or_null("Walls")
	if walls:
		for run in walls.get_children():
			if run is WallRun:
				wall_panels.append_array(run.build(entities, room.size_tiles))
	var floors := get_node_or_null("Floors")
	for n in get_children() + (floors.get_children() if floors else []):
		if n is FloorZone and n.room_name != "":
			rooms.append(n)
	for n in entities.get_children():
		if n is MessItem:
			n.index = mess_items.size()
			mess_items.append(n)
		elif n is Furniture:
			n.index = furniture.size()
			furniture.append(n)
			if n.style == Furniture.Style.TV:
				tv = n
	NavigationServer2D.map_set_cell_size(get_world_2d().navigation_map, NAV_CELL)
	nav_region = NavigationRegion2D.new()
	nav_region.name = "Navigation"
	nav_region.navigation_polygon = _bake_navigation()
	add_child(nav_region)


## Re-bakes the bots' map after furniture is wrecked or rebuilt.
func rebuild_navigation() -> void:
	nav_region.navigation_polygon = _bake_navigation()


## The standing wall panel at a point, if any.
func wall_at(p: Vector2) -> WallPanel:
	var query := PhysicsPointQueryParameters2D.new()
	query.position = to_global(p)
	query.collision_mask = WallPanel.LAYER
	for hit in get_world_2d().direct_space_state.intersect_point(query, 1):
		return hit["collider"] as WallPanel
	return null


## The first standing wall between two points (level coordinates):
## {"panel": WallPanel, "point": Vector2}, or {} if the way is clear.
func wall_between(a: Vector2, b: Vector2) -> Dictionary:
	if wall_panels.is_empty() or a.is_equal_approx(b):
		return {}
	var query := PhysicsRayQueryParameters2D.create(to_global(a), to_global(b), WallPanel.LAYER)
	query.hit_from_inside = false
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return {}
	return {"panel": hit["collider"], "point": to_local(hit["position"])}


## `b`, or the last point before the first wall on the way from `a` to it.
func clip(a: Vector2, b: Vector2) -> Vector2:
	var hit := wall_between(a, b)
	if hit.is_empty():
		return b
	var back := Iso.to_screen(Iso.to_floor(a - b).normalized() * 3.0)
	return hit["point"] + back


## The named room (FloorZone) containing `p`, or null.
func room_at(p: Vector2) -> FloorZone:
	var t := Iso.local_to_tile(p)
	for r in rooms:
		if r.area.has_point(t):
			return r
	return null


## The standing (solid, not wrecked) furniture at a point, if any.
func furniture_at(p: Vector2) -> Furniture:
	var query := PhysicsPointQueryParameters2D.new()
	query.position = to_global(p)
	query.collision_mask = 2
	for hit in get_world_2d().direct_space_state.intersect_point(query, 4):
		var f := hit["collider"] as Furniture
		if f and not f.wrecked:
			return f
	return null


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


## Bakes a navigation mesh for the bots: the whole floor minus standing furniture.
## A coarse 2 px grid keeps the mesh simple enough to merge cleanly.
func _bake_navigation() -> NavigationPolygon:
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
	var pieces: Array[PackedVector2Array] = []
	# Each run of standing wall panels is one long piece (far fewer to merge).
	var run_rect := Rect2()
	var last: WallPanel = null
	for k in wall_panels.size() + 1:
		var panel: WallPanel = wall_panels[k] if k < wall_panels.size() else null
		var joins: bool = panel != null and last != null and panel.run == last.run \
			and not panel.wrecked and absf(panel.a - last.b) < 0.01
		if last != null and not joins:
			pieces.append(_rect_outline(run_rect.grow(0.05)))
			last = null
		if panel == null or panel.wrecked:
			continue
		run_rect = run_rect.merge(panel.solid_rect()) if last != null else panel.solid_rect()
		last = panel
	for n in entities.get_children():
		if n is Furniture and n.solid and not n.wrecked and not n is WallPanel:
			pieces.append(Transform2D(0, n.position) * Iso.footprint(n.size + Vector2(0.1, 0.1)))
	var obstacles: Array[PackedVector2Array] = []
	for piece in pieces:
		var merged := piece
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
	return nav_poly


static func _rect_outline(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([Iso.tile_to_local(r.position), Iso.tile_to_local(Vector2(r.end.x, r.position.y)),
		Iso.tile_to_local(r.end), Iso.tile_to_local(Vector2(r.position.x, r.end.y))])


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
