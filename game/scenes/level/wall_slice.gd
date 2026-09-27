class_name WallSlice
extends Node2D
## Half a WallPanel, drawn as a cutaway wall. Walls live in the depth-sorted
## Entities node like everything else, and anything longer than half a tile
## would sort wrongly against someone standing near its end: a body's centre
## can't get closer than ~0.43 tile to a wall's line, and half a slice is 0.25.
##
## When someone this screen can see (or the remote) is in the strip the wall
## hides, the wall fades to let them show through; the baseboard stays, so the
## floor plan never disappears. During cleanup every inside wall is see-through,
## so no mess is ever hidden.

const CUT := Color("5a4048")
const OUTLINE := Color("3b2a30")
const BASEBOARD := Color("fff8ef")
const STONE := Color("a09a92")
## How deep the hidden strip behind a wall is (tiles), and how far past its ends it counts.
const BAND_DEPTH := 1.3
const BAND_SIDES := 0.5
const FADED := 0.35
const XRAY := 0.45

var panel: WallPanel
var rect := Rect2()
var jamb_start := false
var jamb_end := false
var _fade := 1.0
var _target := 1.0
var _check_t := 0.0


func setup(owner_panel: WallPanel, a: float, b: float, door_before: bool, door_after: bool) -> void:
	panel = owner_panel
	rect = panel.run.tile_rect(a, b)
	jamb_start = door_before
	jamb_end = door_after
	position = Iso.tile_to_local(rect.get_center())
	_check_t = randf() * 0.1


func _process(delta: float) -> void:
	_check_t -= delta
	if _check_t <= 0.0:
		_check_t = 0.1
		_target = _wanted_alpha()
	if not is_equal_approx(_fade, _target):
		_fade = move_toward(_fade, _target, delta / 0.12)
		queue_redraw()


func _wanted_alpha() -> float:
	var arena := Match.current
	if arena == null or panel.wrecked:
		return 1.0
	if arena.phase == Match.Phase.CLEANUP:
		return XRAY
	if hides(arena.remote.position):
		return FADED
	for p: Player in arena.players.values():
		if p.seen_here() and hides(p.position):
			return FADED
	return 1.0


## Is `p` (level coordinates) in the strip of floor this slice hides?
func hides(p: Vector2) -> bool:
	var t := Iso.local_to_tile(p)
	var run := panel.run
	var depth: float
	var along: float
	var lo: float
	var hi: float
	if run.plane == WallRun.Axis.I:
		depth = run.at - t.x
		along = t.y
		lo = rect.position.y
		hi = rect.end.y
	else:
		depth = run.at - t.y
		along = t.x
		lo = rect.position.x
		hi = rect.end.x
	return depth > 0.0 and depth < BAND_DEPTH and along > lo - BAND_SIDES and along < hi + BAND_SIDES


# ================================================================ drawing

func _pt(i: float, j: float, z: float = 0.0) -> Vector2:
	return Iso.tile_to_local(Vector2(i, j) - rect.get_center()) + Vector2(0, -z)


func _draw() -> void:
	var i0 := rect.position.x
	var j0 := rect.position.y
	var i1 := rect.end.x
	var j1 := rect.end.y
	var h := WallRun.HEIGHT
	var plane_i := panel.run.plane == WallRun.Axis.I
	var face := STONE if panel.surface == WallRun.Surface.STONE else panel.color
	# Shaded by which way it faces (like the back walls), and a touch darker
	# than the room's own paint so it stands out against it and the floor.
	face = face.darkened(0.16 if plane_i else 0.07)
	if panel.wrecked:
		_draw_hole(i0, j0, i1, j1, face)
		return
	# Being mended: a new grey board, then taped, then primed white, then painted.
	var mending := panel.step
	if mending == 1:
		face = Color("c3c2bb").darkened(0.08 if plane_i else 0.0)
	elif mending == 2:
		face = Color("f4f2ec").darkened(0.08 if plane_i else 0.0)
	var fa := _fade
	# The long face the camera sees (+i for plane I, +j for plane J), and the end.
	var long_face: PackedVector2Array
	var end_face: PackedVector2Array
	if plane_i:
		long_face = PackedVector2Array([_pt(i1, j0), _pt(i1, j1), _pt(i1, j1, h), _pt(i1, j0, h)])
		end_face = PackedVector2Array([_pt(i0, j1), _pt(i1, j1), _pt(i1, j1, h), _pt(i0, j1, h)])
	else:
		long_face = PackedVector2Array([_pt(i0, j1), _pt(i1, j1), _pt(i1, j1, h), _pt(i0, j1, h)])
		end_face = PackedVector2Array([_pt(i1, j0), _pt(i1, j1), _pt(i1, j1, h), _pt(i1, j0, h)])
	draw_colored_polygon(end_face, _a(face.darkened(0.25), fa))
	draw_colored_polygon(long_face, _a(face, fa))
	_draw_material(long_face, fa)
	if mending == 1:
		# Tape seams down the new board.
		for t in [0.1, 0.9]:
			var bottom := long_face[0].lerp(long_face[1], t)
			draw_line(bottom, bottom + Vector2(0, -WallRun.HEIGHT), _a(Color(1, 1, 1, 0.7), fa), 1.0)
	# Where it meets the floor, and the ends of the run: a crisp outline.
	draw_line(long_face[0], long_face[1], OUTLINE, 1.0)
	if _run_end(true):
		draw_line(long_face[0], long_face[3], _a(OUTLINE, fa), 1.0)
	if _run_end(false):
		draw_line(end_face[0], end_face[3], _a(OUTLINE, fa), 1.0)
		draw_line(end_face[1], end_face[2], _a(OUTLINE, fa), 1.0)
	# Baseboard: stays solid when the wall fades.
	var bb: PackedVector2Array
	if plane_i:
		bb = PackedVector2Array([_pt(i1, j0), _pt(i1, j1), _pt(i1, j1, 3), _pt(i1, j0, 3)])
	else:
		bb = PackedVector2Array([_pt(i0, j1), _pt(i1, j1), _pt(i1, j1, 3), _pt(i0, j1, 3)])
	if panel.surface == WallRun.Surface.DRYWALL:
		draw_colored_polygon(bb, BASEBOARD)
	# The cut: a dark cap that says "this wall goes on up to the ceiling".
	var cap := PackedVector2Array([_pt(i0, j0, h), _pt(i1, j0, h), _pt(i1, j1, h), _pt(i0, j1, h)])
	draw_colored_polygon(cap, _a(CUT, fa))
	if plane_i:
		draw_line(_pt(i1, j0, h), _pt(i1, j1, h), _a(CUT.lightened(0.45), fa), 1.0)
		draw_line(_pt(i0, j0, h), _pt(i0, j1, h), _a(OUTLINE, fa), 1.0)
	else:
		draw_line(_pt(i0, j1, h), _pt(i1, j1, h), _a(CUT.lightened(0.45), fa), 1.0)
		draw_line(_pt(i0, j0, h), _pt(i1, j0, h), _a(OUTLINE, fa), 1.0)
	if panel.max_hp > 0.0 and panel.hp < panel.max_hp * 0.66:
		_draw_cracks(long_face, fa)
	# Door frames: white posts, a little taller than the wall, so doorways pop.
	if jamb_start:
		_draw_jamb(_pt(i1, j0) if plane_i else _pt(i0, j1))
	if jamb_end:
		_draw_jamb(_pt(i1, j1))


