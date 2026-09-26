@tool
class_name Furniture
extends StaticBody2D
## Solid furniture drawn as simple isometric boxes, so it can be resized and
## recoloured right in the inspector. The node's origin is the centre of its
## footprint on the floor. Walkers bump into it; flyers pass over it.
##
## Most furniture can be wrecked during the war (weapons, explosions, and
## characters being launched into it) and has to be rebuilt during cleanup.
## The host owns its health; every peer mirrors it through apply_state().

enum Style { BOX, ARMCHAIR, COUCH, TABLE, TV, CAT_TREE, DOCK, BED, COUNTER, STOVE, FRIDGE, DESK, BEANBAG, WALL, PET_BED }
enum Detail { NONE, SINK, BURNERS }

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
## Swap the i/j axes (turns chairs, couches and beds a quarter turn).
@export var mirror := false:
	set(v):
		mirror = v
		queue_redraw()
## Turn the piece around (a couch with its back to the wall instead of the room).
@export var flip := false:
	set(v):
		flip = v
		queue_redraw()
## Extra detail on counters.
@export var detail: Detail = Detail.NONE:
	set(v):
		detail = v
		queue_redraw()
@export var solid := true
## How much punishment it takes before it's wrecked.
## -1 picks a value for the style; 0 makes it indestructible.
@export var sturdiness := -1.0

## For Style.TV: -1 = off, otherwise the team whose show is on.
var channel := -1:
	set(v):
		channel = v
		queue_redraw()

const OUTLINE := Color("3b2a30")
const STURDINESS := {
	Style.BOX: 40.0, Style.ARMCHAIR: 55.0, Style.COUCH: 80.0, Style.TABLE: 40.0, Style.TV: 0.0,
	Style.CAT_TREE: 0.0, Style.DOCK: 0.0, Style.BED: 80.0, Style.COUNTER: 90.0, Style.STOVE: 0.0,
	Style.FRIDGE: 110.0, Style.DESK: 45.0, Style.BEANBAG: 20.0, Style.WALL: 60.0, Style.PET_BED: 0.0,
}

var index := -1
var max_hp := 0.0
var hp := 0.0
var wrecked := false
## 0..1 progress of putting it back together during cleanup.
var rebuild := 0.0
var helpers := 0

var _boxes: Array[Dictionary] = []
var _poly: CollisionPolygon2D
var _overlay: Node2D
var _t := 0.0


func _ready() -> void:
	collision_layer = 2
	collision_mask = 0
	max_hp = sturdiness if sturdiness >= 0.0 else float(STURDINESS.get(style, 60.0))
	hp = max_hp
	if Engine.is_editor_hint():
		return
	if solid:
		_poly = CollisionPolygon2D.new()
		_poly.polygon = Iso.footprint(size * 0.92)
		add_child(_poly)
	_overlay = Node2D.new()
	_overlay.z_index = 20
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)


func can_be_damaged() -> bool:
	return solid and max_hp > 0.0 and not wrecked


## Roughly how far the footprint reaches from its centre, in floor pixels.
func reach() -> float:
	return maxf(size.x, size.y) * 11.3


## How much a wreck counts against the house's tidiness.
func weight() -> float:
	return 2.0 + size.x * size.y


func rebuild_time() -> float:
	return 4.0 + size.x * size.y * 1.5


func required_lift() -> int:
	return 2


## Mirrors the host's view: health fraction, wrecked or not, rebuild progress.
func apply_state(hp_frac: float, is_wrecked: bool, progress: float, new_helpers: int) -> void:
	hp = hp_frac * max_hp
	rebuild = progress
	helpers = new_helpers
	if is_wrecked != wrecked:
		wrecked = is_wrecked
		if _poly:
			_poly.set_deferred("disabled", wrecked)
	queue_redraw()
	if _overlay:
		_overlay.queue_redraw()


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not wrecked:
		return
	_t += delta
	_overlay.queue_redraw()


