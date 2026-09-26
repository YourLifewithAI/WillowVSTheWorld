@tool
class_name MessItem
extends Node2D
## Something that gets knocked over during the war and has to be put back
## before the parents come home. The server owns its state; every peer just
## mirrors it (see Match._cl_mess_state).

@export var sprite_name := "lamp":
	set(v):
		sprite_name = v
		_refresh_sprite()
## Heavy things need two helpers (or one strong robot) to stand back up.
@export var heavy := false
## Optional sprite left on the floor while knocked over (e.g. spilled dirt).
@export var spill_sprite := ""

const HEAVY_FORCE := 200.0

var index := -1
var home := Vector2.ZERO
## Where it slid to (relative to home) while knocked over.
var offset := Vector2.ZERO
var knocked := false
var progress := 0.0
var helpers := 0

var _sprite: Sprite2D
var _spill: Sprite2D
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


func weight() -> float:
	return 3.0 if heavy else 1.0


func required_lift() -> int:
	return 2 if heavy else 1


func fix_time() -> float:
	return 5.0 if heavy else 3.0


func can_be_knocked_by(force: float) -> bool:
	return not knocked and (not heavy or force >= HEAVY_FORCE)


func _refresh_sprite() -> void:
	if not is_inside_tree():
		return
	if _sprite == null:
		_sprite = Sprite2D.new()
		_sprite.centered = false
		add_child(_sprite)
	_sprite.texture = Roster.texture(sprite_name)
	if _sprite.texture:
		var s := _sprite.texture.get_size()
		_sprite.offset = Vector2(-floor(s.x / 2.0), -s.y + 1)
	queue_redraw()


## Mirrors the server's view of this item. `offset` is where it slid to.
func apply_state(is_knocked: bool, new_offset: Vector2, new_progress: float, new_helpers: int) -> void:
	helpers = new_helpers
	progress = new_progress
	offset = new_offset
	if is_knocked != knocked:
		knocked = is_knocked
		if _tween:
			_tween.kill()
		_tween = create_tween().set_parallel(true)
		if knocked:
			var side := 1.0 if offset.x >= 0.0 else -1.0
			_tween.tween_property(self, "position", home + offset, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			_tween.tween_property(_sprite, "rotation", side * PI * 0.5, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			if spill_sprite != "":
				_spill = Sprite2D.new()
				_spill.texture = Roster.texture(spill_sprite)
				_spill.position = Vector2(-side * 4.0, 1)
				add_child(_spill)
				move_child(_spill, 0)
		else:
			_tween.tween_property(self, "position", home, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			_tween.tween_property(_sprite, "rotation", 0.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			if _spill:
				_spill.queue_free()
				_spill = null
	queue_redraw()
	if _overlay:
		_overlay.queue_redraw()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_t += delta
	if knocked and _overlay:
		_overlay.queue_redraw()


func _draw() -> void:
	var s := 6.0 if heavy else 4.0
	draw_colored_polygon(Iso.ellipse(s, 12), Color(0, 0, 0, 0.18))


func _draw_overlay() -> void:
	if not knocked:
		return
	var top := Vector2(0, -16 - (6 if heavy else 0))
	var cleanup := Match.current != null and Match.current.phase == Match.Phase.CLEANUP
	if cleanup:
		# A bobbing marker so everyone can see what still needs fixing.
		var bob := sin(_t * 5.0) * 1.5
		var c := Color("ffd84d") if progress <= 0.0 else Color("8ff0a4")
		_overlay.draw_colored_polygon(PackedVector2Array([top + Vector2(-3, bob - 4), top + Vector2(3, bob - 4), top + Vector2(0, bob)]), c)
		if heavy and helpers < required_lift():
			var font := ThemeDB.fallback_font
			_overlay.draw_string(font, top + Vector2(-5, bob - 6), "x2", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color.WHITE)
	if progress > 0.0:
		var bar := Rect2(top + Vector2(-8, 2), Vector2(16, 3))
		_overlay.draw_rect(bar.grow(1), Color("3b2a30"))
		_overlay.draw_rect(Rect2(bar.position, Vector2(bar.size.x * progress, bar.size.y)), Color("8ff0a4"))
