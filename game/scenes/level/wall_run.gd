@tool
class_name WallRun
extends Node2D
## One straight interior wall, facing one room. Put WallRuns under a "Walls"
## node in a map (beside Entities, at the level's origin) and set them up in
## tile coordinates, like Room. When a match starts, Level builds each run into
## WallPanels (one per tile, so they can break one at a time) and WallSlices
## (which draw them). The camera only ever sees one face of a wall: the +i side
## for plane I, the +j side for plane J, so face_color is that room's paint.
##
## Walls are drawn like a dollhouse with the top cut off (HEIGHT px, with a dark
## "cut" cap), so you can see over them. Plain painted walls (DRYWALL) break
## under heavy hits; STONE and EXTERIOR never do.

enum Axis { I, J }
enum Surface { DRYWALL, STONE, EXTERIOR }

const HEIGHT := 20.0
const THICKNESS := 0.25
## Collision and navigation stop this far short of the room's shell.
const SHELL_INSET := 0.1

## I: the line i = at, running along j. J: the line j = at, running along i.
@export var plane: Axis = Axis.I:
	set(v):
		plane = v
		queue_redraw()
@export var at := 7.0:
	set(v):
		at = v
		queue_redraw()
@export var from := 0.0:
	set(v):
		from = v
		queue_redraw()
@export var to := 7.0:
	set(v):
		to = v
		queue_redraw()
## Doorways, each as Vector2(start, end) along the run (at least 2 tiles wide).
@export var doors := PackedVector2Array():
	set(v):
		doors = v
		queue_redraw()
@export var surface: Surface = Surface.DRYWALL:
	set(v):
		surface = v
		queue_redraw()
## Stone stretches inside a painted wall (a chimney), as Vector2(start, end).
@export var stone_spans := PackedVector2Array():
	set(v):
		stone_spans = v
		queue_redraw()
## The paint of the room this wall's visible face looks into.
@export var face_color := Color("f3dcc4"):
	set(v):
		face_color = v
		queue_redraw()
## What the feed calls it ("the kitchen wall").
@export var label := "wall"


func _ready() -> void:
	if not Engine.is_editor_hint():
		visible = false  # the panels draw the real thing


## The solid stretches of this wall, split where doors and stone begin and end:
## Array of [start, end, material].
func pieces() -> Array:
	var cuts: Array[float] = [from, to]
	for d in doors:
		cuts.append_array([d.x, d.y])
	for s in stone_spans:
		cuts.append_array([s.x, s.y])
	cuts.sort()
	var out := []
	for k in cuts.size() - 1:
		var a := clampf(cuts[k], from, to)
		var b := clampf(cuts[k + 1], from, to)
		if b - a < 0.05:
			continue
		var mid := (a + b) * 0.5
		if _inside(mid, doors):
			continue
		var mat := Surface.STONE if _inside(mid, stone_spans) else surface
		out.append([a, b, mat])
	return out


static func _inside(x: float, spans: PackedVector2Array) -> bool:
	for s in spans:
		if x > s.x and x < s.y:
			return true
	return false


## True if a doorway starts or ends at `x` along this wall.
func is_door_edge(x: float) -> bool:
	for d in doors:
		if absf(d.x - x) < 0.01 or absf(d.y - x) < 0.01:
			return true
	return false


## The floor area (in tiles: position = (i, j), size = extent) of this wall from a to b.
func tile_rect(a: float, b: float) -> Rect2:
	if plane == Axis.I:
		return Rect2(at - THICKNESS * 0.5, a, THICKNESS, b - a)
	return Rect2(a, at - THICKNESS * 0.5, b - a, THICKNESS)


## A point on the wall's centre line, `x` tiles along it (in tiles).
func line_point(x: float) -> Vector2:
	return Vector2(at, x) if plane == Axis.I else Vector2(x, at)


## Builds the panels and slices into `entities` (called once by Level, in the
## same order on every machine, so their indexes match for the network).
func build(entities: Node, lot: Vector2i) -> Array[WallPanel]:
	var out: Array[WallPanel] = []
	var k := 0
	for piece: Array in pieces():
		var a: float = piece[0]
		var b: float = piece[1]
		var n := maxi(1, ceili(b - a - 0.001))
		var step := (b - a) / n
		for m in n:
			var pa := a + m * step
			var pb := pa + step
			var panel := WallPanel.new()
			panel.name = "Wall_%s_%d" % [name, k]
			panel.setup(self, pa, pb, int(piece[2]), lot)
			entities.add_child(panel)
			# Two half slices, drawn and depth-sorted separately (see WallSlice).
			for h in 2:
				var slice := WallSlice.new()
				slice.name = "WallSlice_%s_%d_%d" % [name, k, h]
				var sa := pa + step * 0.5 * h
				slice.setup(panel, sa, sa + step * 0.5, h == 0 and is_door_edge(pa), h == 1 and is_door_edge(pb))
				entities.add_child(slice)
				panel.slices.append(slice)
			out.append(panel)
			k += 1
	return out


# ================================================================ editor

func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	for piece: Array in pieces():
		var r := tile_rect(piece[0], piece[1])
		var c: Color = Color("a09a92") if int(piece[2]) == Surface.STONE else face_color
		draw_colored_polygon(_rect_poly(r), c)
		draw_polyline(_rect_poly(r) + PackedVector2Array([Iso.tile_to_local(r.position)]), Color("3b2a30"), 1.0)
	for d in doors:
		var r := tile_rect(d.x, d.y)
		draw_polyline(_rect_poly(r) + PackedVector2Array([Iso.tile_to_local(r.position)]), Color(1, 1, 1, 0.6), 1.0)


static func _rect_poly(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([Iso.tile_to_local(r.position), Iso.tile_to_local(Vector2(r.end.x, r.position.y)),
		Iso.tile_to_local(r.end), Iso.tile_to_local(Vector2(r.position.x, r.end.y))])


func _get_configuration_warnings() -> PackedStringArray:
	var out := PackedStringArray()
	for d in doors:
		if d.y - d.x < 2.0 - 0.01:
			out.append("Doorway %s is narrower than 2 tiles: bots and people will jam in it." % d)
	if to <= from:
		out.append("'to' must be past 'from'.")
	return out
