class_name WarmupPanel
extends Control
## The warm-up's checklist, under the scoreboard: a row per person on this
## screen with every move to try, each as its button (see Glyphs). A move
## lights up (with a tick) once they've done it, and the row ends with whether
## they've said they're ready.

## [what Player.tried calls it, which button, what to call it].
const ITEMS := [["move", "move", "Move"], ["attack", "attack", "Fire"], ["aim", "attack", "Hold to aim"],
	["special", "special", "Special"], ["interact", "interact", "Up close"], ["dash", "dash", "Dash"],
	["gag", "gag", "Super"], ["pass", "interact", "Pass the remote"]]
const ROW := 13.0
const PAD := 5.0
const GLYPH := 9.0
const FONT := 7

var arena: Match
var _t := 0.0


func _init(m: Match) -> void:
	arena = m
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	visible = arena.warmup and arena.phase == Match.Phase.WAR
	if visible:
		_t += delta
		queue_redraw()


func _row_width(font: Font, seat: int) -> float:
	var w := 18.0
	for item: Array in ITEMS:
		w += Glyphs.width(Glyphs.of(seat, item[1]), GLYPH, font) + 2.0
		w += font.get_string_size(item[2], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT).x + 7.0
	return w + font.get_string_size("READY!", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT).x + 4.0


func _draw() -> void:
	var font := get_theme_default_font()
	var locals := arena.local_players()
	if locals.is_empty():
		return
	var w := 0.0
	for p in locals:
		w = maxf(w, _row_width(font, p.seat))
	var h := PAD * 2.0 + ROW * locals.size()
	var x0 := floorf((size.x - w) * 0.5) - PAD
	draw_style_box(UiTheme.box(Color(0.23, 0.16, 0.19, 0.85), Color("fff4e3"), 6, 1, 0), Rect2(x0, 0, w + PAD * 2.0, h))
	var shared := arena.shared_screen()
	for k in locals.size():
		var p: Player = locals[k]
		var mid := PAD + ROW * (k + 0.5)
		var base := roundf(mid + (font.get_ascent(FONT) - font.get_descent(FONT)) * 0.5)
		var x := x0 + PAD
		var col := p.marker_color() if shared else Color("ffd84d")
		draw_string(font, Vector2(x, base), Seats.tag(p.seat) if shared else "You", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT, col)
		x += 18.0
		for item: Array in ITEMS:
			var done: bool = p.tried.has(item[0])
			var g := Glyphs.of(p.seat, item[1])
			var gw := Glyphs.draw(self, Vector2(x, mid), g, GLYPH, col if done else Color(0.6, 0.55, 0.58), font)
			if done:
				var t := Vector2(x + gw - 2.0, mid - 5.0)
				draw_polyline(PackedVector2Array([t, t + Vector2(1.5, 1.5), t + Vector2(4.5, -2.0)]), Color("8ff0a4"), 1.5)
			x += gw + 2.0
			draw_string(font, Vector2(x, base), item[2], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT,
				Color.WHITE if done else Color(1, 1, 1, 0.45))
			x += font.get_string_size(item[2], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT).x + 7.0
		if arena.ready_pids.has(p.pid):
			draw_string(font, Vector2(x, base), "READY!", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT, Color("8ff0a4"))
		else:
			var a := 0.55 + 0.45 * sin(_t * 4.0)
			draw_string(font, Vector2(x, base), "ready?", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT, Color(1, 1, 1, a))
