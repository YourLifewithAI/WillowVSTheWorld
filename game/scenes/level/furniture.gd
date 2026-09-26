@tool
class_name Furniture
extends StaticBody2D
## Solid furniture drawn as simple isometric boxes, so it can be resized and
## recoloured right in the inspector. The node's origin is the centre of its
## footprint on the floor. Walkers bump into it; flyers pass over it.

enum Style { BOX, ARMCHAIR, COUCH, TABLE, TV, CAT_TREE, DOCK }

@export var style: Style = Style.BOX:
	set(v):
		style = v
		queue_redraw()
## Footprint in tiles (i = down-right, j = down-left).
@export var size := Vector2(1, 1):
	set(v):
		size = v
		queue_redraw()
@export var height := 12.0:
	set(v):
		height = v
		queue_redraw()
@export var color := Color("8fb3e0"):
	set(v):
		color = v
		queue_redraw()
@export var accent := Color("ffffff"):
	set(v):
		accent = v
		queue_redraw()
## Swap the i/j axes (turns chairs and couches to face the other way).
@export var mirror := false:
	set(v):
		mirror = v
		queue_redraw()
@export var solid := true

## For Style.TV: -1 = off, otherwise the team whose show is on.
var channel := -1:
	set(v):
		channel = v
		queue_redraw()

const OUTLINE := Color("3b2a30")


func _ready() -> void:
	collision_layer = 2
	collision_mask = 0
	if not Engine.is_editor_hint() and solid:
		var poly := CollisionPolygon2D.new()
		var pts := Iso.footprint(size * 0.92)
		poly.polygon = pts
		add_child(poly)


## Converts a (i, j) tile offset along this piece's own axes, honouring `mirror`.
func _v(i: float, j: float) -> Vector2:
	return Vector2(j, i) if mirror else Vector2(i, j)


func _draw() -> void:
	var w := size.y if mirror else size.x
	var d := size.x if mirror else size.y
	match style:
		Style.BOX:
			_box(Vector2.ZERO, Vector2(w, d), 0, height, color)
		Style.ARMCHAIR:
			_box(Vector2.ZERO, Vector2(w, d), 0, height * 0.55, color)
			_box(Vector2(-w * 0.36, 0), Vector2(w * 0.28, d), height * 0.55, height * 1.35, color)
			_box(Vector2(w * 0.12, -d * 0.4), Vector2(w * 0.76, d * 0.2), height * 0.55, height * 0.95, color.darkened(0.05))
			_box(Vector2(w * 0.12, d * 0.4), Vector2(w * 0.76, d * 0.2), height * 0.55, height * 0.95, color.darkened(0.05))
			_box(Vector2(w * 0.08, 0), Vector2(w * 0.6, d * 0.58), height * 0.55, height * 0.7, accent)
		Style.COUCH:
			_box(Vector2.ZERO, Vector2(w, d), 0, height * 0.6, color)
			_box(Vector2(0, d * 0.34), Vector2(w, d * 0.32), height * 0.6, height * 1.3, color.darkened(0.06))
			_box(Vector2(-w * 0.45, -d * 0.16), Vector2(w * 0.1, d * 0.68), height * 0.6, height * 0.95, color.lightened(0.05))
			_box(Vector2(w * 0.45, -d * 0.16), Vector2(w * 0.1, d * 0.68), height * 0.6, height * 0.95, color.lightened(0.05))
		Style.TABLE:
			for sx in [-1.0, 1.0]:
				for sy in [-1.0, 1.0]:
					_box(Vector2(sx * w * 0.38, sy * d * 0.38), Vector2(0.12, 0.12), 0, height - 3, color.darkened(0.25))
			_box(Vector2.ZERO, Vector2(w, d), height - 3, height, color)
			_box(Vector2(w * 0.1, -d * 0.1), Vector2(w * 0.3, d * 0.22), height, height + 1, accent)
		Style.TV:
			_box(Vector2.ZERO, Vector2(w, d), 0, height, color)
			_draw_tv(Vector2(0, -height))
		Style.CAT_TREE:
			_box(Vector2.ZERO, Vector2(w, d), 0, 5, color)
			_box(Vector2(-w * 0.2, -d * 0.2), Vector2(0.28, 0.28), 5, height * 0.55, Color("e8d3a8"))
			_box(Vector2(-w * 0.1, -d * 0.1), Vector2(w * 0.8, d * 0.8), height * 0.55, height * 0.55 + 4, color)
			_box(Vector2(-w * 0.25, -d * 0.25), Vector2(0.24, 0.24), height * 0.55 + 4, height - 4, Color("e8d3a8"))
			_box(Vector2(-w * 0.25, -d * 0.25), Vector2(w * 0.6, d * 0.6), height - 4, height, color)
			var toy := Iso.tile_to_local(_v(w * 0.3, d * 0.3)) + Vector2(0, -height * 0.55 - 9)
			draw_line(toy + Vector2(0, -2), toy + Vector2(0, 5), Color("fff6ea"))
			draw_circle(toy + Vector2(0, 6), 2.0, accent)
		Style.DOCK:
			_box(Vector2.ZERO, Vector2(w, d), 0, 4, color.darkened(0.3))
			_box(Vector2(-w * 0.35, -d * 0.35), Vector2(w * 0.3, d * 0.3), 4, height, color)
			var glow := Iso.tile_to_local(_v(-w * 0.18, -d * 0.18)) + Vector2(0, -height * 0.6)
			draw_colored_polygon(PackedVector2Array([glow + Vector2(1, -5), glow + Vector2(-3, 1), glow + Vector2(0, 1), glow + Vector2(-1, 5), glow + Vector2(3, -1), glow + Vector2(0, -1)]), accent)
			_box(Vector2(w * 0.15, d * 0.15), Vector2(w * 0.5, d * 0.5), 4, 5, accent.darkened(0.2))


