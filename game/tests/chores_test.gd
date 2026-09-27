extends Node
## Cleanup-by-specialty test (run by tools/smoke_test.sh):
##   godot --headless --fixed-fps 60 --path game res://tests/chores_test.tscn -- --war=300
##
## Plays the Family Home with all eight characters standing still (each
## driven by a puppet the test steers), and checks the rules in Chores:
## where the mess comes from during the war, then, in the cleanup, who owns
## what, how fast owners, helpers and everyone work, the two-helper rule,
## idle owners, a wall hole's three-step repair, each owner's own move
## (Zoomba's vacuum, Willow's swat, Pepper's fetch and carry, Bass's THUMP
## through a wall), and spare hands when two people pick the same character.

var _passed := 0
var _failed := 0
var arena: Match
var cast: Dictionary = {}  # character id -> Player
var puppets: Dictionary = {}  # character id -> Puppet


## Steers one character for the test: which way to walk, and whether to hold interact.
class Puppet extends Controls:
	var move := Vector2.ZERO
	var hold := false

	func think() -> Dictionary:
		var d := super.think()
		d["move"] = move
		d["interact"] = hold
		return d


func _ready() -> void:
	get_tree().current_scene = null
	get_tree().create_timer(150.0, true, false, true).timeout.connect(func() -> void:
		check(false, "finished within two and a half minutes")
		_finish())
	_run.call_deferred()


func check(ok: bool, what: String) -> void:
	if ok:
		_passed += 1
		print("  PASS  chores: %s" % what)
	else:
		_failed += 1
		print("  FAIL  chores: %s" % what)


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _finish() -> void:
	print("[chores] %d passed, %d failed" % [_passed, _failed])
	Audio.quit_game()


