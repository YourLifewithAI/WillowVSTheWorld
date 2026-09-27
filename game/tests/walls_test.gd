extends Node
## Walls test (run by tools/smoke_test.sh):
##   godot --headless --fixed-fps 60 --path game res://tests/walls_test.tscn -- --war=300
##
## Plays the Family Home with three pets and three robots standing still, and
## checks the rules of walls along the living-room wall (the line i = 7):
## which hits break them, that shots, blasts, swings, the remote and pickups
## stop at them (and Bass's waves don't), that one hit breaks at most one
## panel, and that a mended wall waits for the gap to be clear. Then it loads
## the Farmhouse and checks that stone and outside walls never break. On both,
## the bots' map must lead from the remote's rug to each base.

const WALL_I := 7.0
const ROW := 13.5  # along the wall: the middle of its panel from j = 13 to 14

var _passed := 0
var _failed := 0
var arena: Match
var cast: Dictionary = {}  # character id -> Player


func _ready() -> void:
	get_tree().current_scene = null
	get_tree().create_timer(120.0, true, false, true).timeout.connect(func() -> void:
		check(false, "finished within two minutes")
		_finish())
	_run.call_deferred()


func check(ok: bool, what: String) -> void:
	if ok:
		_passed += 1
		print("  PASS  walls: %s" % what)
	else:
		_failed += 1
		print("  FAIL  walls: %s" % what)


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _finish() -> void:
	print("[walls] %d passed, %d failed" % [_passed, _failed])
	Audio.quit_game()