## Draws an isometric box. `at` and `box_size` are in tiles along this piece's
## own axes; z0/z1 are heights in pixels.
func _box(at: Vector2, box_size: Vector2, z0: float, z1: float, c: Color) -> void:
	var hw := box_size.x * 0.5
	var hd := box_size.y * 0.5
	var b := Iso.tile_to_local(_v(at.x - hw, at.y - hd))
	var r := Iso.tile_to_local(_v(at.x + hw, at.y - hd))
	var f := Iso.tile_to_local(_v(at.x + hw, at.y + hd))
	var l := Iso.tile_to_local(_v(at.x - hw, at.y + hd))
	if mirror:
		# Mirroring swaps which corner is on the left/right of the screen.
		var tmp := r
		r = l
		l = tmp
	var lo := Vector2(0, -z0)
	var hi := Vector2(0, -z1)
	draw_colored_polygon(PackedVector2Array([l + lo, f + lo, f + hi, l + hi]), c.darkened(0.22))
	draw_colored_polygon(PackedVector2Array([f + lo, r + lo, r + hi, f + hi]), c.darkened(0.08))
	draw_colored_polygon(PackedVector2Array([b + hi, r + hi, f + hi, l + hi]), c.lightened(0.12))
	draw_polyline(PackedVector2Array([b + hi, r + hi, r + lo, f + lo, l + lo, l + hi, b + hi]), OUTLINE, 1.0)
	draw_polyline(PackedVector2Array([l + hi, f + hi, r + hi]), c.darkened(0.45), 1.0)
	draw_line(f + hi, f + lo, c.darkened(0.45), 1.0)


func _draw_tv(base: Vector2) -> void:
	var frame := Rect2(base + Vector2(-15, -20), Vector2(30, 19))
	draw_rect(Rect2(base + Vector2(-2, -3), Vector2(4, 3)), OUTLINE)
	draw_rect(frame.grow(1), OUTLINE)
	draw_rect(frame, Color("2b2d3a"))
	var screen := frame.grow(-2)
	match channel:
		-1:
			draw_rect(screen, Color("3d4257"))
			for k in 4:
				draw_line(screen.position + Vector2(1, 2 + k * 4), screen.position + Vector2(screen.size.x - 1, 2 + k * 4), Color(1, 1, 1, 0.12))
		0:
			draw_rect(screen, Color("9fe0a0"))
			draw_rect(Rect2(screen.position + Vector2(0, screen.size.y - 4), Vector2(screen.size.x, 4)), Color("5cbf6a"))
			var bird := screen.get_center() + Vector2(0, -1)
			draw_circle(bird, 3.0, Color("ffe45c"))
			draw_rect(Rect2(bird + Vector2(2, -1), Vector2(2, 1)), Color("ff9a3c"))
		1:
			draw_rect(screen, Color("243048"))
			var c := screen.get_center()
			draw_colored_polygon(PackedVector2Array([c + Vector2(1, -6), c + Vector2(-3, 1), c + Vector2(0, 1), c + Vector2(-1, 6), c + Vector2(3, -1), c + Vector2(0, -1)]), Color("62f2ff"))
	draw_rect(Rect2(frame.position + Vector2(2, 2), Vector2(4, 1)), Color(1, 1, 1, 0.3))
