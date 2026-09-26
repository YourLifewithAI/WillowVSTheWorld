class_name Debris
extends Node2D
## Fur tufts (pets) and loose bolts (robots) left behind by every KO.
## More fighting now means more sweeping later.

const CLEAN_TIME := 0.8

var debris_id := 0
var progress := 0.0
var _sprite: Sprite2D


func setup(id: int, sprite_name: String, pos: Vector2) -> void:
	debris_id = id
	name = "Debris_%d" % id
	position = pos
	_sprite = Sprite2D.new()
	_sprite.texture = Roster.texture(sprite_name)
	_sprite.position = Vector2(0, -1)
	add_child(_sprite)


func set_progress(p: float) -> void:
	progress = p
	queue_redraw()


func _draw() -> void:
	if progress > 0.0:
		var bar := Rect2(Vector2(-6, -8), Vector2(12, 2))
		draw_rect(bar.grow(1), Color("3b2a30"))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * progress, bar.size.y)), Color("8ff0a4"))
