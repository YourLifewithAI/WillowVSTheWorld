@tool
class_name Room
extends Node2D
## Draws the room shell (floor, back walls, windows, doors, clock, pictures)
## and builds the invisible walls around the floor. The node's origin is the
## back corner of the floor, tile (0, 0). Every map uses one Room; change its
## size and decor in the inspector to make a different kind of home.
##
## Wall features are placed by tile ranges: the left wall runs along j
## (0..size.y), the right wall along i (0..size.x).

enum FloorStyle { WOOD, TILES, CARPET }
enum WallStyle { STRIPES, PLAIN, WAINSCOT }

@export var size_tiles := Vector2i(16, 16):
	set(v):
		size_tiles = v
		queue_redraw()
@export var wall_height := 64.0:
	set(v):
		wall_height = v
		queue_redraw()

@export_group("Floor")
@export var floor_style: FloorStyle = FloorStyle.WOOD:
	set(v):
		floor_style = v
		queue_redraw()
@export var floor_colors: Array[Color] = [Color("d9a066"), Color("cf955c"), Color("e2ab72")]:
	set(v):
		floor_colors = v
		queue_redraw()

@export_group("Walls")
@export var wall_style: WallStyle = WallStyle.STRIPES:
	set(v):
		wall_style = v
		queue_redraw()
@export var wall_left_color := Color("f3dcc4"):
	set(v):
		wall_left_color = v
		queue_redraw()
@export var wall_right_color := Color("fbe9d6"):
	set(v):
		wall_right_color = v
		queue_redraw()
@export var wainscot_color := Color("a0673f"):
	set(v):
		wainscot_color = v
		queue_redraw()
@export var curtain_left := Color("ff9fb2"):
	set(v):
		curtain_left = v
		queue_redraw()
@export var curtain_right := Color("8fd6c9"):
	set(v):
		curtain_right = v
		queue_redraw()
@export var sky_color := Color("aee0ff"):
	set(v):
		sky_color = v
		queue_redraw()

@export_group("Wall features")
## Windows on the left wall, each as Vector2(start_j, end_j).
@export var left_windows := PackedVector2Array([Vector2(3.0, 5.2)]):
	set(v):
		left_windows = v
		queue_redraw()
## Windows on the right wall, each as Vector2(start_i, end_i).
@export var right_windows := PackedVector2Array([Vector2(3.0, 5.2), Vector2(9.5, 11.7)]):
	set(v):
		right_windows = v
		queue_redraw()
## Front door on the left wall (start_j, end_j). (0, 0) for none.
@export var door_left := Vector2(8.2, 9.8):
	set(v):
		door_left = v
		queue_redraw()
## A door on the right wall (start_i, end_i). (0, 0) for none.
@export var door_right := Vector2.ZERO:
	set(v):
		door_right = v
		queue_redraw()
## Where interior walls meet the back walls: j positions on the left wall,
## i positions on the right. Each gets a dark trim, the wall's cut carried up.
@export var wall_joins_left := PackedFloat32Array():
	set(v):
		wall_joins_left = v
		queue_redraw()
@export var wall_joins_right := PackedFloat32Array():
	set(v):
		wall_joins_right = v
		queue_redraw()
## Each room's own paint on the back walls: the colours, left to right, and
## where they change (one fewer). Empty uses wall_left_color / wall_right_color.
@export var left_paints := PackedColorArray():
	set(v):
		left_paints = v
		queue_redraw()
@export var left_paint_breaks := PackedFloat32Array():
	set(v):
		left_paint_breaks = v
		queue_redraw()
@export var right_paints := PackedColorArray():
	set(v):
		right_paints = v
		queue_redraw()
@export var right_paint_breaks := PackedFloat32Array():
	set(v):
		right_paint_breaks = v
		queue_redraw()
## Outdoors (a porch): these stretches of the back walls are a picket fence.
@export var left_outdoor := Vector2.ZERO:
	set(v):
		left_outdoor = v
		queue_redraw()
@export var right_outdoor := Vector2.ZERO:
	set(v):
		right_outdoor = v
		queue_redraw()
## Centre of the fish painting on the left wall (negative for none).
@export var fish_painting_j := 12.3:
	set(v):
		fish_painting_j = v
		queue_redraw()
## Centre of the robot poster on the right wall (negative for none).
@export var bolt_poster_i := 13.7:
	set(v):
		bolt_poster_i = v
		queue_redraw()
