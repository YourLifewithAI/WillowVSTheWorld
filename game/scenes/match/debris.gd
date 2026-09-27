class_name Debris
extends Node2D
## Mess on the floor that has to be cleaned up: fur tufts (pets) and loose
## bolts (robots) from every KO, scorch marks from explosions, egg splats and
## spilled cat litter.
## More fighting now means more scrubbing later.

const CLEAN_TIMES := {"fur": 0.8, "bolts": 0.8, "scorch": 1.2, "yolk": 1.0, "litter": 0.9, "plaster": 1.0}

var debris_id := 0
var kind := "fur"
var progress := 0.0
var clean_time := 0.8
var _sprite: Sprite2D


func setup(id: int, sprite_name: String, pos: Vector2) -> void:
	debris_id = id
	kind = sprite_name
	clean_time = CLEAN_TIMES.get(sprite_name, 0.8)
	name = "Debris_%d" % id
	position = pos
	# Flat on the floor, under everyone's feet.
	z_index = -1
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
