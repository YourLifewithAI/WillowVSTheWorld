class_name UiTheme
extends RefCounted
## The cozy look shared by the menus and the HUD: warm cream panels, chunky
## rounded buttons, dark cocoa text.

const INK := Color("3b2a30")
const CREAM := Color("fff4e3")
const PEACH := Color("ffd9b8")
const COCOA := Color("8a5a3c")


static func box(bg: Color, border: Color, radius: int = 6, border_w: int = 2, pad: int = 6) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(pad)
	s.anti_aliasing = false
	return s


static func build() -> Theme:
	var t := Theme.new()
	t.default_font_size = 10
	t.set_color("font_color", "Label", INK)
	t.set_stylebox("panel", "PanelContainer", box(CREAM, COCOA, 8, 2, 8))
	t.set_stylebox("panel", "Panel", box(CREAM, COCOA, 8, 2, 8))

	t.set_stylebox("normal", "Button", box(PEACH, COCOA, 6, 2, 5))
	t.set_stylebox("hover", "Button", box(Color("ffe8d1"), COCOA, 6, 2, 5))
	t.set_stylebox("pressed", "Button", box(Color("f7b98c"), INK, 6, 2, 5))
	t.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), Color("ff9f68"), 6, 2, 5))
	t.set_stylebox("disabled", "Button", box(Color("e8ddd0"), Color("b8a898"), 6, 2, 5))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(state, "Button", INK)
	t.set_color("font_disabled_color", "Button", Color("a39488"))

	t.set_stylebox("normal", "LineEdit", box(Color.WHITE, COCOA, 4, 2, 4))
	t.set_stylebox("focus", "LineEdit", box(Color(0, 0, 0, 0), Color("ff9f68"), 4, 2, 4))
	t.set_color("font_color", "LineEdit", INK)

	t.set_stylebox("slider", "HSlider", box(Color("e8ddd0"), COCOA, 3, 1, 3))
	t.set_stylebox("grabber_area", "HSlider", box(Color("ff9f68"), COCOA, 3, 1, 3))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(Color("ffb98f"), COCOA, 3, 1, 3))
	t.set_icon("grabber", "HSlider", _knob(PEACH))
	t.set_icon("grabber_highlight", "HSlider", _knob(Color.WHITE))

	t.set_stylebox("background", "ProgressBar", box(Color("3b2a30"), Color("3b2a30"), 2, 1, 0))
	t.set_stylebox("fill", "ProgressBar", box(Color("8ff0a4"), Color("3b2a30"), 2, 1, 0))
	return t


## A chunky round slider knob.
static func _knob(fill: Color) -> ImageTexture:
	var img := Image.create(12, 12, false, Image.FORMAT_RGBA8)
	for y in 12:
		for x in 12:
			var d := Vector2(x - 5.5, y - 5.5).length()
			if d <= 4.2:
				img.set_pixel(x, y, fill)
			elif d <= 5.9:
				img.set_pixel(x, y, COCOA)
	return ImageTexture.create_from_image(img)


static func label(text: String, size: int = 10, color: Color = INK, outline: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if outline:
		l.add_theme_color_override("font_outline_color", INK)
		l.add_theme_constant_override("outline_size", 4)
	return l


static func bar(fill: Color, width: float, height: float) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.custom_minimum_size = Vector2(width, height)
	b.max_value = 1.0
	b.step = 0.0
	b.add_theme_stylebox_override("fill", box(fill, fill.darkened(0.3), 2, 1, 0))
	return b


static func sprite_icon(sprite_name: String, px: float) -> TextureRect:
	var r := TextureRect.new()
	r.texture = Roster.texture(sprite_name)
	r.custom_minimum_size = Vector2(px, px)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return r
