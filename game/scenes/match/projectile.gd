class_name Projectile
extends Node2D
## Every shot, shell, egg and bark. Every peer flies its own copy (the owner
## only sends the direction); the shooter's owner holds the "authoritative"
## copy, which checks what it hits and reports that to the host.
##
## Straight shots stop at the first piece of furniture in their way (and chip
## at it), unless fired from the air or marked `through_walls`. Lobbed shells
## sail over everything and explode where they land.

const HEIGHT := 9.0

var shooter: Player
var ability := 0
var spec: Dictionary = {}
var dir := Vector2.RIGHT
var authoritative := false
var ambush := false
var proj_id := 0
var lob := false
var z := HEIGHT
var _start_z := HEIGHT
var _travelled := 0.0
var _hit: Dictionary = {}
var _sprite: Sprite2D
var _t := 0.0
var _done := false
var _first := true

const SPRITES := {"ball": "p_ball", "rocket": "p_rocket", "egg": "p_egg", "toast": "p_toast",
	"feather": "feather", "rocket_fist": "rocket_fist", "litter": "p_litter"}


func setup(from: Player, which: int, direction: Vector2, id: int, is_authoritative: bool, from_ambush: bool) -> void:
	shooter = from
	ability = which
	spec = Roster.ability(from.data, which)
	dir = direction.normalized()
	authoritative = is_authoritative
	ambush = from_ambush
	proj_id = id
	# Lobbed weapons, and the Litter Bomb gag (the only gag that's thrown).
	lob = (which == 0 and int(spec["kind"]) == Roster.Weapon.LOB) or which == 2
	name = "Proj_%d_%d" % [from.pid, id]
	position = from.position + Iso.to_screen(dir * (3.0 if lob else 8.0))
	_start_z = maxf(from.z, 8.0) if lob else HEIGHT + from.z * 0.5
	z = _start_z


func _ready() -> void:
	var look: String = spec.get("look", "")
	if SPRITES.has(look):
		_sprite = Sprite2D.new()
		_sprite.texture = Roster.texture(SPRITES[look])
		_sprite.rotation = Iso.to_screen(dir).angle() if look in ["rocket", "feather", "rocket_fist"] else 0.0
		add_child(_sprite)


func _arena() -> Match:
	return shooter.arena if is_instance_valid(shooter) else null


func _physics_process(delta: float) -> void:
	var arena := _arena()
	if arena == null or _done:
		queue_free()
		return
	_t += delta
	# The first step starts from the shooter's centre: someone hugging a wall
	# spawns their shot a little way ahead, possibly inside it.
	var from := shooter.position if _first else position
	_first = false
	var step := dir * float(spec["speed"]) * delta
	position += Iso.to_screen(step)
	_travelled += step.length()
	var reach := float(spec["range"])
	if lob:
		var k := clampf(_travelled / reach, 0.0, 1.0)
		z = _start_z * (1.0 - k) + float(spec.get("arc", 0.0)) * 4.0 * k * (1.0 - k)
	# Walls. Shells sail over while they're higher than the wall (as drawn).
	if not spec.get("through_walls", false) and (not lob or z < WallRun.HEIGHT):
		var hit := arena.level.wall_between(from, position)
		if not hit.is_empty():
			position = hit["point"] - Iso.to_screen(dir * 2.0)
			if lob:
				_explode(arena)
			else:
				_hit_wall(arena, hit["panel"])
			return
	if lob:
		var k := clampf(_travelled / reach, 0.0, 1.0)
		if k >= 1.0 or not arena.level.room.contains(position, 0.05):
			_explode(arena)
		queue_redraw()
		return
	if _travelled >= reach or not arena.level.room.contains(position, 0.05):
		queue_free()
		return
	queue_redraw()

	# Furniture in the way.
	if not shooter.data.get("flying", false):
		var f := arena.level.furniture_at(position)
		if f and not _hit.has(f):
			_hit[f] = true
			if authoritative:
				arena.report_furniture_hit(f, float(spec.get("demolition", 0.0)), shooter, ability)
			if not spec.get("through_walls", false):
				Fx.burst(arena.level.entities, position + Vector2(0, -z), Color.WHITE)
				Audio.play_at("thud", arena.level.entities, position, -6.0)
				queue_free()
				return
	if not authoritative:
		return
	var hit_reach := float(spec["hit_radius"]) + Player.BODY_RADIUS
	for other: Player in arena.players.values():
		if other.team == shooter.team or other.is_ko or _hit.has(other.pid):
			continue
		if Iso.fdist(position, other.position) <= hit_reach:
			_hit[other.pid] = true
			arena.report_hit(shooter, other, ability, dir, ambush)
			if not spec.get("pierce", false):
				shooter.despawn_projectile.rpc(proj_id)
				return
	for item in arena.level.mess_items:
		if not _hit.has(item) and Iso.fdist(position, item.position) <= hit_reach:
			_hit[item] = true
			arena.report_mess_hit(item, float(spec["knock"]), Iso.to_floor(item.position - position))


