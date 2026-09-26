class_name Fx
extends Node2D
## Tiny self-deleting effects: swipes, puffs, rings, pop-up text.
## Everything is drawn with primitives, so there are no assets to manage.

enum Kind { SLASH, PUFF, RING, RING_IN, BURST, TEXT, NOTE, GHOST, BOOM, SWING }

var kind: Kind = Kind.PUFF
var life := 0.3
var color := Color.WHITE
var dir := Vector2.RIGHT
var radius := 10.0
var message := ""
var _t := 0.0


static func _make(parent: Node, k: Kind, pos: Vector2, c: Color, lifetime: float) -> Fx:
	var fx := Fx.new()
	fx.kind = k
	fx.position = pos
	fx.color = c
	fx.life = lifetime
	parent.add_child(fx)
	return fx


static func slash(parent: Node, pos: Vector2, facing: Vector2, c: Color) -> void:
	var fx := _make(parent, Kind.SLASH, pos, c, 0.14)
	fx.dir = facing
	fx.z_index = 5


static func puff(parent: Node, pos: Vector2, c: Color) -> void:
	_make(parent, Kind.PUFF, pos, c, 0.3)


static func burst(parent: Node, pos: Vector2, c: Color) -> void:
	var fx := _make(parent, Kind.BURST, pos, c, 0.18)
	fx.z_index = 6


static func ring(parent: Node, pos: Vector2, r: float, c: Color, inward: bool) -> void:
	var fx := _make(parent, Kind.RING_IN if inward else Kind.RING, pos, c, 0.4)
	fx.radius = r
	fx.z_index = -1


static func text(parent: Node, pos: Vector2, msg: String, c: Color) -> void:
	var fx := _make(parent, Kind.TEXT, pos, c, 0.9)
	fx.message = msg
	fx.z_index = 40


## A cartoon explosion (or a splat, for eggs).
static func boom(parent: Node, pos: Vector2, r: float, splat: bool) -> void:
	var fx := _make(parent, Kind.BOOM, pos, Color("fffdf0") if splat else Color("ffb347"), 0.35)
	fx.radius = r
	fx.z_index = 6


## The wide arc of a big melee swing (the wrecking ball).
static func swing(parent: Node, pos: Vector2, facing: Vector2, r: float, c: Color) -> void:
	var fx := _make(parent, Kind.SWING, pos, c, 0.2)
	fx.dir = facing
	fx.radius = r
	fx.z_index = 5


static func note(parent: Node, pos: Vector2) -> void:
	var fx := _make(parent, Kind.NOTE, pos, Color("62f2ff"), 0.8)
	fx.z_index = 20


## A fading copy of a sprite, for dash trails.
static func ghost(parent: Node, source: Sprite2D, global_pos: Vector2) -> void:
	var fx := _make(parent, Kind.GHOST, Vector2.ZERO, Color(1, 1, 1, 0.5), 0.18)
	fx.global_position = global_pos
	var copy := Sprite2D.new()
	copy.texture = source.texture
	copy.centered = source.centered
	copy.offset = source.offset
	copy.flip_h = source.flip_h
	copy.position = source.get_parent().position
	copy.modulate = Color(1, 1, 1, 0.45)
	fx.add_child(copy)


func _process(delta: float) -> void:
	_t += delta
	if _t >= life:
		queue_free()
		return
	if kind == Kind.GHOST:
		modulate.a = 1.0 - _t / life
	queue_redraw()


func _draw() -> void:
	var k := _t / life
	match kind:
		Kind.SLASH:
			var a := Iso.to_screen(dir).angle()
			draw_arc(Vector2.ZERO, 7.0 + k * 3.0, a - 1.1, a + 1.1, 8, Color(color, 1.0 - k), 2.0)
		Kind.PUFF:
			for i in 5:
				var p := Iso.to_screen(Vector2.from_angle(TAU * i / 5.0) * (4.0 + k * 10.0))
				draw_circle(p + Vector2(0, -2), 2.5 * (1.0 - k), Color(color, 0.8 * (1.0 - k)))
		Kind.BURST:
			for i in 6:
				var v := Vector2.from_angle(TAU * i / 6.0 + 0.3)
				draw_line(v * (2.0 + k * 6.0), v * (4.0 + k * 9.0), Color(color, 1.0 - k), 1.0)
		Kind.RING, Kind.RING_IN:
			var r := radius * (k if kind == Kind.RING else 1.0 - k)
			var pts := Iso.ellipse(maxf(r, 1.0), 32)
			pts.append(pts[0])
			draw_polyline(pts, Color(color, 1.0 - k * 0.7), 1.0)
		Kind.TEXT:
			var font := ThemeDB.fallback_font
			var size := 8
			var w := font.get_string_size(message, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
			var p := Vector2(-w / 2.0, -k * 10.0)
			var c := Color(color, 1.0 - maxf(0.0, k - 0.6) / 0.4)
			draw_string_outline(font, p, message, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 2, Color(0.17, 0.11, 0.16, c.a))
			draw_string(font, p, message, HORIZONTAL_ALIGNMENT_LEFT, -1, size, c)
		Kind.BOOM:
			var r := radius * (0.4 + k * 0.8)
			var ring := Iso.ellipse(r, 24)
			ring.append(ring[0])
			draw_polyline(ring, Color(color, 1.0 - k), 2.0)
			draw_circle(Vector2(0, -4 - k * 6.0), radius * 0.45 * (1.0 - k), Color(color, 0.9 * (1.0 - k)))
			draw_circle(Vector2(0, -4 - k * 6.0), radius * 0.25 * (1.0 - k), Color(1, 1, 0.85, 1.0 - k))
			for i in 7:
				var v := Vector2.from_angle(TAU * i / 7.0 + 0.4)
				var p0 := Iso.to_screen(v * r * 0.6) + Vector2(0, -3)
				draw_line(p0, p0 + Iso.to_screen(v * 6.0) + Vector2(0, -3), Color(color, 1.0 - k), 1.0)
		Kind.SWING:
			var a := Iso.to_screen(dir).angle()
			var pts := PackedVector2Array()
			for i in 13:
				var ang := a - 1.75 + 3.5 * i / 12.0
				pts.append(Vector2(cos(ang) * radius, sin(ang) * radius * 0.5 - 6.0))
			draw_polyline(pts, Color(color, 1.0 - k), 3.0)
		Kind.NOTE:
			var p := Vector2(sin(_t * 8.0) * 2.0, -8.0 - k * 14.0)
			var c := Color(color, 1.0 - k)
			draw_line(p, p + Vector2(0, -5), c, 1.0)
			draw_line(p + Vector2(0, -5), p + Vector2(2, -4), c, 1.0)
			draw_circle(p + Vector2(-1, 0), 1.5, c)