## Where the wall clock hangs on the right wall (negative for none).
@export var clock_i := 7.2:
	set(v):
		clock_i = v
		queue_redraw()

## 0..1, how far the minute hand has swept. The match sets this as a diegetic timer.
var clock_progress := 0.0:
	set(v):
		clock_progress = v
		queue_redraw()
## Opens the doors (the parents are home!).
var door_open := false:
	set(v):
		door_open = v
		queue_redraw()

const OUTLINE := Color("3b2a30")
const SLAB := 7.0


func _ready() -> void:
	if not Engine.is_editor_hint():
		_build_walls()


## The on-screen area the room covers, relative to this node.
func bounds() -> Rect2:
	var w := float(size_tiles.x)
	var d := float(size_tiles.y)
	var top := -wall_height - 4.0
	return Rect2(-d * 16.0 - 4.0, top, (w + d) * 16.0 + 8.0, (w + d) * 8.0 + SLAB - top)


func _t(i: float, j: float) -> Vector2:
	return Iso.tile_to_local(Vector2(i, j))


## A quad on the left-back wall (the plane i = 0) between j0..j1 and heights h0..h1.
func _left_wall_quad(j0: float, j1: float, h0: float, h1: float) -> PackedVector2Array:
	var up0 := Vector2(0, -h0)
	var up1 := Vector2(0, -h1)
	return PackedVector2Array([_t(0, j0) + up0, _t(0, j1) + up0, _t(0, j1) + up1, _t(0, j0) + up1])


## A quad on the right-back wall (the plane j = 0).
func _right_wall_quad(i0: float, i1: float, h0: float, h1: float) -> PackedVector2Array:
	var up0 := Vector2(0, -h0)
	var up1 := Vector2(0, -h1)
	return PackedVector2Array([_t(i0, 0) + up0, _t(i1, 0) + up0, _t(i1, 0) + up1, _t(i0, 0) + up1])


func _quad(on_left: bool, a0: float, a1: float, h0: float, h1: float) -> PackedVector2Array:
	return _left_wall_quad(a0, a1, h0, h1) if on_left else _right_wall_quad(a0, a1, h0, h1)