## Is this the first (or last) slice of a stretch of wall (a door edge or the run's end)?
func _run_end(start: bool) -> bool:
	var along := Vector2(rect.position.y, rect.end.y) if panel.run.plane == WallRun.Axis.I else Vector2(rect.position.x, rect.end.x)
	if start:
		return jamb_start or absf(along.x - panel.run.from) < 0.01
	return jamb_end or absf(along.y - panel.run.to) < 0.01


static func _a(c: Color, alpha: float) -> Color:
	return Color(c.r, c.g, c.b, c.a * alpha)


func _draw_material(face: PackedVector2Array, fa: float) -> void:
	var bl := face[0]
	var br := face[1]
	match panel.surface:
		WallRun.Surface.STONE:
			# Mortar every 4 px, with staggered joints.
			var line := _a(Color(0.3, 0.27, 0.25, 0.5), fa)
			for k in range(1, 5):
				var z := Vector2(0, -4.0 * k)
				draw_line(bl + z, br + z, line, 1.0)
				var off := 0.3 if k % 2 == 0 else 0.7
				var p := bl.lerp(br, off) + z
				draw_line(p, p + Vector2(0, 4), line, 1.0)
		WallRun.Surface.EXTERIOR:
			# Siding.
			var line := _a(Color(0, 0, 0, 0.14), fa)
			for k in range(1, 7):
				var z := Vector2(0, -3.0 * k)
				draw_line(bl + z, br + z, line, 1.0)


func _draw_cracks(face: PackedVector2Array, fa: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(name)
	var count := 1 if panel.hp > panel.max_hp * 0.33 else 2
	for k in count:
		var p := face[0].lerp(face[1], rng.randf_range(0.2, 0.8)) + Vector2(0, -rng.randf_range(8, 16))
		var pts := PackedVector2Array([p])
		for s in 3:
			p += Vector2(rng.randf_range(-2, 2), rng.randf_range(1, 3))
			pts.append(p)
		draw_polyline(pts, _a(Color(0.1, 0.07, 0.09, 0.8), fa), 1.0)


func _draw_jamb(base: Vector2) -> void:
	draw_rect(Rect2(base + Vector2(-1.5, -WallRun.HEIGHT - 5), Vector2(3, WallRun.HEIGHT + 5)), OUTLINE)
	draw_rect(Rect2(base + Vector2(-0.5, -WallRun.HEIGHT - 4), Vector2(1, WallRun.HEIGHT + 4)), BASEBOARD)


## A hole: a jagged stub of wall, two wooden studs and plaster crumbs.
func _draw_hole(i0: float, j0: float, i1: float, j1: float, face: Color) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(name) + 3
	var plane_i := panel.run.plane == WallRun.Axis.I
	var e0 := _pt(i1, j0) if plane_i else _pt(i0, j1)
	var e1 := _pt(i1, j1)
	var stub := PackedVector2Array([e0, e1])
	for k in 5:
		var t := 1.0 - k / 4.0
		stub.append(e0.lerp(e1, t) + Vector2(0, -rng.randf_range(2.0, 5.0)))
	draw_colored_polygon(stub, face.darkened(0.1))
	draw_polyline(stub + PackedVector2Array([e0]), OUTLINE, 1.0)
	for t in [0.3, 0.75]:
		var p := e0.lerp(e1, t)
		draw_rect(Rect2(p + Vector2(-1, -10), Vector2(2, 10)), Color("b5824f"))
		draw_rect(Rect2(p + Vector2(-1, -10), Vector2(2, 1)), Color("8a5a3c"))
	for k in 3:
		var p := e0.lerp(e1, rng.randf()) + Vector2(rng.randf_range(-3, 3), rng.randf_range(0, 3))
		draw_rect(Rect2(p, Vector2(1, 1)), Color(1, 1, 1, 0.9))
