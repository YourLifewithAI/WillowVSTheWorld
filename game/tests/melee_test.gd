extends Node
## Close-up move test (run by tools/smoke_test.sh):
##   godot --headless --fixed-fps 60 --path game res://tests/melee_test.tscn -- --war=120
##
## A practice match with one pet and one robot, both standing still. Each
## check turns the attacker into a character, puts a target where the move
## should (or shouldn't) reach, swings once and looks at what happened:
## every move lands, and each effect (pounce, heal, steal, heavy shelves,
## all-round spin, flip, reel in, blast away) does its job.

var _passed := 0
var _failed := 0
var arena: Match
var pet: Player
var robot: Player
var spot := Vector2.ZERO


func _ready() -> void:
	get_tree().current_scene = null
	get_tree().create_timer(60.0, true, false, true).timeout.connect(func() -> void:
		check(false, "finished within a minute")
		_finish())
	_run.call_deferred()


func check(ok: bool, what: String) -> void:
	if ok:
		_passed += 1
		print("  PASS  melee: %s" % what)
	else:
		_failed += 1
		print("  FAIL  melee: %s" % what)


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _finish() -> void:
	print("[melee] %d passed, %d failed" % [_passed, _failed])
	Audio.quit_game()


func _run() -> void:
	Net.local_char = "willow"
	Net.practice()
	await frames(5)
	Net.add_bot(Roster.Team.ROBOTS)
	Net.start_match()
	while Match.current == null or Match.current.phase != Match.Phase.WAR:
		await frames(10)
	arena = Match.current
	for p: Player in arena.players.values():
		p.brain = Controls.new()  # Nobody moves on their own.
		if p.team == Roster.Team.PETS:
			pet = p
		else:
			robot = p
	spot = _open_spot()
	# Keep the remote out of the way (touching it picks it up).
	arena.remote.position = spot + Iso.to_screen(Vector2(0, 120))
	arena.remote.state = TVRemote.State.DROPPED
	arena.remote.timer = 999.0

	# Every close-up move lands on someone right in front.
	for id: String in Roster.CHARACTERS.keys():
		var c: Dictionary = Roster.get_char(id)
		var a := pet if c["team"] == Roster.Team.PETS else robot
		var t := robot if a == pet else pet
		await _setup(a, id, t, 12.0)
		var hp := t.hp
		var charge := a.gag_charge
		a._do_melee()
		await frames(8)
		check(t.hp < hp and a.gag_charge > charge, "%s's %s hurts (%d -> %d HP) and charges the gag" % [c["name"], c["melee"]["name"], hp, t.hp])

	# Willow's pounce reaches past a normal swipe, and she lands where she hit.
	await _setup(pet, "willow", robot, 38.0)
	var start := pet.position
	var hp := robot.hp
	pet._do_melee()
	await frames(12)
	check(robot.hp < hp and Iso.fdist(pet.position, start) > 15.0,
		"Pounce hops forward and hits someone out of swiping reach (moved %.0f px)" % Iso.fdist(pet.position, start))

	# Biscuit heals by kneading.
	await _setup(pet, "biscuit", robot, 12.0)
	pet.max_hp = 150
	pet.hp = 100
	pet._do_melee()
	await frames(8)
	check(pet.hp > 100, "Making Biscuits heals Biscuit (100 -> %d HP)" % pet.hp)

	# Pepper steals the remote from whoever is carrying it.
	await _setup(pet, "pepper", robot, 12.0)
	arena.remote.state = TVRemote.State.CARRIED
	arena.remote.carrier_pid = robot.pid
	await frames(2)
	pet._do_melee()
	await frames(8)
	check(arena.remote.state == TVRemote.State.CARRIED and arena.remote.carrier_pid == pet.pid, "Gimme! snatches the remote")
	arena.remote.position = spot + Iso.to_screen(Vector2(0, 120))
	arena.remote.state = TVRemote.State.DROPPED
	arena.remote.carrier_pid = 0
	arena.remote.timer = 999.0
	await frames(2)
	check(not pet.carrying, "...and hands it back to the test afterwards")

	# Kiwi's pecks topple even heavy things.
	var heavy: MessItem = null
	for item in arena.level.mess_items:
		if item.heavy and not item.knocked:
			heavy = item
			break
	if heavy:
		await _setup(pet, "kiwi", robot, 200.0)
		pet.position = heavy.position + Iso.to_screen(Vector2(-12, 0))
		pet._net_pos = pet.position
		pet.facing = Vector2.RIGHT
		await frames(2)
		pet._do_melee()
		await frames(8)
		check(heavy.knocked, "Peck Peck Peck knocks over the heavy %s" % heavy.sprite_name)
	else:
		check(false, "the living room has a heavy item to peck over")

	# Zoomba's spin hits someone behind it.
	await _setup(robot, "zoomba", pet, -12.0)
	hp = pet.hp
	robot._do_melee()
	await frames(8)
	check(pet.hp < hp, "Spot Clean hits all round (someone behind: %d -> %d HP)" % [hp, pet.hp])

	# Unit-7 flips people into the air, stunned.
	await _setup(robot, "butler", pet, 12.0)
	robot._do_melee()
	await frames(3)
	check(pet.stun > 0.4 and pet._hop_t > 0.0, "Spatula Flip pops the target up, stunned (%.2f s)" % pet.stun)

	# The Claw reels people in.
	await _setup(robot, "claw", pet, 26.0)
	var before := Iso.fdist(pet.position, robot.position)
	robot._do_melee()
	await frames(20)
	var after := Iso.fdist(pet.position, robot.position)
	check(after < before - 8.0, "Yoink! reels the target in (%.0f -> %.0f px)" % [before, after])

	# Bass blasts people away.
	await _setup(robot, "bass", pet, 14.0)
	before = Iso.fdist(pet.position, robot.position)
	robot._do_melee()
	await frames(30)
	after = Iso.fdist(pet.position, robot.position)
	check(after > before + 25.0, "Feedback blasts the target away (%.0f -> %.0f px)" % [before, after])

	# Someone outside the cone is safe.
	await _setup(robot, "butler", pet, -12.0)
	hp = pet.hp
	robot._do_melee()
	await frames(8)
	check(pet.hp == hp, "a close-up move misses someone behind you (outside its cone)")
	_finish()


