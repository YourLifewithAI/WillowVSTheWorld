@tool
class_name MessItem
extends Node2D
## Something that gets knocked over during the war and has to be put back
## before the parents come home. The server owns its state; every peer just
## mirrors it (see Match._cl_mess_state).
##
## Whose job it is (see Chores): heavy things are the Claw's to lift, things
## that live up high (pictures, things on counters and shelves) are Kiwi's,
## cushions are Biscuit's, and everything else is Pepper's to fetch.

@export var sprite_name := "lamp":
	set(v):
		sprite_name = v
		_refresh_sprite()
## Heavy things need the Claw (or two helpers) to stand back up.
@export var heavy := false
## Lives up high: a picture on a wall, or something on a counter or shelf.
@export var high := false
## How far above the floor it sits or hangs while it's in its place (px).
@export var hang := 0.0:
	set(v):
		hang = v
		_refresh_sprite()
## What spills out when it's knocked over (dirt from a plant, books from a
## shelf...): mess on the floor for its owner to clean (see Match._knock).
@export var spill_sprite := ""

const HEAVY_FORCE := 200.0

var index := -1
var home := Vector2.ZERO
## Where it slid to (relative to home) while knocked over.
var offset := Vector2.ZERO
var knocked := false
var progress := 0.0
var helpers := 0
## Who is carrying it home in their mouth (Pepper), or 0.
var carrier := 0
## Its owner is the one working on it (a green bar; anyone else's is grey).
var owner_working := false
## A picture: which way its wall runs on screen (so the frame slants with it).
var wall_dir := Vector2.ZERO

var _sprite: Sprite2D
var _overlay: Node2D
var _tween: Tween
var _t := 0.0


func _ready() -> void:
	home = position
	_refresh_sprite()
	if Engine.is_editor_hint():
		return
	_overlay = Node2D.new()
	_overlay.z_index = 20
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)


## Whose job it is to put it back.
func chore() -> int:
	if heavy:
		return Chores.Chore.LIFT
	if high:
		return Chores.Chore.HIGH
	if sprite_name.begins_with("cushion"):
		return Chores.Chore.SOFT
	return Chores.Chore.FETCH


## Flung a long way from home (another room, even), not just tipped over.
func stray() -> bool:
	return Iso.to_floor(offset).length() > Chores.STRAY_DISTANCE


func _spec() -> Array:
	match chore():
		Chores.Chore.LIFT:
			return Chores.HEAVY
		Chores.Chore.HIGH:
			return Chores.HIGH_ITEM
		Chores.Chore.SOFT:
			return [Chores.Chore.SOFT, 0.8, 1.4]
	return Chores.STRAY if stray() else Chores.TIPPED


## Seconds of work to put it back (at rate 1), and how much it counts against the house.
func job_time() -> float:
	return float(_spec()[1])


func weight() -> float:
	return float(_spec()[2])


func can_be_knocked_by(force: float) -> bool:
	return not knocked and (not heavy or force >= HEAVY_FORCE)


func _refresh_sprite() -> void:
	if not is_inside_tree():
		return
	if _sprite == null:
		_sprite = Sprite2D.new()
		_sprite.centered = false
		add_child(_sprite)
	_sprite.texture = Roster.texture(sprite_name) if sprite_name != "picture" else null
	if _sprite.texture:
		var s := _sprite.texture.get_size()
		_sprite.offset = Vector2(-floor(s.x / 2.0), -s.y + 1)
	_sprite.position = Vector2(0, -hang if not knocked else 0.0)
	queue_redraw()


## Mirrors the server's view of this item. `offset` is where it slid to.
func apply_state(is_knocked: bool, new_offset: Vector2, new_progress: float, new_helpers: int, new_carrier: int = 0) -> void:
	helpers = new_helpers
	progress = new_progress
	offset = new_offset
	var dropped := carrier != 0 and new_carrier == 0 and is_knocked
	carrier = new_carrier
	if dropped:
		# Put down wherever the carrier was.
		position = home + offset
		_sprite.position = Vector2.ZERO
	if is_knocked != knocked:
		knocked = is_knocked
		if _tween:
			_tween.kill()
		_tween = create_tween().set_parallel(true)
		if knocked:
			var side := 1.0 if offset.x >= 0.0 else -1.0
			_tween.tween_property(self, "position", home + offset, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			_tween.tween_property(_sprite, "rotation", side * PI * 0.5, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			_tween.tween_property(_sprite, "position", Vector2.ZERO, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		else:
			_tween.tween_property(self, "position", home, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			_tween.tween_property(_sprite, "rotation", 0.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			_tween.tween_property(_sprite, "position", Vector2(0, -hang), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	queue_redraw()
	if _overlay:
		_overlay.queue_redraw()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_t += delta
	# Carried home in Pepper's mouth.
	if carrier != 0 and knocked and Match.current and Match.current.players.has(carrier):
		var p: Player = Match.current.players[carrier]
		position = p.position + Vector2(0, 1)
		_sprite.position = Vector2(0, -p.sprite_height() + 4)
	if knocked and _overlay:
		_overlay.queue_redraw()


func _draw() -> void:
	if sprite_name == "picture":
		_draw_picture()
		return
	var s := 6.0 if heavy else 4.0
	if not knocked or carrier == 0:
		draw_colored_polygon(Iso.ellipse(s, 12), Color(0, 0, 0, 0.18))


## A little framed picture: hanging on its wall (slanting along it), or lying
## face-up where it fell.
func _draw_picture() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(name)
	var art: Array[Color] = [Color("8fd6c9"), Color("ffd6a5"), Color("c9b3ff"), Color("9fe0a0"), Color("ffb3c1")]
	var fill := art[rng.randi() % art.size()]
	if knocked:
		var rect := Rect2(Vector2(-5, -4), Vector2(10, 4))
		draw_rect(rect.grow(1), Color("3b2a30"))
		draw_rect(rect, Color("b5824f"))
		draw_rect(rect.grow(-1), fill)
		return
	var along := wall_dir if wall_dir != Vector2.ZERO else Vector2.RIGHT
	var base := Vector2(0, -hang)
	var quad := func(x0: float, x1: float, y0: float, y1: float, c: Color) -> void:
		draw_colored_polygon(PackedVector2Array([base + along * x0 - Vector2(0, y0), base + along * x1 - Vector2(0, y0),
			base + along * x1 - Vector2(0, y1), base + along * x0 - Vector2(0, y1)]), c)
	quad.call(-6.0, 6.0, -1.0, 10.0, Color("3b2a30"))
	quad.call(-5.0, 5.0, 0.0, 9.0, Color("b5824f"))
	quad.call(-4.0, 4.0, 1.0, 8.0, fill)
	quad.call(-3.0, 0.0, 2.0, 4.0, fill.darkened(0.35))
	quad.call(1.0, 3.0, 5.0, 7.0, Color(1, 1, 1, 0.6))


## The job marker (see JobBadge): whose job it is, and progress.
func _draw_overlay() -> void:
	if not knocked or carrier != 0:
		return
	var arena := Match.current
	if arena == null or arena.phase != Match.Phase.CLEANUP:
		return
	JobBadge.draw(_overlay, Vector2(0, -18 - (6 if heavy else 0)), arena, chore(), progress, helpers, owner_working, _t)
