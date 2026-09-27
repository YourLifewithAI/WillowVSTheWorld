class_name Debris
extends Node2D
## Mess on the floor that has to be cleaned up, each kind someone's job (see
## Chores): fur tufts and loose bolts from every KO, litter, plaster dust and
## crumbs (Zoomba's), clutter shaken off shelves and tables (Willow's), scorch
## marks, egg, scuffs and spills (Bass's), and pillows (Biscuit's).
## More fighting now means more scrubbing later.

var debris_id := 0
var kind := "fur"
var progress := 0.0
## Whose job it is (see Chores.DEBRIS), how long it takes at rate 1, and how
## much it counts against the house's tidiness.
var chore := Chores.Chore.FLOOR
var clean_time := 0.5
var weight := 0.4
## Extra weight it has gathered (another KO on the same spot, or a full house).
var growth := 0.0
## Its owner is the one working on it (a green bar; anyone else's is grey).
var owner_working := false
var _sprite: Sprite2D
var _extra: Array[Sprite2D] = []
## Cleanup: the colours of the people on this screen whose job it is (a pulsing ring).
var _mine: Array[Color] = []
var _t := 0.0


func setup(id: int, sprite_name: String, pos: Vector2) -> void:
	debris_id = id
	kind = sprite_name
	var spec: Array = Chores.DEBRIS.get(sprite_name, [Chores.Chore.FLOOR, 0.5, 0.4])
	chore = spec[0]
	clean_time = spec[1]
	weight = spec[2]
	name = "Debris_%d" % id
	position = pos
	# Flat on the floor, under everyone's feet.
	z_index = -1
	_sprite = Sprite2D.new()
	_sprite.texture = Roster.texture(sprite_name)
	_sprite.position = Vector2(0, -1)
	add_child(_sprite)


func _process(delta: float) -> void:
	var arena := Match.current
	if arena == null or arena.phase != Match.Phase.CLEANUP:
		if not _mine.is_empty():
			_mine.clear()
			queue_redraw()
		return
	_t += delta
	_mine = arena.local_owner_colors(chore)
	if not _mine.is_empty():
		queue_redraw()


func set_progress(p: float) -> void:
	progress = p
	queue_redraw()


## A bigger pile: a bit more to clean, and it looks it.
func grow() -> void:
	growth += Chores.GROW_WEIGHT
	weight += Chores.GROW_WEIGHT
	clean_time += Chores.GROW_TIME
	var more := Sprite2D.new()
	more.texture = _sprite.texture
	var k := _extra.size()
	more.position = Vector2([-3, 3, 0][k % 3], [-1, 0, -3][k % 3])
	more.flip_h = k % 2 == 0
	add_child(more)
	_extra.append(more)


## Cleaned up: it shrinks away into `to` (under a couch, into Zoomba), or
## shakes loose and fades (a THUMP).
func vanish(to: Vector2, shake: bool = false) -> void:
	progress = 0.0
	queue_redraw()
	var tw := create_tween().set_parallel(true)
	if shake:
		tw.tween_property(self, "position", position + Vector2(0, -3), 0.12).set_trans(Tween.TRANS_SINE)
		tw.tween_property(self, "modulate:a", 0.0, 0.25).set_delay(0.08)
	else:
		tw.tween_property(self, "position", to, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(self, "scale", Vector2(0.3, 0.3), 0.2)
		tw.tween_property(self, "modulate:a", 0.0, 0.2).set_delay(0.08)
	tw.chain().tween_callback(queue_free)


func _draw() -> void:
	if not _mine.is_empty():
		# Yours: a ring in your colour, pulsing every 1.5 s.
		var ring := Iso.ellipse(7.0 + growth * 4.0, 16)
		ring.append(ring[0])
		var c := _mine[0]
		c.a = 0.35 + 0.45 * (0.5 + 0.5 * sin(_t * TAU / 1.5))
		draw_polyline(ring, c, 1.0)
	if progress > 0.0:
		var bar := Rect2(Vector2(-6, -8), Vector2(12, 2))
		draw_rect(bar.grow(1), Color("3b2a30"))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * progress, bar.size.y)),
			Color("8ff0a4") if owner_working else Color("d8d8d8"))
