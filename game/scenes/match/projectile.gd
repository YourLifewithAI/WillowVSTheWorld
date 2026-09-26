class_name Projectile
extends Node2D
## Feathers, barks and rocket fists. Every peer flies its own copy; only the
## shooter's owner (the "authoritative" copy) checks for hits and reports them.

const HEIGHT := 9.0

var shooter: Player
var dir := Vector2.RIGHT
var spec: Dictionary = {}
var authoritative := false
var proj_id := 0
var _travelled := 0.0
var _hit: Dictionary = {}
var _sprite: Sprite2D
var _t := 0.0


func setup(from: Player, direction: Vector2, id: int, is_authoritative: bool) -> void:
	shooter = from
	dir = direction.normalized()
	spec = from.data["special"]
	authoritative = is_authoritative
	proj_id = id
	name = "Proj_%d_%d" % [from.pid, id]
	position = from.position + Iso.to_screen(dir * 8.0)


func _ready() -> void:
	var sprite_name: String = spec.get("sprite", "")
	if sprite_name != "":
		_sprite = Sprite2D.new()
		_sprite.texture = Roster.texture(sprite_name)
		_sprite.position = Vector2(0, -HEIGHT)
		_sprite.rotation = Iso.to_screen(dir).angle()
		add_child(_sprite)


func _physics_process(delta: float) -> void:
	_t += delta
	var step := dir * float(spec["speed"]) * delta
	position += Iso.to_screen(step)
	_travelled += step.length()
	var arena: Match = shooter.arena if is_instance_valid(shooter) else null
	if arena == null or _travelled >= float(spec["range"]) or not arena.level.room.contains(position, 0.1):
		queue_free()
		return
	queue_redraw()
	if not authoritative:
		return
	var reach := float(spec["hit_radius"]) + Player.BODY_RADIUS
	for other: Player in arena.players.values():
		if other.team == shooter.team or other.is_ko or _hit.has(other.pid):
			continue
		if Iso.fdist(position, other.position) <= reach:
			_hit[other.pid] = true
			arena.report_hit(shooter, other, 1, dir)
			if not spec.get("pierce", false):
				shooter.despawn_projectile.rpc(proj_id)
				return
	for item in arena.level.mess_items:
		if not _hit.has(-1000 - item.index) and Iso.fdist(position, item.position) <= reach:
			_hit[-1000 - item.index] = true
			arena.report_mess_hit(item, float(spec["knock"]), Iso.to_floor(item.position - position))


func _draw() -> void:
	draw_colored_polygon(Iso.ellipse(3.0, 10), Color(0, 0, 0, 0.2))
	if _sprite == null:
		# Big Bark: expanding sound arcs.
		var a := Iso.to_screen(dir).angle()
		var c := Color("ffe9a8")
		for k in 3:
			var r := 4.0 + k * 4.0 + fmod(_t * 30.0, 4.0)
			draw_arc(Vector2(0, -HEIGHT), r, a - 0.9, a + 0.9, 8, Color(c, 1.0 - k * 0.25), 2.0)