func _run() -> void:
	await _start("family_home", ["biscuit", "pepper"], ["bass", "claw", "butler"])
	var level := arena.level
	var walls := level.wall_panels

	# Walls are built after the scene's own furniture, so indexes match everywhere.
	var first := level.furniture.find(walls[0])
	var tail := level.furniture.slice(first)
	check(first > 0 and tail.size() == walls.size() and tail.all(func(f: Furniture) -> bool: return f is WallPanel),
		"%d wall panels come after the %d pieces of furniture" % [walls.size(), first])

	# Only the heavy hitters (demolition 50+) dent a painted wall.
	var panel := _panel(ROW)
	var wrong := []
	var heavy := []
	for id: String in Roster.CHARACTERS:
		var data: Dictionary = Roster.get_char(id)
		for a in [0, 1, 2, 3]:
			var spec := Roster.ability(data, a)
			var d := float(spec.get("demolition", 0.0))
			_mend(panel)
			arena._damage_furniture(panel, d)
			if (panel.hp < panel.max_hp) != (d >= WallPanel.MIN_HIT):
				wrong.append("%s %s (%d)" % [data["name"], spec["name"], d])
			elif d >= WallPanel.MIN_HIT:
				heavy.append(String(spec["name"]))
			if a == 3 and d >= WallPanel.MIN_HIT:
				wrong.append("%s's close-up move breaks walls" % data["name"])
	_mend(panel)
	arena._damage_furniture(panel, Player.CRASH_DAMAGE)
	check(wrong.is_empty() and panel.hp == panel.max_hp,
		"only heavy hits dent walls (%s); lasers, eggs, crashes and close-up moves don't %s" % [", ".join(heavy), wrong])
	_mend(panel)
	await frames(2)

	var willow: Player = cast["willow"]
	var bass: Player = cast["bass"]
	var claw: Player = cast["claw"]
	var biscuit: Player = cast["biscuit"]
	var butler: Player = cast["butler"]

	# A laser stops at the wall (and doesn't hurt it); on the same side it hits.
	_place(willow, 6.4, ROW, Vector2(1, 0))
	_place(claw, 8.3, ROW, Vector2(-1, 0))
	willow._do_attack()
	await frames(40)
	check(claw.hp == claw.max_hp and panel.hp == panel.max_hp, "a laser stops at the wall with a tink")
	_place(willow, 7.8, 15.6, Vector2(1, 0))
	_place(claw, 9.6, 15.6, Vector2(-1, 0))
	willow._do_attack()
	await frames(40)
	check(claw.hp < claw.max_hp, "...and hits someone in the same room (%d -> %d HP)" % [claw.max_hp, claw.hp])
	_park(claw)

	# Bass's bass waves go right through walls.
	_place(bass, 8.4, ROW, Vector2(-1, 0))
	_place(willow, 6.4, ROW, Vector2(1, 0))
	bass._do_attack()
	await frames(40)
	check(willow.hp < willow.max_hp, "Bass's waves pass through walls (%d -> %d HP)" % [willow.max_hp, willow.hp])
	_park(bass)

	# A bazooka shell fired right at a wall bursts on it; from further back it sails over.
	_heal_all()
	_place(biscuit, 6.6, ROW, Vector2(1, 0))
	var target := claw
	_place(target, 6.6 + 5.3, ROW, Vector2(-1, 0))
	biscuit._do_attack()
	await frames(60)
	check(target.hp == target.max_hp and panel.hp < panel.max_hp,
		"a bazooka shell fired at a wall right in front bursts on the wall")
	_mend(panel)
	_heal_all()
	biscuit.attack_cd = 0.0
	_place(biscuit, 4.6, ROW, Vector2(1, 0))
	_place(target, 4.6 + 5.3, ROW, Vector2(-1, 0))
	biscuit._do_attack()
	await frames(60)
	check(target.hp < target.max_hp and panel.hp == panel.max_hp,
		"...but sails over it from further back (%d -> %d HP)" % [target.max_hp, target.hp])
	_park(biscuit)

	# A blast doesn't reach through a wall, but does in its own room.
	_heal_all()
	_place(bass, 7.6, ROW, Vector2(-1, 0))
	_place(butler, 6.1, ROW - 0.8, Vector2(1, 0))
	biscuit.hit_area(_at(6.55, ROW), 30.0, 0, 240.0, 60.0, false)
	await frames(10)
	check(bass.hp == bass.max_hp and butler.hp < butler.max_hp,
		"a blast hurts only its own side of a wall (behind: %d HP, beside: %d HP)" % [bass.hp, butler.hp])
	_park(bass)
	_park(butler)

	# One blast, one swing or one satellite strike damages at most one panel.
	_mend_all()
	biscuit.hit_area(_at(7.4, 14.0), 30.0, 0, 240.0, 60.0, false)
	await frames(5)
	check(_damaged().size() == 1, "a blast right between two panels damages just one of them")
	_mend_all()
	_place(claw, 7.7, 13.0, Vector2(-1, 0))
	claw._hit_arc(claw.weapon_spec(), 0, false)
	await frames(5)
	check(_damaged().size() == 1, "a wrecking-ball swing damages only the nearest panel")
	_park(claw)
	_mend_all()
	arena._strikes.append({"pid": butler.pid, "pos": _at(WALL_I, 14.0), "t": 0.0})
	await frames(5)
	var broken := _damaged()
	check(broken.size() == 1 and broken[0].wrecked, "a satellite strike on a wall breaks exactly one panel")
	# ...and bots can walk through the hole once the map re-plans.
	await frames(40)
	var hole: WallPanel = broken[0]
	var through := level.find_path(_at(6.2, hole.rect.get_center().y), _at(7.8, hole.rect.get_center().y))
	check(through.size() > 0 and _path_len(through) < 60.0, "the bots' map goes through the hole (%.0f px)" % _path_len(through))

	# A mended wall only turns solid once nobody is standing in the gap.
	_place(bass, WALL_I, hole.rect.get_center().y, Vector2(1, 0))
	await frames(3)
	hole.rebuild = 1.0
	arena._tick_rebuild(hole, 0.1, true)
	await frames(2)
	check(hole.wrecked, "a mended wall waits while someone stands in the gap")
	_park(bass)
	await frames(3)
	arena._tick_rebuild(hole, 0.1, true)
	await frames(2)
	check(not hole.wrecked, "...and goes solid once they've moved")
	_mend_all()

	# The remote: thrown at a wall it drops on this side; nobody picks it up through one.
	var r := arena.remote
	_place(willow, 6.4, ROW, Vector2(1, 0))
	r.state = TVRemote.State.CARRIED
	r.carrier_pid = willow.pid
	await frames(3)
	arena.request_throw(willow, willow.facing)
	await frames(12)  # (before the thrower's grace is up and she grabs it back)
	check(r.state == TVRemote.State.DROPPED and Iso.local_to_tile(r.position).x < WALL_I,
		"a remote thrown at a wall drops on the thrower's side")
	_park(willow)
	r.state = TVRemote.State.DROPPED
	r.carrier_pid = 0
	r.position = _at(7.16, 12.5)
	r.timer = 999.0
	_place(claw, 6.57, 12.5, Vector2(1, 0))
	await frames(30)
	check(r.state == TVRemote.State.DROPPED, "nobody picks up the remote through a wall (%.1f px away)" % Iso.fdist(claw.position, r.position))
	_park(claw)
	r.position = _at(12.5, 8.8)

	_check_layout()
	await _check_nav()

	# The Farmhouse: stone (the chimney) and the outside walls never break.
	await _start("farmhouse", ["biscuit"], ["claw"])
	var stone := arena.level.wall_panels.filter(func(p: WallPanel) -> bool: return p.surface == WallRun.Surface.STONE)
	var outside := arena.level.wall_panels.filter(func(p: WallPanel) -> bool: return p.surface == WallRun.Surface.EXTERIOR)
	var survived := true
	for p: WallPanel in stone + outside:
		arena._damage_furniture(p, 150.0)
		survived = survived and not p.wrecked and p.hp == p.max_hp
	check(stone.size() == 4 and outside.size() > 0 and survived,
		"stone (%d panels) and outside walls (%d) never break" % [stone.size(), outside.size()])
	_check_layout()
	await _check_nav()
	_finish()


