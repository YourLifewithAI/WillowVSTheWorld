@tool
class_name Room
extends Node2D
## Draws the room shell (floor, back walls, windows, door, clock) and builds
## the invisible walls around the floor. The node's origin is the back corner
## of the floor, tile (0, 0).

@export var size_tiles := Vector2i(16, 16):
	set(v):
		size_tiles = v
		queue_redraw()
@export var wall_height := 64.0:
	set(v):
		wall_height = v
		queue_redraw()
@export var floor_colors: Array[Color] = [Color("d9a066"), Color("cf955c"), Color("e2ab72")]
@export var wall_left_color := Color("f3dcc4")
@export var wall_right_color := Color("fbe9d6")

## 0..1, how far the minute hand has swept. The match sets this as a diegetic timer.
var clock_progress := 0.0:
	set(v):
		clock_progress = v
		queue_redraw()
## Opens the front door (the parents are home!).
var door_open := false:
	set(v):
		door_open = v
		queue_redraw()

const OUTLINE := Color("3b2a30")
const SLAB := 7.0


func _ready() -> void:
	if not Engine.is_editor_hint():
		_build_walls()


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

	# Wooden planks: three tiles long, staggered per row.
	for j in size_tiles.y:
		for i in size_tiles.x:
			var plank := int(floor((i + (j % 3)) / 3.0))
			var c: Color = floor_colors[(plank * 7 + j * 3) % floor_colors.size()]
			draw_colored_polygon(PackedVector2Array([_t(i, j), _t(i + 1, j), _t(i + 1, j + 1), _t(i, j + 1)]), c)
			if (i + (j % 3)) % 3 == 0:
				draw_line(_t(i, j), _t(i, j + 1), Color(0, 0, 0, 0.12))
		draw_line(_t(0, j), _t(w, j), Color(0, 0, 0, 0.10))

	# Back walls.
	var h := wall_height
	draw_colored_polygon(_left_wall_quad(0, d, 0, h), wall_left_color)
	draw_colored_polygon(_right_wall_quad(0, w, 0, h), wall_right_color)
	for k in range(1, int(d)):
		draw_line(_t(0, k) + Vector2(0, -6), _t(0, k) + Vector2(0, -h), Color(0.75, 0.55, 0.45, 0.25))
	for k in range(1, int(w)):
		draw_line(_t(k, 0) + Vector2(0, -6), _t(k, 0) + Vector2(0, -h), Color(0.75, 0.55, 0.45, 0.2))
	# Baseboards.
	draw_colored_polygon(_left_wall_quad(0, d, 0, 5), Color("fff8ef"))
	draw_colored_polygon(_right_wall_quad(0, w, 0, 5), Color("ffffff"))

	_draw_window_left(3.0, 5.2)
	_draw_window_right(3.0, 5.2)
	_draw_window_right(9.5, 11.7)
	_draw_door(8.2, 9.8)
	_draw_painting()
	_draw_clock(7.2)

	# Wall caps and outline.
	var cap := Vector2(0, -h)
	draw_colored_polygon(PackedVector2Array([left + cap, top + cap, top + cap + Vector2(0, -4), left + cap + Vector2(-4, -2)]), Color("c9a58c"))
	draw_colored_polygon(PackedVector2Array([top + cap, right + cap, right + cap + Vector2(4, -2), top + cap + Vector2(0, -4)]), Color("b8927a"))
	draw_polyline(PackedVector2Array([left, left + cap, top + cap, right + cap, right]), OUTLINE, 1.0)
	draw_line(top, top + cap, Color(0, 0, 0, 0.15))
	draw_polyline(PackedVector2Array([left + Vector2(0, SLAB), bottom + Vector2(0, SLAB), right + Vector2(0, SLAB)]), OUTLINE, 1.0)
	draw_line(left, left + Vector2(0, SLAB), OUTLINE)
	draw_line(right, right + Vector2(0, SLAB), OUTLINE)