func _draw_overlay() -> void:
	if not wrecked or Match.current == null or Match.current.phase != Match.Phase.CLEANUP:
		return
	var top := Vector2(0, -18)
	var bob := sin(_t * 5.0) * 1.5
	var c := Color("ffd84d") if rebuild <= 0.0 else Color("8ff0a4")
	_overlay.draw_colored_polygon(PackedVector2Array([top + Vector2(-4, bob - 5), top + Vector2(4, bob - 5), top + Vector2(0, bob)]), c)
	if helpers < required_lift():
		_overlay.draw_string(ThemeDB.fallback_font, top + Vector2(-5, bob - 7), "x2", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color.WHITE)
	if rebuild > 0.0:
		var bar := Rect2(top + Vector2(-10, 2), Vector2(20, 3))
		_overlay.draw_rect(bar.grow(1), OUTLINE)
		_overlay.draw_rect(Rect2(bar.position, Vector2(bar.size.x * rebuild, bar.size.y)), Color("8ff0a4"))


## This piece's own (i, j) axes -> the room's tile axes, honouring flip/mirror.
func _world(i: float, j: float) -> Vector2:
	var p := Vector2(-i, -j) if flip else Vector2(i, j)
	return Vector2(p.y, p.x) if mirror else p


## A point on (or above, by z pixels) the floor, in own coordinates.
func _pt(i: float, j: float, z: float = 0.0) -> Vector2:
	return Iso.tile_to_local(_world(i, j)) + Vector2(0, -z)


