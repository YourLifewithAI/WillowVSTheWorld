class_name Glyphs
extends RefCounted
## Little pictures of buttons for on-screen hints (see HintLine).
##
## A sideways Joy-Con's four buttons are printed differently on each side
## (arrows on the left one, letters on the right one), and a Pro Controller's
## letters are in other places again, so a button is shown by WHERE it is: a
## diamond of four dots with that one lit. The shoulder buttons get a pill
## ("SL SR" on a sideways Joy-Con), + / - a round "+", the stick a stick, and
## the keyboard a keycap.

const INK := Color("2b1d2a")
## Where each face button sits in the diamond.
const FACE := {"left": Vector2(-1, 0), "top": Vector2(0, -1), "right": Vector2(1, 0), "bottom": Vector2(0, 1)}
## Which face button does what (the same on every controller, see Seats).
const ACTION_FACE := {"attack": "left", "special": "top", "interact": "right", "dash": "bottom"}
const KEYS := {"attack": "J", "special": "K", "interact": "E", "dash": "Space", "gag": "I", "menu": "Esc",
	"move": "WASD", "aim": "Mouse", "ready": "Enter"}


## What to draw for `action` ("attack", "special", "interact", "dash", "gag",
## "menu", "move", "aim" or "ready": + in the warm-up, Enter on the keyboard)
## for this seat's controller or keyboard.
static func of(seat: int, action: String) -> Dictionary:
	if not Seats.uses_controller(seat):
		return {"kind": "key", "text": KEYS.get(action, action)}
	if ACTION_FACE.has(action):
		return {"kind": "face", "pos": ACTION_FACE[action]}
	match action:
		"gag":
			return {"kind": "shoulder", "text": "SL SR" if Seats.sideways(seat) else "L R"}
		"menu", "ready":
			return {"kind": "menu"}
	return {"kind": "stick"}


## How wide a glyph is at height `h`.
static func width(g: Dictionary, h: float, font: Font) -> float:
	match g["kind"]:
		"key", "shoulder":
			return ceilf(font.get_string_size(g["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, _text_size(h)).x) + 5.0
	return h


## Draws a glyph `h` px tall with its left edge at `at.x`, centred on `at.y`.
## `accent` lights the button that matters. Returns its width.
static func draw(ci: CanvasItem, at: Vector2, g: Dictionary, h: float, accent: Color, font: Font) -> float:
	var w := width(g, h, font)
	var r := h * 0.5
	var c := at + Vector2(r, 0)
	match g["kind"]:
		"face":
			ci.draw_circle(c, r, INK)
			for pos: String in FACE:
				var off: Vector2 = FACE[pos]
				var p := c + off * r * 0.56
				if pos == g["pos"]:
					ci.draw_circle(p, r * 0.4, accent)
				else:
					ci.draw_circle(p, r * 0.22, Color(1, 1, 1, 0.6))
		"menu":
			ci.draw_circle(c, r * 0.85, INK)
			ci.draw_circle(c, r * 0.85, accent, false, 1.0)
			ci.draw_line(c + Vector2(-r * 0.45, 0), c + Vector2(r * 0.45, 0), accent, 1.0)
			ci.draw_line(c + Vector2(0, -r * 0.45), c + Vector2(0, r * 0.45), accent, 1.0)
		"stick":
			ci.draw_circle(c, r, INK)
			ci.draw_circle(c, r * 0.8, Color(1, 1, 1, 0.35), false, 1.0)
			ci.draw_circle(c, r * 0.45, accent)
		"key", "shoulder":
			var box := Rect2(at + Vector2(0, -r), Vector2(w, h)).abs()
			var pill: bool = g["kind"] == "shoulder"
			ci.draw_rect(box, INK if pill else Color("fff4e3"))
			ci.draw_rect(box, accent if pill else INK, false, 1.0)
			var ts := _text_size(h)
			var tw := font.get_string_size(g["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, ts).x
			var base := Vector2(box.position.x + (w - tw) * 0.5, at.y + (font.get_ascent(ts) - font.get_descent(ts)) * 0.5)
			ci.draw_string(font, base.round(), g["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, ts, accent if pill else INK)
	return w


static func _text_size(h: float) -> int:
	return maxi(5, int(h * 0.62))
