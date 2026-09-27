class_name ChorePanel
extends Control
## The cleanup panel in the top-left corner: how tidy the house is against
## what the parents need (the marks at 60% and 90%), then every chore in play
## as its owner's face and how many of its jobs are left. The grey hand counts
## jobs nobody owns right now. The biggest pile of work pulses (that's where
## help is needed); a finished chore gets a tick. A chore someone on this
## screen owns is underlined in their colour.

const W := 144.0
const ROW := 12.0
const PER_ROW := 4
const STEP := 34.0

var arena: Match
var _t := 0.0


func _init(m: Match) -> void:
	arena = m
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(W, 42)


func _process(delta: float) -> void:
	if visible:
		_t += delta
		queue_redraw()


## [face, jobs left, weight left, chore or -1 for the grey hand], in chore order.
func _entries() -> Array:
	var totals := arena.chore_totals()
	var out: Array = []
	var anyone := [0, 0.0]
	var owned := {}
	for pid: int in arena.specialty:
		owned[arena.specialty[pid]] = true
	for c: int in Chores.Chore.values():
		if c == Chores.Chore.NONE:
			continue
		var t: Array = totals.get(c, [0, 0.0])
		if owned.has(c) and not arena.chore_owners.get(c, []).is_empty():
			out.append([arena.chore_face(c), t[0], t[1], c])
		else:
			anyone[0] += t[0]
			anyone[1] += t[1]
	if anyone[0] > 0:
		out.append(["face_anyone", anyone[0], anyone[1], -1])
	return out


func _draw() -> void:
	var entries := _entries()
	var rows := ceili(entries.size() / float(PER_ROW))
	var h := 16.0 + rows * ROW + 2.0
	custom_minimum_size.y = h
	size.y = h
	draw_style_box(UiTheme.box(Color(0.23, 0.16, 0.19, 0.85), Color("fff4e3"), 6, 1, 0), Rect2(0, 0, W, h))
	var font := get_theme_default_font()
	# How tidy, against the parents' marks.
	var tidy := arena.tidiness()
	draw_string(font, Vector2(5, 11), "TIDY", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color.WHITE)
	var bar := Rect2(28, 5, 110, 6)
	draw_rect(bar.grow(1), UiTheme.INK)
	var fill := Color("8ff0a4") if tidy >= Match.TIDY_PASS else Color("ffb347")
	draw_rect(Rect2(bar.position, Vector2(roundf(bar.size.x * tidy), bar.size.y)), fill)
	for mark: float in [Match.TIDY_PASS, Match.TIDY_SPOTLESS]:
		var x := roundf(bar.position.x + bar.size.x * mark)
		draw_line(Vector2(x, bar.position.y - 2), Vector2(x, bar.end.y + 1), Color("ffd84d") if mark < 0.8 else Color.WHITE, 1.0)
	# Every chore's face and what's left of it. The biggest one pulses.
	var biggest := -1
	var most := 0.0
	for k in entries.size():
		if entries[k][2] > most:
			most = entries[k][2]
			biggest = k
	for k in entries.size():
		var e: Array = entries[k]
		var at := Vector2(5 + (k % PER_ROW) * STEP, 15 + floori(k / float(PER_ROW)) * ROW)
		var tex := Roster.texture(e[0])
		var alpha := 1.0
		if k == biggest and e[1] > 0:
			alpha = 0.6 + 0.4 * sin(_t * 6.0)
		if tex:
			draw_texture(tex, at, Color(1, 1, 1, alpha))
		var c: int = e[3]
		var mine: Array[Color] = []
		if c >= 0:
			mine = arena.local_owner_colors(c)
		if not mine.is_empty():
			draw_line(at + Vector2(0, 12), at + Vector2(11, 12), mine[0], 1.0)
		if e[1] <= 0:
			_tick(at + Vector2(14, 2), Color("8ff0a4"))
		else:
			draw_string(font, at + Vector2(13, 9), str(e[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1, 1, 1, alpha))


func _tick(at: Vector2, col: Color) -> void:
	draw_polyline(PackedVector2Array([at + Vector2(0, 4), at + Vector2(2, 6), at + Vector2(7, 0)]), col, 1.5)