# ================================================================ helpers

## Starts a practice match on `map` with those pets and robots (as bots) and
## you as Willow, then stops everyone moving on their own.
func _start(map: String, pets: Array, robots: Array) -> void:
	if Match.current:
		Net.leave()
		await frames(10)
	Net.local_char = "willow"
	Net.practice()
	await frames(5)
	Net.set_map(map)
	for c in pets:
		Net.add_bot(Roster.Team.PETS)
	for c in robots:
		Net.add_bot(Roster.Team.ROBOTS)
	var wanted := {Roster.Team.PETS: pets.duplicate(), Roster.Team.ROBOTS: robots.duplicate()}
	for id: int in Net.roster:
		var e: Dictionary = Net.roster[id]
		if e["bot"] and not wanted[e["team"]].is_empty():
			e["char"] = wanted[e["team"]].pop_front()
	Net.start_match()
	while Match.current == null or Match.current.phase != Match.Phase.WAR:
		await frames(10)
	arena = Match.current
	cast.clear()
	for p: Player in arena.players.values():
		p.brain = Controls.new()
		cast[p.char_id] = p
		_park(p)
	arena.remote.timer = 999.0
	await frames(3)


func _at(i: float, j: float) -> Vector2:
	return Iso.tile_to_local(Vector2(i, j))


func _place(p: Player, i: float, j: float, facing_tiles: Vector2) -> void:
	p.position = _at(i, j)
	p._net_pos = p.position
	p.facing = Iso.to_floor(Iso.tile_to_local(facing_tiles)).normalized()
	p.hp = p.max_hp
	p.invuln = 0.0
	p.stun = 0.0
	p.knock_vel = Vector2.ZERO
	p.attack_cd = 0.0
	p.special_cd = 0.0
	p.melee_cd = 0.0


## Out of the way, in the dining room (the back room).
func _park(p: Player) -> void:
	var k := p.pid % 5
	_place(p, 1.5 + k * 0.9, 2.5 + (k % 2) * 1.2, Vector2(1, 0))


func _heal_all() -> void:
	for p: Player in arena.players.values():
		p.hp = p.max_hp


func _panel(j: float) -> WallPanel:
	return arena.level.wall_at(_at(WALL_I, j))


func _mend(p: WallPanel) -> void:
	arena._cl_furniture_state(p.index, 1.0, false, 0.0, 0)
	p.hp = p.max_hp


func _mend_all() -> void:
	for p in arena.level.wall_panels:
		if p.max_hp > 0.0 and (p.wrecked or p.hp < p.max_hp):
			_mend(p)


func _damaged() -> Array[WallPanel]:
	var out: Array[WallPanel] = []
	for p in arena.level.wall_panels:
		if p.max_hp > 0.0 and (p.wrecked or p.hp < p.max_hp):
			out.append(p)
	return out


func _path_len(path: PackedVector2Array) -> float:
	var total := 0.0
	for k in range(1, path.size()):
		total += Iso.fdist(path[k - 1], path[k])
	return total


## Bases and the remote's rug are never where a wall hides them, and doorways are wide enough.
func _check_layout() -> void:
	var level := arena.level
	var hidden := []
	for zone: BaseZone in [level.home, level.bases[0], level.bases[1]]:
		for n in level.entities.get_children():
			if n is WallSlice and n.hides(zone.position):
				hidden.append(zone.name)
				break
	var narrow := []
	for run in level.get_node("Walls").get_children():
		for d in (run as WallRun).doors:
			if d.y - d.x < 2.0 - 0.01:
				narrow.append("%s %s" % [run.name, d])
	check(hidden.is_empty() and narrow.is_empty(),
		"%s: no wall hides a base or the rug, and doors are 2+ tiles wide %s %s" % [Net.map_id, hidden, narrow])


func _check_nav() -> void:
	await frames(5)
	var level := arena.level
	var ok := true
	for base in level.bases:
		ok = ok and _path_len(level.find_path(level.home.position, base.position)) > 0.0
	check(ok, "%s: the bots' map leads from the rug to both bases" % Net.map_id)
