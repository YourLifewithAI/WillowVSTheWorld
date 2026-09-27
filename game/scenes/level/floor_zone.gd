@tool
class_name FloorZone
extends Node2D
## A patch of different flooring painted over the room's floor: kitchen
## tiles, a carpeted den, a rug. Keep this node at the level's origin and set
## `area` in tiles (position = start i/j, size = width/depth).

enum Style { WOOD, TILES, CARPET, RUG }

@export var area := Rect2(0, 0, 4, 4):
	set(v):
		area = v
		queue_redraw()
@export var style: Style = Style.TILES:
	set(v):
		style = v
		queue_redraw()
## TILES alternates the first two colours; CARPET and RUG use the first as the
## base and the last for flecks / the border.
@export var colors: Array[Color] = [Color("f4f1ea"), Color("c9d8e8")]:
	set(v):
		colors = v
		queue_redraw()
## For a whole room's floor: its name ("Kitchen"), used by the feed and bots.
@export var room_name := ""


func _ready() -> void:
	z_index = -9


func _draw() -> void:
	if colors.is_empty():
		return
	if style == Style.RUG:
		var border := Rect2(area.position, area.size)
		_quad(border, colors[colors.size() - 1])
		_quad(border.grow(-0.2), colors[0])
		_quad(border.grow(-0.45), colors[colors.size() - 1].lightened(0.3))
		_quad(border.grow(-0.55), colors[0])
		return
	Room.draw_floor(self, area, int(style), colors)
	# Threshold strip so the edge reads as a change of flooring.
	var pts := PackedVector2Array([
		Iso.tile_to_local(area.position), Iso.tile_to_local(Vector2(area.end.x, area.position.y)),
		Iso.tile_to_local(area.end), Iso.tile_to_local(Vector2(area.position.x, area.end.y)),
		Iso.tile_to_local(area.position)])
	draw_polyline(pts, Color(0, 0, 0, 0.18), 1.0)


func _quad(r: Rect2, c: Color) -> void:
	draw_colored_polygon(PackedVector2Array([
		Iso.tile_to_local(r.position), Iso.tile_to_local(Vector2(r.end.x, r.position.y)),
		Iso.tile_to_local(r.end), Iso.tile_to_local(Vector2(r.position.x, r.end.y))]), c)