func _run() -> void:
	await _start(["biscuit", "pepper", "kiwi"], ["zoomba", "bass", "claw", "butler"])
	var level := arena.level

	# ------------------------------------------------------------ mess sources
	# Knocking a couch about shakes a pillow loose every 25 damage, three at most.
	var couch := _furniture("Couch")
	var claw: Player = cast["claw"]
	_place(claw, 12.6, 14.8)
	var pillows := func() -> int: return _count("pillow")
	for k in 3:
		arena._damage_furniture(couch, 25.0, claw)
	check(pillows.call() == 3, "25 damage at a time shakes a pillow off the couch each time (%d)" % pillows.call())
	couch.hp = couch.max_hp
	arena._damage_furniture(couch, 30.0, claw)
	check(pillows.call() == 3 and not couch.wrecked, "...until its budget of three runs out")
	check(couch.chain() == [Chores.Chore.SOFT], "a saggy couch is a job for Biscuit")
	var table := _furniture("CoffeeTable")
	arena._damage_furniture(table, 50.0, claw)
	check(table.wrecked and table.chain() == [Chores.Chore.LIFT, Chores.Chore.REPAIR],
		"a wrecked table is the Claw's to stand up, then Unit-7's to fix")
	check(_count("crumbs") == 1, "a wreck leaves crumbs")
	check(_count_chore(Chores.Chore.CLUTTER) == 2, "...and sheds its clutter (%d)" % _count_chore(Chores.Chore.CLUTTER))
	# A KO pile on top of another just makes it bigger.
	var before := arena.debris.size()
	arena._spawn_debris("fur", _at(10.5, 11.0))
	var pile := arena._nearest_debris(_at(10.5, 11.0), 20.0, "fur", -1)
	arena._spawn_debris("fur", pile.position)
	check(arena.debris.size() == before + 1 and is_equal_approx(pile.weight, 0.5), "a second KO pile merges into the first")
	# A crash leaves a scuff (one per spot), and any hit to a wall knocks its picture down.
	var pepper: Player = cast["pepper"]
	_place(pepper, 9.4, 14.2)
	var chair := _furniture("ArmchairPets")
	arena._srv_furniture_hit(chair.index, 18.0, pepper.pid, -1)
	check(_count("scuff") == 0 and chair.hp == chair.max_hp, "a crash report nobody was knocked into is ignored")
	arena._knocked_at[pepper.pid] = arena.work_clock
	arena._srv_furniture_hit(chair.index, 18.0, pepper.pid, -1)
	arena._srv_furniture_hit(chair.index, 18.0, pepper.pid, -1)
	check(_count("scuff") == 1 and chair.hp == chair.max_hp - Player.CRASH_DAMAGE,
		"crashing into furniture leaves a scuff and a dent (once per crash)")
	var pic := _item("PicLivingW1")
	var panel: WallPanel = null
	for idx: int in arena._pictures:
		if pic in arena._pictures[idx]:
			panel = level.furniture[idx]
	check(panel != null, "the picture hangs on a wall panel")
	arena._srv_furniture_hit(panel.index, 0.0, pepper.pid, 0)
	check(pic.knocked and pic.chore() == Chores.Chore.HIGH, "even a weak hit on a wall knocks its picture down (Kiwi's job)")
	check(not panel.cracked() and not panel.wrecked, "...without hurting the wall")
	# A hard knock flings a light thing into a stray; a nudge only tips it over.
	var lamp := _item("LampA")
	var vase := _item("LampB")
	arena._knock(lamp, Vector2(1, 1), 300.0)
	arena._knock(vase, Vector2(1, 1), 60.0)
	await frames(20)
	check(lamp.stray() and not vase.stray(), "a hard hit flings things 2-4 tiles; a nudge just tips them over")
	var plant := _item("PlantA")
	var dirt_before := _count("dirt")
	arena._knock(plant, Vector2(1, 0), 60.0)
	check(_count("dirt") == dirt_before + 1, "a knocked plant spills dirt (Zoomba's)")

	# ------------------------------------------------------------- the whistle
	# Keep something far away dirty all along, so the house is never finished early.
	_mess("scorch", 16.0, 2.0)
	_mess("scorch", 16.5, 2.5)
	arena._end_war()
	arena.time_left = 0.0
	while arena.phase != Match.Phase.CLEANUP:
		await frames(5)
	arena.time_left = 999.0
	for id: String in cast:
		var want := Chores.owned_by(id)
		check(arena.my_chore(cast[id]) == want, "%s owns %s" % [id, Chores.Chore.keys()[want]])
	check(arena.chore_owners.size() == 8, "every chore has an active owner")

	# ------------------------------------------------------------ work rates
	var biscuit: Player = cast["biscuit"]
	var butler: Player = cast["butler"]
	var fur := _mess("fur", 11.0, 10.5)
	_place(biscuit, 11.0, 10.2)
	_refresh()
	var rate := await _rate(biscuit, fur, 30)
	check(absf(rate - Chores.HELPER_RATE) < 0.03, "a helper works at a fifth of the speed (%.2f)" % rate)
	_park(claw)
	var crack := _furniture("DenDesk")
	arena._damage_furniture(crack, 20.0, claw)
	check(crack.current_chore() == Chores.Chore.REPAIR, "a cracked desk is Unit-7's")
	_place(butler, 10.2, 5.4)
	_refresh()
	rate = await _rate(butler, crack, 30)
	check(absf(rate - Chores.OWNER_RATE) < 0.08, "its owner works at full speed (%.2f)" % rate)
	arena._last_work[butler.pid] = arena.work_clock - Chores.IDLE_TIME - 1.0
	await frames(2)
	await _rate(butler, crack, 8)
	check(butler.pid in arena.chore_owners.get(Chores.Chore.REPAIR, []) and crack.current_chore() == Chores.Chore.REPAIR,
		"an owner partway through a long job counts as working (before it's finished)")
	_park(butler)
	# Zoomba wanders off: floor mess is anyone's, at half speed, with his face faded on it.
	_refresh()
	arena._last_work[cast["zoomba"].pid] = arena.work_clock - Chores.IDLE_TIME - 1.0
	await frames(2)
	check(arena.chore_owners.get(Chores.Chore.FLOOR, []).is_empty() and cast["zoomba"].pid in arena.idle_owners.get(Chores.Chore.FLOOR, []),
		"an owner who's done nothing for 8 s stops counting")
	rate = await _rate(biscuit, fur, 20)
	check(absf(rate - Chores.ANYONE_RATE) < 0.05, "...and everyone does their chore at half speed (%.2f)" % rate)
	_park(biscuit)

	# ------------------------------------------------------ two pairs of hands
	var shelf := _item("Bookshelf")
	arena._knock(shelf, Vector2(0, 1), 300.0)
	await frames(20)
	check(shelf.chore() == Chores.Chore.LIFT, "a knocked-over bookshelf is the Claw's to lift")
	var spot := level.walkable(shelf.position + Iso.to_screen(Vector2(0, 14)))
	_refresh()
	_place_at(biscuit, spot)
	rate = await _rate(biscuit, shelf, 30)
	check(rate == 0.0, "one helper alone can't lift it")
	_place_at(pepper, spot + Vector2(3, 0))
	pepper.focus_job = shelf
	puppets["pepper"].hold = true
	rate = await _rate(biscuit, shelf, 30)
	puppets["pepper"].hold = false
	pepper.focus_job = null
	check(rate > 0.3 and rate < 0.55, "two helpers can, at a fifth of the speed each (%.2f)" % rate)
	_park(biscuit)
	_park(pepper)
	await frames(2)

	# ---------------------------------------------------------- a wall's repair
	var hole := level.wall_at(_at(7.0, 15.5))
	arena._cl_furniture_state(hole.index, 0.0, true, 0.0, 0, 0)
	await frames(2)
	check(hole.chain() == [Chores.Chore.LIFT, Chores.Chore.REPAIR, Chores.Chore.HIGH], "a hole takes lift, tape, then paint")
	var kiwi: Player = cast["kiwi"]
	_refresh()
	_place(kiwi, 8.0, 15.5)
	rate = await _rate(kiwi, hole, 30)
	check(rate == 0.0 and hole.step == 0, "Kiwi can't paint before the new panel is in")
	_park(kiwi)
	for step in [["claw", Chores.Chore.LIFT], ["butler", Chores.Chore.REPAIR], ["kiwi", Chores.Chore.HIGH]]:
		var who: Player = cast[step[0]]
		check(hole.current_chore() == step[1], "next: %s (%s)" % [Chores.Chore.keys()[step[1]], step[0]])
		_place(who, 8.0, 15.5)
		_refresh()
		who.focus_job = hole
		puppets[step[0]].hold = true
		await frames(int(60 * 2.2))
		puppets[step[0]].hold = false
		who.focus_job = null
		_park(who)
		await frames(3)
	check(hole.current_chore() == Chores.Chore.NONE and not hole.wrecked, "...and three owners mend it in about 6 s")

	# ------------------------------------------------------------ owner moves
	# Zoomba vacuums floor mess by driving over it (but not stains).
	var zoomba: Player = cast["zoomba"]
	var dust := _mess("fur", 12.0, 11.0)
	var stain := _mess("scorch", 12.0, 11.35)
	_place(zoomba, 12.0, 9.8)
	_refresh()
	arena._last_work[zoomba.pid] = arena.work_clock - Chores.IDLE_TIME - 1.0
	await frames(2)
	check(zoomba.pid in arena.idle_owners.get(Chores.Chore.FLOOR, []), "(Zoomba has wandered off)")
	puppets["zoomba"].move = Vector2(-1, 1).normalized()  # along +j
	await frames(25)
	puppets["zoomba"].move = Vector2.ZERO
	await frames(2)
	check(not arena.is_open(dust), "Zoomba vacuums up fur by driving over it")
	check(arena.is_open(stain), "...but not stains")
	check(Chores.Chore.FLOOR in arena.chore_owners and zoomba.pid in arena.chore_owners[Chores.Chore.FLOOR],
		"...and doing his job again makes him count again")
	_park(zoomba)
	# Willow bats clutter away by running over it.
	var willow: Player = cast["willow"]
	var book := _mess("book", 13.0, 10.0)
	_place(willow, 12.2, 10.0)
	puppets["willow"].move = Iso.to_floor(Iso.tile_to_local(Vector2(1, 0))).normalized()
	await frames(20)
	puppets["willow"].move = Vector2.ZERO
	check(not arena.is_open(book), "Willow swats clutter away by running over it")
	_park(willow)
	# Pepper: a tipped vase pops back up; a stray lamp goes home in his mouth.
	_place_at(pepper, vase.position)
	await frames(3)
	check(not vase.knocked, "Pepper stands a tipped-over thing up just by touching it")
	_place_at(pepper, lamp.position)
	await frames(3)
	check(lamp.carrier == pepper.pid and lamp.knocked, "...and picks up a stray in his mouth")
	var r := arena.remote
	r.state = TVRemote.State.DROPPED
	r.position = pepper.position
	await frames(5)
	check(r.carrier_pid != pepper.pid, "...and can't grab the remote while he's carrying something")
	arena._reset_remote()
	puppets["pepper"].hold = true
	await frames(3)
	puppets["pepper"].hold = false
	await frames(2)
	check(lamp.carrier == 0 and lamp.knocked, "...can put it down by pressing the button")
	await frames(95)  # (he won't grab it straight back)
	_place_at(pepper, lamp.position)
	await frames(3)
	check(lamp.carrier == pepper.pid, "...and pick it up again")
	_place_at(pepper, lamp.home + Iso.to_screen(Vector2(8, 0)))
	await frames(3)
	check(not lamp.knocked and lamp.carrier == 0, "...and drops it in its place")
	_park(pepper)
	# Bass THUMPs stains away, through a wall.
	var bass: Player = cast["bass"]
	var far_side := _mess("scorch", 6.4, 14.0)
	_place(bass, 7.9, 14.0)
	check(not level.wall_between(bass.position, far_side.position).is_empty(), "(the stain is behind the wall)")
	puppets["bass"].hold = true
	await frames(3)
	puppets["bass"].hold = false
	await frames(2)
	check(not arena.is_open(far_side), "Bass's THUMP cleans a stain on the other side of a wall")
	_park(bass)

	# ---------------------------------------------------------- the cap
	var full := arena.debris.size()
	for k in Match.MAX_DEBRIS - full:
		arena._cl_debris_add(arena._next_debris_id, "scuff", _at(2.0 + (k % 10) * 0.4, 9.0 + floori(k / 10.0) * 0.4))
		arena._next_debris_id += 1
	var nearest := arena._nearest_debris(_at(15.0, 2.0), INF, "", Chores.Chore.STAIN)
	var w := nearest.weight
	arena._spawn_debris("scorch", _at(15.0, 2.0))
	check(arena.debris.size() == Match.MAX_DEBRIS and nearest.weight > w, "a full house grows the nearest pile instead")

	# ------------------------------------------------------------ spare hands
	await _start(["willow", "pepper"], ["zoomba", "bass"])
	var willows := arena.players.values().filter(func(p: Player) -> bool: return p.char_id == "willow")
	_mess("pillow", 12.0, 12.0)  # Biscuit's, and there's no Biscuit
	arena._assign_chores()
	var chores := willows.map(func(p: Player) -> int: return arena.my_chore(p))
	check(willows.size() == 2 and Chores.Chore.CLUTTER in chores and Chores.Chore.SOFT in chores,
		"when two play Willow, one of them takes the biggest chore nobody owns (%s)" % str(chores))
	check(arena.my_chore(arena.local_player()) == Chores.Chore.CLUTTER, "...and it's the bot, not the person, who switches")
	_finish()