func _draw() -> void:
	var w := float(size_tiles.x)
	var d := float(size_tiles.y)
	var top := _t(0, 0)
	var right := _t(w, 0)
	var bottom := _t(w, d)
	var left := _t(0, d)

	# Floor slab edge, so the room reads like a little diorama.
	draw_colored_polygon(PackedVector2Array([left, bottom, bottom + Vector2(0, SLAB), left + Vector2(0, SLAB)]), Color("8a5a3c"))
	draw_colored_polygon(PackedVector2Array([bottom, right, right + Vector2(0, SLAB), bottom + Vector2(0, SLAB)]), Color("6e452e"))
	draw_floor(self, Rect2(0, 0, w, d), floor_style, floor_colors)

	# Back walls, painted room by room. Outdoor stretches (a porch) at the far
	# ends are left open for a fence, so the indoor walls stop at dl / wr.
	var h := wall_height
	var dl := left_outdoor.x if left_outdoor.y > left_outdoor.x else d
	var wr := right_outdoor.x if right_outdoor.y > right_outdoor.x else w
	_paint_wall(true, d, left_paints, left_paint_breaks, wall_left_color)
	_paint_wall(false, w, right_paints, right_paint_breaks, wall_right_color)
	match wall_style:
		WallStyle.STRIPES:
			for k in range(1, int(dl)):
				draw_line(_t(0, k) + Vector2(0, -6), _t(0, k) + Vector2(0, -h), Color(0.75, 0.55, 0.45, 0.25))
			for k in range(1, int(wr)):
				draw_line(_t(k, 0) + Vector2(0, -6), _t(k, 0) + Vector2(0, -h), Color(0.75, 0.55, 0.45, 0.2))
		WallStyle.WAINSCOT:
			var ws := 22.0 * _k()
			draw_colored_polygon(_left_wall_quad(0, dl, 0, ws), wainscot_color.darkened(0.12))
			draw_colored_polygon(_right_wall_quad(0, wr, 0, ws), wainscot_color)
			for k in range(1, int(dl) * 2):
				draw_line(_t(0, k * 0.5) + Vector2(0, -3), _t(0, k * 0.5) + Vector2(0, -ws + 2), Color(0, 0, 0, 0.12))
			for k in range(1, int(wr) * 2):
				draw_line(_t(k * 0.5, 0) + Vector2(0, -3), _t(k * 0.5, 0) + Vector2(0, -ws + 2), Color(0, 0, 0, 0.1))
			draw_colored_polygon(_left_wall_quad(0, dl, ws - 1, ws + 2), wainscot_color.lightened(0.2))
			draw_colored_polygon(_right_wall_quad(0, wr, ws - 1, ws + 2), wainscot_color.lightened(0.25))
	# Baseboards.
	draw_colored_polygon(_left_wall_quad(0, dl, 0, 5), Color("fff8ef"))
	draw_colored_polygon(_right_wall_quad(0, wr, 0, 5), Color("ffffff"))
	for j in wall_joins_left:
		draw_colored_polygon(_left_wall_quad(j - 0.07, j + 0.07, 0, h), Color("5a4048"))
	for i in wall_joins_right:
		draw_colored_polygon(_right_wall_quad(i - 0.07, i + 0.07, 0, h), Color("5a4048"))
	_draw_fence(true, left_outdoor)
	_draw_fence(false, right_outdoor)

	for win in left_windows:
		_draw_window(true, win.x, win.y)
	for win in right_windows:
		_draw_window(false, win.x, win.y)
	if door_left.y > door_left.x:
		_draw_door(true, door_left.x, door_left.y)
	if door_right.y > door_right.x:
		_draw_door(false, door_right.x, door_right.y)
	if fish_painting_j >= 0.0:
		_draw_fish_painting(fish_painting_j)
	if bolt_poster_i >= 0.0:
		_draw_bolt_poster(bolt_poster_i)
	if clock_i >= 0.0:
		_draw_clock(clock_i)

	# Wall caps and outline (the indoor part of the back walls).
	var cap := Vector2(0, -h)
	var wall_left := _t(0, dl)
	var wall_right := _t(wr, 0)
	draw_colored_polygon(PackedVector2Array([wall_left + cap, top + cap, top + cap + Vector2(0, -4), wall_left + cap + Vector2(-4, -2)]), Color("c9a58c"))
	draw_colored_polygon(PackedVector2Array([top + cap, wall_right + cap, wall_right + cap + Vector2(4, -2), top + cap + Vector2(0, -4)]), Color("b8927a"))
	draw_polyline(PackedVector2Array([wall_left, wall_left + cap, top + cap, wall_right + cap, wall_right]), OUTLINE, 1.0)
	draw_line(top, top + cap, Color(0, 0, 0, 0.15))
	draw_polyline(PackedVector2Array([left + Vector2(0, SLAB), bottom + Vector2(0, SLAB), right + Vector2(0, SLAB)]), OUTLINE, 1.0)
	draw_line(left, left + Vector2(0, SLAB), OUTLINE)
	draw_line(right, right + Vector2(0, SLAB), OUTLINE)


## Fills a rectangle of floor tiles (in tile coordinates) on `canvas`.
## Shared with FloorZone, which paints kitchens, carpets and rugs on top.
static func draw_floor(canvas: CanvasItem, area: Rect2, style: int, colors: Array[Color]) -> void:
	var i0 := int(area.position.x)
	var j0 := int(area.position.y)
	var i1 := int(ceil(area.end.x))
	var j1 := int(ceil(area.end.y))
	for j in range(j0, j1):
		for i in range(i0, i1):
			var a := Vector2(maxf(i, area.position.x), maxf(j, area.position.y))
			var b := Vector2(minf(i + 1, area.end.x), minf(j + 1, area.end.y))
			var quad := PackedVector2Array([Iso.tile_to_local(a), Iso.tile_to_local(Vector2(b.x, a.y)), Iso.tile_to_local(b), Iso.tile_to_local(Vector2(a.x, b.y))])
			var c: Color
			match style:
				FloorStyle.TILES:
					c = colors[(i + j) % 2 % colors.size()]
				FloorStyle.CARPET:
					c = colors[0]
				_:
					var plank := int(floor((i + (j % 3)) / 3.0))
					c = colors[(plank * 7 + j * 3) % colors.size()]
			canvas.draw_colored_polygon(quad, c)
			if style == FloorStyle.WOOD and (i + (j % 3)) % 3 == 0:
				canvas.draw_line(Iso.tile_to_local(a), Iso.tile_to_local(Vector2(a.x, b.y)), Color(0, 0, 0, 0.12))
			elif style == FloorStyle.CARPET and (i * 7 + j * 13) % 5 == 0:
				var dot := Iso.tile_to_local((a + b) * 0.5)
				canvas.draw_rect(Rect2(dot, Vector2(1, 1)), colors[colors.size() - 1])
		if style == FloorStyle.WOOD:
			canvas.draw_line(Iso.tile_to_local(Vector2(area.position.x, j)), Iso.tile_to_local(Vector2(area.end.x, j)), Color(0, 0, 0, 0.10))
	if style == FloorStyle.TILES:
		for j in range(j0, j1 + 1):
			canvas.draw_line(Iso.tile_to_local(Vector2(area.position.x, j)), Iso.tile_to_local(Vector2(area.end.x, j)), Color(1, 1, 1, 0.25))
		for i in range(i0, i1 + 1):
			canvas.draw_line(Iso.tile_to_local(Vector2(i, area.position.y)), Iso.tile_to_local(Vector2(i, area.end.y)), Color(1, 1, 1, 0.25))