## A straight shot stops at a wall: a crunch if it's hard enough to hurt it,
## otherwise just a "tink" (every machine shows this from its own copy).
func _hit_wall(arena: Match, panel: WallPanel) -> void:
	_done = true
	var demolition := float(spec.get("demolition", 0.0))
	var hurts := panel.can_be_damaged() and demolition >= panel.min_hit
	if hurts:
		Fx.burst(arena.level.entities, position + Vector2(0, -z), Color("fff8ef"))
		if authoritative:
			arena.report_furniture_hit(panel, demolition, shooter, ability)
	else:
		Fx.puff(arena.level.entities, position + Vector2(0, -z), Color(1, 1, 1, 0.7))
		Audio.play_at("tink", arena.level.entities, position, -4.0)
		if authoritative:
			arena.report_furniture_hit(panel, 0.0, shooter, ability)  # it still knocks the pictures off
	queue_free()


func _explode(arena: Match) -> void:
	_done = true
	var radius := float(spec.get("explode_radius", 16.0))
	Fx.boom(arena.level.entities, position, radius, spec.get("look", "") == "egg")
	# Bigger blasts sound deeper. (The litter bomb's cloud makes its own noise.)
	if ability != 2:
		Audio.play_at(spec.get("hit_sfx", "boom"), arena.level.entities, position, 0.0, clampf(24.0 / radius, 0.8, 1.3))
	if authoritative:
		shooter.hit_area(position, radius, ability, float(spec["knock"]), float(spec.get("demolition", 0.0)), ambush)
		if ability == 2:
			arena.report_gag(shooter, position)
		else:
			arena.report_decal(position, spec.get("decal", ""))
	queue_free()


func _draw() -> void:
	var look: String = spec.get("look", "")
	draw_colored_polygon(Iso.ellipse(2.5 if look != "ring" else 5.0, 10), Color(0, 0, 0, 0.2))
	var at := Vector2(0, round(-z))
	var a := Iso.to_screen(dir).angle()
	if _sprite:
		_sprite.position = at
		if look == "toast" or look == "litter":
			_sprite.rotation = _t * (14.0 if look == "toast" else 6.0)
	match look:
		"laser":
			var back := Iso.to_screen(-dir) * 10.0
			draw_line(at, at + back, Color(1, 0.2, 0.25, 0.9), 2.0)
			draw_line(at, at + back * 0.6, Color(1, 0.9, 0.9), 1.0)
		"dust":
			var r := 2.0 + _t * 14.0
			draw_circle(at, r + 1.0, Color(0.55, 0.52, 0.5, 0.5))
			draw_circle(at + Vector2(-1, -1), r, Color(0.85, 0.82, 0.78, 0.8))
		"ring":
			for k in 2:
				var rr := 5.0 + k * 4.0 + fmod(_t * 30.0, 4.0)
				draw_arc(at, rr, a - 1.0, a + 1.0, 10, Color(0.38, 0.95, 1.0, 0.9 - k * 0.3), 2.0)
		"bark":
			for k in 3:
				var rr := 4.0 + k * 4.0 + fmod(_t * 30.0, 4.0)
				draw_arc(at, rr, a - 0.9, a + 0.9, 8, Color(1.0, 0.91, 0.66, 1.0 - k * 0.25), 2.0)
		"rocket":
			draw_circle(at - Iso.to_screen(dir) * 5.0, 1.5 + sin(_t * 40.0), Color("ffd84d"))