func _draw() -> void:
	var w := size.y if mirror else size.x
	var d := size.x if mirror else size.y
	_boxes.clear()
	if wrecked:
		_draw_rubble(w, d)
		return
	match style:
		Style.BOX:
			_box(Vector2.ZERO, Vector2(w, d), 0, height, color)
		Style.WALL:
			_box(Vector2.ZERO, Vector2(w, d), 0, height, color)
			_box(Vector2.ZERO, Vector2(w + 0.04, d + 0.04), 0, 3, Color("fff8ef"))
		Style.ARMCHAIR:
			_box(Vector2.ZERO, Vector2(w, d), 0, height * 0.55, color)
			_box(Vector2(-w * 0.36, 0), Vector2(w * 0.28, d), height * 0.55, height * 1.35, color)
			_box(Vector2(w * 0.12, -d * 0.4), Vector2(w * 0.76, d * 0.2), height * 0.55, height * 0.95, color.darkened(0.05))
			_box(Vector2(w * 0.12, d * 0.4), Vector2(w * 0.76, d * 0.2), height * 0.55, height * 0.95, color.darkened(0.05))
			_box(Vector2(w * 0.08, 0), Vector2(w * 0.44, d * 0.58), height * 0.55, height * 0.7, accent)
		Style.COUCH:
			_box(Vector2.ZERO, Vector2(w, d), 0, height * 0.6, color)
			_box(Vector2(0, d * 0.34), Vector2(w, d * 0.32), height * 0.6, height * 1.3, color.darkened(0.06))
			_box(Vector2(-w * 0.45, -d * 0.16), Vector2(w * 0.1, d * 0.68), height * 0.6, height * 0.95, color.lightened(0.05))
			_box(Vector2(w * 0.45, -d * 0.16), Vector2(w * 0.1, d * 0.68), height * 0.6, height * 0.95, color.lightened(0.05))
		Style.TABLE, Style.DESK:
			for sx in [-1.0, 1.0]:
				for sy in [-1.0, 1.0]:
					_box(Vector2(sx * w * 0.38, sy * d * 0.38), Vector2(0.12, 0.12), 0, height - 3, color.darkened(0.25))
			_box(Vector2.ZERO, Vector2(w, d), height - 3, height, color)
			if style == Style.TABLE:
				_box(Vector2(w * 0.1, -d * 0.1), Vector2(w * 0.3, d * 0.22), height, height + 1, accent)
			else:
				_box(Vector2(w * 0.1, d * 0.05), Vector2(w * 0.2, d * 0.4), height, height + 1, Color("3b3b44"))
		Style.TV:
			_box(Vector2.ZERO, Vector2(w, d), 0, height, color)
		Style.CAT_TREE:
			_box(Vector2.ZERO, Vector2(w, d), 0, 5, color)
			_box(Vector2(-w * 0.2, -d * 0.2), Vector2(0.28, 0.28), 5, height * 0.55, Color("e8d3a8"))
			_box(Vector2(-w * 0.1, -d * 0.1), Vector2(w * 0.8, d * 0.8), height * 0.55, height * 0.55 + 4, color)
			_box(Vector2(-w * 0.25, -d * 0.25), Vector2(0.24, 0.24), height * 0.55 + 4, height - 4, Color("e8d3a8"))
			_box(Vector2(-w * 0.25, -d * 0.25), Vector2(w * 0.6, d * 0.6), height - 4, height, color)
		Style.DOCK:
			_box(Vector2.ZERO, Vector2(w, d), 0, 4, color.darkened(0.3))
			_box(Vector2(-w * 0.35, -d * 0.35), Vector2(w * 0.3, d * 0.3), 4, height, color)
			_box(Vector2(w * 0.15, d * 0.15), Vector2(w * 0.5, d * 0.5), 4, 5, accent.darkened(0.2))
		Style.BED:
			_box(Vector2(-w * 0.47, 0), Vector2(w * 0.06, d), 0, height * 1.6, color.darkened(0.1))
			_box(Vector2(w * 0.03, 0), Vector2(w * 0.94, d), 0, height * 0.45, color)
			_box(Vector2(w * 0.03, 0), Vector2(w * 0.9, d * 0.92), height * 0.45, height * 0.7, Color("fff6ea"))
			_box(Vector2(-w * 0.32, 0), Vector2(w * 0.16, d * 0.7), height * 0.7, height * 0.9, Color("ffffff"))
			_box(Vector2(w * 0.16, 0), Vector2(w * 0.64, d * 0.96), height * 0.7, height * 0.8, accent)
		Style.COUNTER:
			_box(Vector2.ZERO, Vector2(w, d), 0, height - 2, color)
			_box(Vector2.ZERO, Vector2(w + 0.04, d + 0.06), height - 2, height, accent)
		Style.STOVE:
			_box(Vector2.ZERO, Vector2(w * 0.8, d * 0.8), 0, height, Color("3b3b44"))
			_box(Vector2.ZERO, Vector2(w * 0.9, d * 0.9), height, height + 2, Color("2b2b33"))
			_box(Vector2(-w * 0.15, -d * 0.15), Vector2(0.25, 0.25), height + 2, 60, Color("4a4a55"))
		Style.FRIDGE:
			_box(Vector2.ZERO, Vector2(w, d), 0, height, color)
		Style.BEANBAG, Style.PET_BED:
			pass  # Drawn in _draw_details.
	_flush_boxes()
	_draw_details(w, d)
	if max_hp > 0.0 and hp < max_hp * 0.66:
		_draw_cracks(w, d)


