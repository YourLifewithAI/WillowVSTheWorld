@tool
class_name BaseZone
extends Node2D
## A rug on the floor. For a team base: carry the remote here to score.
## For the remote's home spot (team = -1): where the remote starts, and where
## it must be put back during cleanup.

@export_range(-1, 1) var team := 0:
	set(v):
		team = v
		queue_redraw()
## Radius on the floor, in floor pixels.
@export var radius := 34.0:
	set(v):
		radius = v
		queue_redraw()

var pulse := 0.0


func _ready() -> void:
	z_index = -5


func contains(p: Vector2) -> bool:
	return Iso.fdist(position, p) <= radius


## Evenly spaced spawn positions inside the rug (in the parent's coordinates).
func spawn_point(slot: int, count: int) -> Vector2:
	var a := TAU * float(slot) / float(max(count, 1)) + 0.3
	return position + Iso.to_screen(Vector2(cos(a), sin(a)) * radius * 0.55)


func _process(delta: float) -> void:
	if pulse > 0.0:
		pulse = max(0.0, pulse - delta)
		queue_redraw()


func _draw() -> void:
	if team < 0:
		_draw_home_rug()
		return
	var col: Color = Roster.TEAM_COLORS[team]
	var r := radius + pulse * 12.0
	draw_colored_polygon(Iso.ellipse(r + 2, 32), col.darkened(0.35))
	draw_colored_polygon(Iso.ellipse(r, 32), col.lightened(0.25))
	draw_colored_polygon(Iso.ellipse(r * 0.8, 32), col.lightened(0.45))
	var ring := Iso.ellipse(r * 0.9, 32)
	ring.append(ring[0])
	draw_polyline(ring, col.darkened(0.1), 1.0)
	if team == Roster.Team.PETS:
		_draw_paw(Vector2(0, 0), col.darkened(0.25))
	else:
		_draw_bolt(Vector2(0, 0), col.darkened(0.3))


func _draw_home_rug() -> void:
	draw_colored_polygon(Iso.ellipse(radius * 2.4 + 2, 40), Color("9a5b6f"))
	draw_colored_polygon(Iso.ellipse(radius * 2.4, 40), Color("d98ba0"))
	draw_colored_polygon(Iso.ellipse(radius * 1.8, 40), Color("f2b8c6"))
	draw_colored_polygon(Iso.ellipse(radius * 1.2, 40), Color("d98ba0"))
	var ring := Iso.ellipse(radius, 24)
	ring.append(ring[0])
	draw_polyline(ring, Color("fff6ea"), 1.0)


func _draw_paw(c: Vector2, col: Color) -> void:
	draw_colored_polygon(Transform2D(0, c + Vector2(0, 2)) * Iso.ellipse(6, 16), col)
	for k in 4:
		var off := Vector2(-7.5 + k * 5.0, -2.5 - (1.5 if k == 1 or k == 2 else 0.0))
		draw_colored_polygon(Transform2D(0, c + off) * Iso.ellipse(2.2, 10), col)


func _draw_bolt(c: Vector2, col: Color) -> void:
	var pts := PackedVector2Array([Vector2(3, -6), Vector2(-4, 1), Vector2(0, 1), Vector2(-3, 6), Vector2(5, -1), Vector2(1, -1)])
	for k in pts.size():
		pts[k] = c + Vector2(pts[k].x * 1.2, pts[k].y * 0.8)
	draw_colored_polygon(pts, col)
