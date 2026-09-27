class_name Pickup
extends Node2D
## Something that popped up on the floor (see Pickups): a bobbing bubble with
## what's inside on show (a power-up, someone else's weapon, or a turbo tool
## with its chore owner's face). The host decides who gets it (see
## Match._tick_pickups); it blinks for its last few seconds, then pops.

var pickup_id := 0
var kind := Pickups.Kind.SNACK
## The weapon's character (Kind.WEAPON) or the chore (Kind.TOOL), as a string.
var arg := ""
var life := Pickups.LIFETIME
var _icon: Texture2D
var _t := 0.0


func setup(id: int, k: int, a: String, pos: Vector2, lifetime: float) -> void:
	pickup_id = id
	kind = k as Pickups.Kind
	arg = a
	life = lifetime
	position = pos
	name = "Pickup_%d" % id
	_icon = Roster.texture(icon_name())


func icon_name() -> String:
	match kind:
		Pickups.Kind.WEAPON:
			return String(Roster.get_char(arg)["weapon"]["sprite"])
		Pickups.Kind.TOOL:
			return Chores.face(int(arg))
	return Pickups.ICONS.get(kind, "pu_treat")


## What the feed calls it ("the Catnip Bazooka", "the Turbo Bag").
func label() -> String:
	match kind:
		Pickups.Kind.WEAPON:
			return "the %s" % Roster.get_char(arg)["weapon"]["name"]
		Pickups.Kind.TOOL:
			return Pickups.TOOLS.get(int(arg), "a tool")
	return Pickups.NAMES.get(kind, "something")


## Who may take it: in cleanup a tool is only for its chore's owner (or anyone,
## if nobody owns that chore right now).
func takeable_by(p: Player, arena: Match) -> bool:
	if p.is_ko or p.captured_by != 0:
		return false
	if kind == Pickups.Kind.TOOL:
		var owners: Array = arena.chore_owners.get(int(arg), [])
		return owners.is_empty() or p.pid in owners
	return true


func _process(delta: float) -> void:
	_t += delta
	life -= delta
	queue_redraw()


func _draw() -> void:
	# Blinks when it's about to pop.
	if life < 3.0 and fmod(_t, 0.3) < 0.12:
		return
	draw_colored_polygon(Iso.ellipse(6.0, 12), Color(0, 0, 0, 0.2))
	var c := Vector2(0, -12 + round(sin(_t * 3.0) * 2.0))
	var ring: Color = Pickups.COLORS.get(kind, Color.WHITE)
	draw_circle(c, 9.0, Color("3b2a30"))
	draw_circle(c, 8.0, ring)
	draw_circle(c, 7.0, Color(1, 1, 1, 0.85))
	# A glint going round.
	var g := c + Vector2.from_angle(_t * 2.5) * 6.0
	draw_circle(g, 1.0, Color.WHITE)
	if _icon:
		var s := _icon.get_size()
		var k := minf(1.0, 12.0 / maxf(s.x, s.y))
		var size := (s * k).round()
		draw_texture_rect(_icon, Rect2((c - size * 0.5).round(), size), false)
	if kind == Pickups.Kind.TOOL:
		# A little spanner: it's a tool, not a job.
		var w := c + Vector2(5, 4)
		draw_line(w, w + Vector2(3, 3), Color("3b2a30"), 2.0)
		draw_circle(w, 1.8, Color("3b2a30"))
		draw_circle(w, 0.9, ring)
