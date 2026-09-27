class_name WallPanel
extends Furniture
## One tile (or less) of an interior wall, built by WallRun. It is Furniture,
## so hp, cracks, wrecking, rebuilding, the navigation bake and the network
## sync all work as for a couch. It draws nothing itself: its two WallSlices
## do (and the Furniture overlay still shows the rebuild marker in cleanup).
##
## Walls sit on their own physics layer (8): walkers and Zoomba bump into
## them, flyers pass over (they're drawn above the cut), and shots, blasts and
## close-up moves check Level.wall_between before they reach past one.

const LAYER := 8
## Hits below this do nothing to a painted wall: only the heavy hitters break
## through (see Roster: demolition 50 and up).
const MIN_HIT := 50.0
const DRYWALL_HP := 150.0
## Half the wall's thickness, in floor pixels.
const HALF_THICK := WallRun.THICKNESS * 0.5 * 22.63

var run: WallRun
## Where along the run this panel starts and ends (tiles).
var a := 0.0
var b := 0.0
var surface := 0
## Its floor area in tiles (position = (i, j)).
var rect := Rect2()
var slices: Array[WallSlice] = []
var _solid_rect := Rect2()


func setup(wall: WallRun, start: float, end: float, mat: int, lot: Vector2i) -> void:
	run = wall
	a = start
	b = end
	surface = mat
	rect = wall.tile_rect(start, end)
	style = Style.HOUSE_WALL
	size = rect.size
	position = Iso.tile_to_local(rect.get_center())
	color = wall.face_color
	footprint_scale = 1.0
	collision_layer_value = LAYER
	if mat == WallRun.Surface.DRYWALL:
		sturdiness = DRYWALL_HP
		min_hit = MIN_HIT
	else:
		sturdiness = 0.0  # stone and outside walls never break
	# Collision stops a little short of the room's shell (so the navigation
	# outline never touches the floor's edge), but the wall is drawn right up to it.
	var i0 := maxf(rect.position.x, WallRun.SHELL_INSET)
	var j0 := maxf(rect.position.y, WallRun.SHELL_INSET)
	var i1 := minf(rect.end.x, lot.x - WallRun.SHELL_INSET)
	var j1 := minf(rect.end.y, lot.y - WallRun.SHELL_INSET)
	_solid_rect = Rect2(i0, j0, i1 - i0, j1 - j0)


func _ready() -> void:
	super._ready()
	if _poly:
		_poly.polygon = solid_polygon(Vector2.ZERO)


## The solid footprint, relative to this panel (grown by `grow` tiles each way).
func solid_polygon(grow: Vector2) -> PackedVector2Array:
	var r := _solid_rect.grow_individual(grow.x, grow.y, grow.x, grow.y)
	var c := rect.get_center()
	return PackedVector2Array([Iso.tile_to_local(r.position - c), Iso.tile_to_local(Vector2(r.end.x, r.position.y) - c),
		Iso.tile_to_local(r.end - c), Iso.tile_to_local(Vector2(r.position.x, r.end.y) - c)])


## Its solid floor area in tiles (a little short of the room's shell).
func solid_rect() -> Rect2:
	return _solid_rect


## The ends of the wall's centre line along this panel (level coordinates).
func line() -> PackedVector2Array:
	return PackedVector2Array([Iso.tile_to_local(run.line_point(a)), Iso.tile_to_local(run.line_point(b))])


## Floor pixels from `p` to the wall's surface.
func distance_to(p: Vector2) -> float:
	var l := line()
	return maxf(0.0, Iso.segment_fdist(p, l[0], l[1]) - HALF_THICK)


func reach() -> float:
	return maxf(size.x, size.y) * 11.3


## A hole is mended in three steps: the Claw lowers a new panel, Unit-7 tapes
## it, Kiwi paints it. After the first it's solid again (step > 0 while the
## rest is still to do). A crack just needs Unit-7.
func chain() -> Array[int]:
	if wrecked or step > 0:
		return [Chores.Chore.LIFT, Chores.Chore.REPAIR, Chores.Chore.HIGH]
	if cracked():
		return [Chores.Chore.REPAIR]
	return []


func step_time(_chore: int) -> float:
	return 2.0 if wrecked or step > 0 else 1.0


func step_weight(chore: int) -> float:
	if not wrecked and step == 0:
		return 1.0
	match chore:
		Chores.Chore.LIFT:
			return 1.5
		Chores.Chore.REPAIR:
			return 1.75
	return 2.4


func shed_budget() -> int:
	return 0


func breakable() -> bool:
	return surface == WallRun.Surface.DRYWALL


## What the feed calls it.
func label() -> String:
	return run.label


func apply_state(hp_frac: float, is_wrecked: bool, progress: float, new_helpers: int, new_step: int = 0) -> void:
	super.apply_state(hp_frac, is_wrecked, progress, new_helpers, new_step)
	for s in slices:
		s.queue_redraw()


func _draw() -> void:
	pass  # the slices draw the wall