# ================================================================ helpers

## Starts a practice match on the Family Home with those pets and robots (as
## bots) and you as Willow, with everyone driven by a puppet.
func _start(pets: Array, robots: Array) -> void:
	if Match.current:
		Net.leave()
		await frames(10)
	Net.local_char = "willow"
	Net.practice()
	await frames(5)
	Net.set_map("family_home")
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
	arena.pickups_on = false  # nothing random turning up mid-test
	cast.clear()
	puppets.clear()
	for p: Player in arena.players.values():
		var puppet := Puppet.new()
		p.brain = puppet
		puppets[p.char_id] = puppet
		cast[p.char_id] = p
		_park(p)
	arena.remote.timer = 999.0
	await frames(3)


func _at(i: float, j: float) -> Vector2:
	return Iso.tile_to_local(Vector2(i, j))


func _place(p: Player, i: float, j: float) -> void:
	_place_at(p, _at(i, j))


func _place_at(p: Player, pos: Vector2) -> void:
	p.position = pos
	p._net_pos = pos
	p.knock_vel = Vector2.ZERO
	arena._prev_pos[p.pid] = pos


## Out of the way, in the dining room (the back room).
func _park(p: Player) -> void:
	var k := p.pid % 5
	_place(p, 1.5 + k * 0.9, 2.5 + (k % 2) * 1.2)


