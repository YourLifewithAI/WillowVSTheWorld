class_name LitterCloud
extends Node2D
## The dust cloud from a Litter Bomb. Cats on the thrower's team are invisible
## inside it, even while running; everyone else wades through it slowly.
## Every peer runs its own copy from the host's _cl_cloud broadcast.

var cloud_id := 0
var team := 0
var radius := 46.0
var life := 7.0
var _t := 0.0
var _puffs: Array[Vector3] = []  # x, y offset on the floor, and size


func setup(id: int, pos: Vector2, r: float, duration: float, owner_team: int) -> void:
	cloud_id = id
	name = "Cloud_%d" % id
	position = pos
	radius = r
	life = duration
	team = owner_team
	# Drawn over the characters inside it: it's a cloud, after all.
	z_index = 25
	var rng := RandomNumberGenerator.new()
	rng.seed = id * 7919
	for k in 16:
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * r * 0.85
		_puffs.append(Vector3(cos(a) * d, sin(a) * d * 0.5, rng.randf_range(0.25, 0.45) * r))


func active() -> bool:
	return _t < life


func contains(p: Vector2) -> bool:
	return active() and Iso.fdist(position, p) <= radius


func _process(delta: float) -> void:
	_t += delta
	if _t >= life + 0.5:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var fade := clampf(_t / 0.3, 0.0, 1.0) * clampf((life + 0.5 - _t) / 1.0, 0.0, 1.0)
	for k in _puffs.size():
		var p := _puffs[k]
		var drift := Vector2(sin(_t * 0.8 + k) * 3.0, cos(_t * 0.6 + k * 2.0) * 1.5)
		var at := Vector2(p.x, p.y - p.z * 0.4) + drift
		draw_circle(at, p.z * 0.5, Color(0.72, 0.67, 0.58, 0.28 * fade))
		draw_circle(at + Vector2(-p.z * 0.1, -p.z * 0.1), p.z * 0.38, Color(0.93, 0.9, 0.84, 0.32 * fade))