func _draw_window_left(j0: float, j1: float) -> void:
	draw_colored_polygon(_left_wall_quad(j0 - 0.15, j1 + 0.15, 18, 54), Color("fff8ef"))
	draw_colored_polygon(_left_wall_quad(j0, j1, 21, 51), Color("9fd8ff"))
	draw_colored_polygon(_left_wall_quad(j0 + 0.3, j0 + 0.9, 21, 51), Color(1, 1, 1, 0.35))
	draw_colored_polygon(_left_wall_quad((j0 + j1) * 0.5 - 0.05, (j0 + j1) * 0.5 + 0.05, 21, 51), Color("fff8ef"))
	# Curtains.
	draw_colored_polygon(_left_wall_quad(j0 - 0.45, j0 + 0.05, 14, 56), Color("ff9fb2"))
	draw_colored_polygon(_left_wall_quad(j1 - 0.05, j1 + 0.45, 14, 56), Color("ff9fb2"))


func _draw_window_right(i0: float, i1: float) -> void:
	draw_colored_polygon(_right_wall_quad(i0 - 0.15, i1 + 0.15, 18, 54), Color("ffffff"))
	draw_colored_polygon(_right_wall_quad(i0, i1, 21, 51), Color("aee0ff"))
	draw_colored_polygon(_right_wall_quad(i1 - 0.9, i1 - 0.3, 21, 51), Color(1, 1, 1, 0.35))
	draw_colored_polygon(_right_wall_quad((i0 + i1) * 0.5 - 0.05, (i0 + i1) * 0.5 + 0.05, 21, 51), Color("ffffff"))
	draw_colored_polygon(_right_wall_quad(i0 - 0.45, i0 + 0.05, 14, 56), Color("8fd6c9"))
	draw_colored_polygon(_right_wall_quad(i1 - 0.05, i1 + 0.45, 14, 56), Color("8fd6c9"))


func _draw_door(j0: float, j1: float) -> void:
	draw_colored_polygon(_left_wall_quad(j0 - 0.12, j1 + 0.12, 0, 48), Color("fff8ef"))
	if door_open:
		draw_colored_polygon(_left_wall_quad(j0, j1, 0, 45), Color("fff4c2"))
		draw_colored_polygon(_left_wall_quad(j0, j0 + 0.35, 0, 45), Color("9b6240"))
	else:
		draw_colored_polygon(_left_wall_quad(j0, j1, 0, 45), Color("b5754c"))
		draw_colored_polygon(_left_wall_quad(j0 + 0.2, j1 - 0.2, 26, 40), Color("a3663f"))
		draw_colored_polygon(_left_wall_quad(j0 + 0.2, j1 - 0.2, 6, 22), Color("a3663f"))
		var knob := _t(0, j1 - 0.3) + Vector2(0, -22)
		draw_rect(Rect2(knob - Vector2(1, 1), Vector2(2, 2)), Color("ffd84d"))


func _draw_painting() -> void:
	# A fish for the pets (left wall) and a lightning bolt for the robots (right wall).
	draw_colored_polygon(_left_wall_quad(11.4, 13.2, 22, 46), Color("8a5a3c"))
	draw_colored_polygon(_left_wall_quad(11.6, 13.0, 24, 44), Color("bfe8ff"))
	var fc := _t(0, 12.3) + Vector2(0, -34)
	draw_colored_polygon(PackedVector2Array([fc + Vector2(-6, -1), fc + Vector2(2, -4), fc + Vector2(5, 0), fc + Vector2(2, 3), fc + Vector2(-6, 2)]), Color("ff9f68"))
	draw_colored_polygon(PackedVector2Array([fc + Vector2(4, 0), fc + Vector2(8, -3), fc + Vector2(8, 4)]), Color("ff9f68"))
	draw_colored_polygon(_right_wall_quad(12.8, 14.6, 22, 46), Color("3f4d70"))
	draw_colored_polygon(_right_wall_quad(13.0, 14.4, 24, 44), Color("243048"))
	var bc := _t(13.7, 0) + Vector2(0, -34)
	draw_colored_polygon(PackedVector2Array([bc + Vector2(1, -8), bc + Vector2(-4, 1), bc + Vector2(0, 1), bc + Vector2(-2, 8), bc + Vector2(4, -2), bc + Vector2(0, -2)]), Color("62f2ff"))


func _draw_clock(i: float) -> void:
	var c := _t(i, 0) + Vector2(0, -40)
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
