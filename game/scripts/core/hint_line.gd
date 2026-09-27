class_name HintLine
extends Control
## One line of text with pictures of buttons in it, drawn for one seat's
## controller or keyboard (see Glyphs): "{special} Big Bark  ready!" shows the
## special button, then the words. Tokens: {attack} {special} {interact}
## {dash} {gag} {menu} {move} {aim}.

var seat := 0:
	set(v):
		if v != seat:
			seat = v
			_changed()
var text := "":
	set(v):
		if v != text:
			text = v
			_changed()
var font_size := 7
var color := Color.WHITE
## Lights the button that matters (the seat's own colour, say).
var accent := Color("ffd84d")
var outline := true
var centered := false
## How tall the button pictures are.
var glyph_h := 9.0
## Keep to this width, trimming the end (0: as wide as the text).
var fixed_width := 0.0


func _init(p_seat: int = 0, p_text: String = "", p_size: int = 7, p_color: Color = Color.WHITE) -> void:
	seat = p_seat
	text = p_text
	font_size = p_size
	color = p_color
	glyph_h = maxf(8.0, p_size + (4.0 if p_size >= 7 else 2.0))
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true


func _changed() -> void:
	update_minimum_size()
	queue_redraw()


func _get_minimum_size() -> Vector2:
	var font := get_theme_default_font()
	var h := maxf(glyph_h, font.get_height(font_size))
	return Vector2(fixed_width if fixed_width > 0.0 else _measure(font), h)


## The words and button pictures, in order: [is_button, text or glyph].
func _parts() -> Array:
	var out := []
	var rest := text
	while true:
		var i := rest.find("{")
		var j := rest.find("}", i)
		if i < 0 or j < 0:
			break
		if i > 0:
			out.append([false, rest.substr(0, i)])
		out.append([true, Glyphs.of(seat, rest.substr(i + 1, j - i - 1))])
		rest = rest.substr(j + 1)
	if rest != "":
		out.append([false, rest])
	return out


func _measure(font: Font) -> float:
	var w := 0.0
	for part: Array in _parts():
		if part[0]:
			w += Glyphs.width(part[1], glyph_h, font) + 2.0
		else:
			w += font.get_string_size(part[1], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	return ceilf(w + (2.0 if outline else 0.0))


func _draw() -> void:
	var font := get_theme_default_font()
	var x := 1.0 if outline else 0.0
	if centered:
		x = floorf((size.x - _measure(font)) * 0.5) + x
	var mid := floorf(size.y * 0.5)
	var base := roundf(mid + (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5)
	for part: Array in _parts():
		if part[0]:
			x += Glyphs.draw(self, Vector2(x, mid), part[1], glyph_h, accent, font) + 2.0
			continue
		var t: String = part[1]
		if outline:
			draw_string_outline(font, Vector2(x, base), t, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 3, Glyphs.INK)
		draw_string(font, Vector2(x, base), t, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
		x += font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