## What's left after the war: a heap of broken pieces.
func _draw_rubble(w: float, d: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(name)
	draw_colored_polygon(Iso.footprint(size * 0.9), Color(0, 0, 0, 0.18))
	for k in 5:
		var at := Vector2(rng.randf_range(-0.32, 0.32) * w, rng.randf_range(-0.32, 0.32) * d)
		var piece := Vector2(rng.randf_range(0.18, 0.4) * w, rng.randf_range(0.18, 0.4) * d)
		var tone := color.darkened(rng.randf_range(0.05, 0.3)) if k != 2 else accent.darkened(0.2)
		_box(at, piece, 0.0, rng.randf_range(2.0, 5.0), tone)
	_flush_boxes()
	for k in 4:
		var p := _pt(rng.randf_range(-0.4, 0.4) * w, rng.randf_range(-0.4, 0.4) * d, 1.0)
		draw_line(p, p + Vector2(rng.randf_range(-4, 4), rng.randf_range(-3, 1)), color.lightened(0.3), 1.0)


## Cracks that spread as it takes damage.
func _draw_cracks(w: float, d: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(name) + 7
	var count := 1 if hp > max_hp * 0.33 else 3
	for k in count:
		var p := _pt(rng.randf_range(-0.3, 0.3) * w, rng.randf_range(-0.3, 0.3) * d, height * rng.randf_range(0.5, 1.0))
		var pts := PackedVector2Array([p])
		for s in 3:
			p += Vector2(rng.randf_range(-3, 3), rng.randf_range(1, 3))
			pts.append(p)
		draw_polyline(pts, Color(0.1, 0.07, 0.09, 0.75), 1.0)


func _draw_details(w: float, d: float) -> void:
	match style:
		Style.TV:
			_draw_tv(Vector2(0, -height))
		Style.CAT_TREE:
			var toy := _pt(w * 0.3, d * 0.3, height * 0.55 + 9)
			draw_line(toy + Vector2(0, -2), toy + Vector2(0, 5), Color("fff6ea"))
			draw_circle(toy + Vector2(0, 6), 2.0, accent)
		Style.DOCK:
			var glow := _pt(-w * 0.18, -d * 0.18, height * 0.6)
			draw_colored_polygon(PackedVector2Array([glow + Vector2(1, -5), glow + Vector2(-3, 1), glow + Vector2(0, 1), glow + Vector2(-1, 5), glow + Vector2(3, -1), glow + Vector2(0, -1)]), accent)
		Style.COUNTER:
			var top := _pt(0, 0, height)
			if detail == Detail.SINK:
				draw_colored_polygon(Transform2D(0, top) * Iso.ellipse(5.0, 12), Color("8a93a3"))
				draw_colored_polygon(Transform2D(0, top + Vector2(0, 0.5)) * Iso.ellipse(3.5, 12), Color("5a6272"))
			elif detail == Detail.BURNERS:
				for k in 2:
					var b := top + Vector2(-5 + k * 10, 0)
					draw_colored_polygon(Transform2D(0, b) * Iso.ellipse(3.0, 10), Color("2b2b33"))
					draw_arc(b, 2.0, 0, TAU, 10, Color("e05a5a"), 1.0)
		Style.STOVE:
			var fire := _pt(w * 0.4, d * 0.4, height * 0.5)
			draw_rect(Rect2(fire + Vector2(-3, -2), Vector2(6, 4)), Color("ff9a3c"))
			draw_rect(Rect2(fire + Vector2(-2, -1), Vector2(4, 2)), Color("ffd84d"))
		Style.FRIDGE:
			# Freezer line across both visible faces, and a handle.
			var l := _pt(-w / 2.0, d / 2.0, height * 0.66)
			var f := _pt(w / 2.0, d / 2.0, height * 0.66)
			var r := _pt(w / 2.0, -d / 2.0, height * 0.66)
			draw_polyline(PackedVector2Array([l, f, r]), color.darkened(0.35), 1.0)
			var h := _pt(w / 2.0, 0.1, height * 0.5)
			draw_rect(Rect2(h + Vector2(0, -6), Vector2(1, 8)), Color("8a93a3"))
		Style.DESK:
			var mon := _pt(-w * 0.2, -d * 0.1, height)
			draw_rect(Rect2(mon + Vector2(-1, -3), Vector2(2, 3)), OUTLINE)
			var screen := Rect2(mon + Vector2(-9, -15), Vector2(18, 12))
			draw_rect(screen.grow(1), OUTLINE)
			draw_rect(screen, Color("243048"))
			draw_rect(Rect2(screen.position + Vector2(2, 2), Vector2(9, 1)), Color("62f2ff"))
			draw_rect(Rect2(screen.position + Vector2(2, 5), Vector2(12, 1)), Color("8ff0a4"))
			draw_rect(Rect2(screen.position + Vector2(2, 8), Vector2(6, 1)), Color("ffd84d"))
		Style.BEANBAG:
			var r := minf(w, d) * 11.0
			draw_colored_polygon(Transform2D(0, Vector2(0, -1)) * Iso.ellipse(r + 1.0, 20), OUTLINE)
			draw_colored_polygon(Transform2D(0, Vector2(0, -1)) * Iso.ellipse(r, 20), color.darkened(0.2))
			draw_circle(Vector2(0, -r * 0.55), r * 0.75 + 1.0, OUTLINE)
			draw_circle(Vector2(0, -r * 0.55), r * 0.75, color)
			draw_circle(Vector2(-r * 0.25, -r * 0.8), r * 0.25, color.lightened(0.2))
		Style.PET_BED:
			var r := minf(w, d) * 11.0
			draw_colored_polygon(Transform2D(0, Vector2(0, -2)) * Iso.ellipse(r + 1.0, 24), OUTLINE)
			draw_colored_polygon(Transform2D(0, Vector2(0, -2)) * Iso.ellipse(r, 24), color)
			draw_colored_polygon(Transform2D(0, Vector2(0, -1)) * Iso.ellipse(r * 0.68, 24), accent)


## Queues an isometric box. `at` and `box_size` are in tiles along this
## piece's own axes; z0/z1 are heights in pixels.
func _box(at: Vector2, box_size: Vector2, z0: float, z1: float, c: Color) -> void:
	var center := _world(at.x, at.y)
	var ext := box_size * 0.5
	if mirror:
		ext = Vector2(ext.y, ext.x)
	_boxes.append({"min": center - ext, "max": center + ext, "z0": z0, "z1": z1, "c": c, "n": _boxes.size()})


## Draws queued boxes back to front, so stacked and neighbouring parts overlap correctly.
func _flush_boxes() -> void:
	var left := _boxes.duplicate()
	while not left.is_empty():
		var pick := 0
		for a in left.size():
			var blocked := false
			for b in left.size():
				if a != b and _behind(left[b], left[a]):
					blocked = true
					break
			if not blocked:
				pick = a
				break
		_draw_box(left[pick])
		left.remove_at(pick)
	_boxes.clear()


## True if box a has to be drawn before box b.
func _behind(a: Dictionary, b: Dictionary) -> bool:
	if a["z1"] <= b["z0"] and not (b["z1"] <= a["z0"]):
		return true
	if b["z1"] <= a["z0"]:
		return false
	var amin: Vector2 = a["min"]
	var amax: Vector2 = a["max"]
	var bmin: Vector2 = b["min"]
	var bmax: Vector2 = b["max"]
	if amax.x <= bmin.x + 0.001 or amax.y <= bmin.y + 0.001:
		return true
	if bmax.x <= amin.x + 0.001 or bmax.y <= amin.y + 0.001:
		return false
	var da := (amin + amax).x + (amin + amax).y
	var db := (bmin + bmax).x + (bmin + bmax).y
	if not is_equal_approx(da, db):
		return da < db
	return a["n"] < b["n"]


func _draw_box(box: Dictionary) -> void:
	var mn: Vector2 = box["min"]
	var mx: Vector2 = box["max"]
	var c: Color = box["c"]
	var b := Iso.tile_to_local(mn)
	var r := Iso.tile_to_local(Vector2(mx.x, mn.y))
	var f := Iso.tile_to_local(mx)
	var l := Iso.tile_to_local(Vector2(mn.x, mx.y))
	var lo := Vector2(0, -float(box["z0"]))
	var hi := Vector2(0, -float(box["z1"]))
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