## Decorations shrink with walls lower than the usual 60 px, so nothing pokes out the top.
func _k() -> float:
	return minf(1.0, wall_height / 60.0)


func _draw_window(on_left: bool, a0: float, a1: float) -> void:
	var k := _k()
	var trim := Color("fff8ef") if on_left else Color("ffffff")
	var curtain := curtain_left if on_left else curtain_right
	draw_colored_polygon(_quad(on_left, a0 - 0.15, a1 + 0.15, 18 * k, 54 * k), trim)
	draw_colored_polygon(_quad(on_left, a0, a1, 21 * k, 51 * k), sky_color if not on_left else sky_color.darkened(0.05))
	draw_colored_polygon(_quad(on_left, a0 + 0.3, a0 + 0.9, 21 * k, 51 * k), Color(1, 1, 1, 0.35))
	draw_colored_polygon(_quad(on_left, (a0 + a1) * 0.5 - 0.05, (a0 + a1) * 0.5 + 0.05, 21 * k, 51 * k), trim)
	draw_colored_polygon(_quad(on_left, a0 - 0.45, a0 + 0.05, 14 * k, 56 * k), curtain)
	draw_colored_polygon(_quad(on_left, a1 - 0.05, a1 + 0.45, 14 * k, 56 * k), curtain)


func _draw_door(on_left: bool, a0: float, a1: float) -> void:
	var k := _k()
	draw_colored_polygon(_quad(on_left, a0 - 0.12, a1 + 0.12, 0, 48 * k), Color("fff8ef"))
	if door_open:
		draw_colored_polygon(_quad(on_left, a0, a1, 0, 45 * k), Color("fff4c2"))
		draw_colored_polygon(_quad(on_left, a0, a0 + 0.35, 0, 45 * k), Color("9b6240"))
		return
	draw_colored_polygon(_quad(on_left, a0, a1, 0, 45 * k), Color("b5754c"))
	draw_colored_polygon(_quad(on_left, a0 + 0.2, a1 - 0.2, 26 * k, 40 * k), Color("a3663f"))
	draw_colored_polygon(_quad(on_left, a0 + 0.2, a1 - 0.2, 6 * k, 22 * k), Color("a3663f"))
	var knob := (_t(0, a1 - 0.3) if on_left else _t(a1 - 0.3, 0)) + Vector2(0, -22 * k)
	draw_rect(Rect2(knob - Vector2(1, 1), Vector2(2, 2)), Color("ffd84d"))


## Each room's paint on one back wall.
func _paint_wall(on_left: bool, length: float, paints: PackedColorArray, breaks: PackedFloat32Array, fallback: Color) -> void:
	var outdoor := left_outdoor if on_left else right_outdoor
	var edges: Array[float] = [0.0]
	for b in breaks:
		edges.append(b)
	edges.append(length)
	for k in edges.size() - 1:
		var c := paints[k] if k < paints.size() else fallback
		var a0 := edges[k]
		var a1 := edges[k + 1]
		# Leave the outdoor stretch open (the fence is drawn later).
		if outdoor.y > outdoor.x:
			if a0 < outdoor.x:
				draw_colored_polygon(_quad(on_left, a0, minf(a1, outdoor.x), 0, wall_height), c)
			if a1 > outdoor.y:
				draw_colored_polygon(_quad(on_left, maxf(a0, outdoor.y), a1, 0, wall_height), c)
			continue
		draw_colored_polygon(_quad(on_left, a0, a1, 0, wall_height), c)