## Gives `a` character `id`'s close-up move, facing right at `spot`, with `t` standing
## `dist` floor px in front (negative: behind), both healthy and ready.
func _setup(a: Player, id: String, t: Player, dist: float) -> void:
	# Only the close-up move changes hands (the rest of the character stays put).
	a.data = a.data.duplicate(true)
	a.data["melee"] = Roster.get_char(id)["melee"].duplicate(true)
	for p: Player in [a, t]:
		p.hp = p.max_hp
		p.invuln = 0.0
		p.stun = 0.0
		p.knock_vel = Vector2.ZERO
		p.melee_cd = 0.0
		p.attack_cd = 0.0
		p._hop_t = 0.0
		p.stealthed = false
	a.position = spot
	a.facing = Vector2.RIGHT
	t.position = spot + Iso.to_screen(Vector2(dist, 0))
	t.facing = Vector2.LEFT
	a._net_pos = a.position
	t._net_pos = t.position
	a.gag_charge = 0.0
	await frames(2)


## A stretch of floor with nothing in the way for 50 px either side.
func _open_spot() -> Vector2:
	var level := arena.level
	var best := level.home.position
	for dj in range(-6, 7):
		for di in range(-6, 7):
			var c := level.home.position + Iso.to_screen(Vector2(di * 16.0, dj * 16.0))
			if not level.room.contains(c, 3.0):
				continue
			var clear := true
			for k in range(-5, 6):
				var p := c + Iso.to_screen(Vector2(k * 10.0, 0))
				if level.furniture_at(p) != null or Iso.fdist(p, level.home.position) < 40.0:
					clear = false
					break
			if clear:
				return c
	return best