## Everyone counts as busy (so nobody's chore turns into anyone's by accident).
func _refresh() -> void:
	for pid: int in arena.players:
		arena._last_work[pid] = arena.work_clock
	arena._update_owners()


## Holds interact for `n` frames and returns the work rate measured on `job`
## (progress per second x its time at rate 1).
func _rate(p: Player, job: Object, n: int) -> float:
	var puppet: Puppet = puppets[p.char_id]
	var start := arena.progress_of(job)
	p.focus_job = job
	puppet.hold = true
	await frames(n)
	puppet.hold = false
	await frames(1)
	p.focus_job = null
	var done := arena.progress_of(job) - start
	return done * arena.time_of(job) / (n / 60.0)


func _mess(kind: String, i: float, j: float) -> Debris:
	var id := arena._next_debris_id
	arena._next_debris_id += 1
	arena._cl_debris_add(id, kind, _at(i, j))
	return arena.debris[id]


func _count(kind: String) -> int:
	return arena.debris.values().filter(func(d: Debris) -> bool: return d.kind == kind).size()


func _count_chore(c: int) -> int:
	return arena.debris.values().filter(func(d: Debris) -> bool: return d.chore == c).size()


func _furniture(node_name: String) -> Furniture:
	for f in arena.level.furniture:
		if f.name == node_name:
			return f
	return null


func _item(node_name: String) -> MessItem:
	for item in arena.level.mess_items:
		if item.name == node_name:
			return item
	return null
