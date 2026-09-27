class_name ChoreBubble
extends Node2D
## At the whistle, a speech bubble over each character on this screen: their
## chore's face and the one word for it ("HIDE IT!", "FETCH!"...), so everyone
## knows their job before the cleanup starts.

var player: Player
var face: Texture2D
var word := ""
var color := Color.WHITE
var _t := 0.0
var _life := 4.0


static func show_for(p: Player, chore: int, duration: float) -> void:
	var b := ChoreBubble.new()
	b.player = p
	b.face = Roster.texture(p.arena.chore_face(chore))
	b.word = Chores.VERB.get(chore, "HELP!")
	b.color = p.marker_color()
	b._life = duration
	b.z_index = 45
	p.arena.level.entities.add_child(b)


func _process(delta: float) -> void:
	_t += delta
	if _t >= _life or not is_instance_valid(player):
		queue_free()
		return
	position = player.position + Vector2(0, round(-player.z) - player.sprite_height() - 14)
	# Pops in, then fades out at the end.
	var k := clampf(_t / 0.2, 0.0, 1.0)
	scale = Vector2.ONE * (0.6 + 0.4 * k)
	modulate.a = clampf((_life - _t) / 0.4, 0.0, 1.0)
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var tw := font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
	var w := 11.0 + 3.0 + tw + 8.0
	var box := Rect2(Vector2(-w / 2.0, -8), Vector2(w, 15))
	draw_rect(box.grow(1), Color("3b2a30"))
	draw_rect(box, Color("fffdf5"))
	draw_rect(Rect2(box.position, Vector2(w, 2)), color)
	draw_colored_polygon(PackedVector2Array([Vector2(-3, 7), Vector2(3, 7), Vector2(0, 11)]), Color("3b2a30"))
	draw_colored_polygon(PackedVector2Array([Vector2(-2, 7), Vector2(2, 7), Vector2(0, 9)]), Color("fffdf5"))
	if face:
		draw_texture(face, Vector2(box.position.x + 3, -6))
	draw_string(font, Vector2(box.position.x + 17, 3), word, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color("3b2a30"))