## A white picket fence along an outdoor stretch of the back wall.
func _draw_fence(on_left: bool, span: Vector2) -> void:
	if span.y <= span.x:
		return
	draw_colored_polygon(_quad(on_left, span.x, span.y, 0, 5), Color("9fc97a"))
	draw_colored_polygon(_quad(on_left, span.x, span.y, 9, 11), Color("fff8ef"))
	var a := span.x + 0.15
	while a < span.y:
		draw_colored_polygon(_quad(on_left, a - 0.08, a + 0.08, 0, 16), Color("fff8ef"))
		draw_line((_t(0, a) if on_left else _t(a, 0)) + Vector2(0, -16), (_t(0, a) if on_left else _t(a, 0)), Color(0, 0, 0, 0.15))
		a += 0.4


## A fish for the pets' side of the room.
func _draw_fish_painting(j: float) -> void:
	var k := _k()
	draw_colored_polygon(_left_wall_quad(j - 0.9, j + 0.9, 22 * k, 46 * k), Color("8a5a3c"))
	draw_colored_polygon(_left_wall_quad(j - 0.7, j + 0.7, 24 * k, 44 * k), Color("bfe8ff"))
	var fc := _t(0, j) + Vector2(0, -34 * k)
	draw_colored_polygon(PackedVector2Array([fc + Vector2(-6, -1), fc + Vector2(2, -4), fc + Vector2(5, 0), fc + Vector2(2, 3), fc + Vector2(-6, 2)]), Color("ff9f68"))
	draw_colored_polygon(PackedVector2Array([fc + Vector2(4, 0), fc + Vector2(8, -3), fc + Vector2(8, 4)]), Color("ff9f68"))


## A lightning bolt poster for the robots' side.
func _draw_bolt_poster(i: float) -> void:
	var k := _k()
	draw_colored_polygon(_right_wall_quad(i - 0.9, i + 0.9, 22 * k, 46 * k), Color("3f4d70"))
	draw_colored_polygon(_right_wall_quad(i - 0.7, i + 0.7, 24 * k, 44 * k), Color("243048"))
	var bc := _t(i, 0) + Vector2(0, -34 * k)
	draw_colored_polygon(PackedVector2Array([bc + Vector2(1, -8), bc + Vector2(-4, 1), bc + Vector2(0, 1), bc + Vector2(-2, 8), bc + Vector2(4, -2), bc + Vector2(0, -2)]), Color("62f2ff"))


func _draw_clock(i: float) -> void:
	var c := _t(i, 0) + Vector2(0, -40 * _k())
	draw_circle(c, 7.5, OUTLINE)
	draw_circle(c, 6.5, Color("fffdf5"))
	for k in 12:
		var a := TAU * k / 12.0
		draw_rect(Rect2(c + Vector2(cos(a), sin(a)) * 5.0 - Vector2(0.5, 0.5), Vector2(1, 1)), Color("8a5a3c"))
	var minute := -PI / 2 + TAU * clock_progress
	draw_line(c, c + Vector2(cos(minute), sin(minute)) * 5.0, Color("e05a5a"), 1.0)
	draw_line(c, c + Vector2(0, -3), OUTLINE, 1.0)


func _build_walls() -> void:
	var body := StaticBody2D.new()
	body.name = "Walls"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var w := float(size_tiles.x)
	var d := float(size_tiles.y)
	var corners := [_t(0, 0), _t(w, 0), _t(w, d), _t(0, d)]
	for k in 4:
		var seg := SegmentShape2D.new()
		seg.a = corners[k]
		seg.b = corners[(k + 1) % 4]
		var shape := CollisionShape2D.new()
		shape.shape = seg
		body.add_child(shape)


## Is this point (in room coordinates) on the floor, at least `margin` tiles in?
func contains(p: Vector2, margin: float = 0.0) -> bool:
	var t := Iso.local_to_tile(p)
	return t.x >= margin and t.y >= margin and t.x <= size_tiles.x - margin and t.y <= size_tiles.y - margin
