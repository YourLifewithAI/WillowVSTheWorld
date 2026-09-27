class_name JobBadge
extends RefCounted
## The marker over a cleanup job: a little disc with the face of whoever's job
## it is (see Chores), so nobody has to read anything from the sofa.
##   - The ring is the colour of the person on this screen who plays that
##     character (P1 red, P2 blue...): "my face, my colour" means "mine".
##     White for bots and players on other machines.
##   - A grey hand: nobody in the house owns this chore right now, so anyone
##     does it at half speed. If its owner has wandered off, their face shows
##     small and faded beside it.
##   - It only bobs for the people whose job it is.
##   - Two dots underneath: helpers need a second pair of hands (heavy and
##     high jobs, while their owner is about). They fill as helpers arrive.
##   - A repair chain shows the faces of the steps still to come, small and faded.
##   - The progress bar is green while the owner works it, grey for helpers.

const RADIUS := 6.5
const OUTLINE := Color("3b2a30")
const GREY := Color("8a8a8a")
const GREEN := Color("8ff0a4")
const HELP_GREY := Color("d8d8d8")


static func draw(canvas: CanvasItem, at: Vector2, arena: Match, chore: int, progress: float, helpers: int,
		owner_working: bool, t: float, later: Array = []) -> void:
	var owners: Array = arena.chore_owners.get(chore, [])
	var mine := arena.local_owner_colors(chore)
	var bob := sin(t * 5.0) * 1.5 if not mine.is_empty() else 0.0
	var c := at + Vector2(0, round(bob) - 6)
	canvas.draw_circle(c, RADIUS + 1.0, OUTLINE)
	if owners.is_empty():
		canvas.draw_circle(c, RADIUS, GREY)
	elif mine.is_empty():
		canvas.draw_circle(c, RADIUS, Color.WHITE)
	else:
		# One arc per local owner (two P-colours for two people playing the same character).
		var n := mine.size()
		for k in n:
			canvas.draw_arc(c, RADIUS - 0.5, TAU * k / n - PI * 0.5, TAU * (k + 1) / n - PI * 0.5, 12, mine[k], 2.0)
	var tex := Roster.texture(arena.chore_face(chore))
	if tex:
		canvas.draw_texture(tex, (c - tex.get_size() * 0.5).round())
	var x := RADIUS + 2.0
	# An owner who's wandered off: their face, faded, next to the grey hand.
	if owners.is_empty() and not arena.idle_owners.get(chore, []).is_empty():
		var ghost := Roster.texture(Chores.face(chore))
		if ghost:
			canvas.draw_texture_rect(ghost, Rect2(c + Vector2(x, -1), Vector2(6, 6)), false, Color(1, 1, 1, 0.45))
			x += 7.0
	# The steps still to come.
	for step: int in later:
		var small := Roster.texture(arena.chore_face(step))
		if small:
			canvas.draw_texture_rect(small, Rect2(c + Vector2(x, -1), Vector2(6, 6)), false, Color(1, 1, 1, 0.55))
		x += 7.0
	# A second pair of hands needed?
	var two := Chores.needs_two(chore, arena.chore_owners) and mine.is_empty()
	if two:
		for k in 2:
			var dot := c + Vector2(-2.5 + k * 5.0, RADIUS + 3.0)
			canvas.draw_circle(dot, 1.6, OUTLINE)
			canvas.draw_circle(dot, 1.0, GREEN if k < helpers else Color("fffdf5"))
	if progress > 0.0:
		var bar := Rect2(c + Vector2(-8, RADIUS + (6.0 if two else 3.0)), Vector2(16, 2))
		canvas.draw_rect(bar.grow(1), OUTLINE)
		canvas.draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(progress, 0.0, 1.0), bar.size.y)),
			GREEN if owner_working else HELP_GREY)
