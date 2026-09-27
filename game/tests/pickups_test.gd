extends Node
## Pickups test (run by tools/smoke_test.sh):
##   godot --headless --fixed-fps 60 --path game res://tests/pickups_test.tscn -- --war=300
##
## Plays the Family Home with everyone standing still, puts each kind of
## pickup (see Pickups) under someone's feet and checks what it does: the
## Zoomies, a Snack, a Treat, Bubble Wrap soaking up hits, someone else's
## weapon (which the host only accepts while it lasts), then in the cleanup a
## turbo tool that only its chore's owner can take (and that makes them
## faster at it) and roller skates. Also: they turn up on their own, away from
## the bases, pop when nobody takes them, go at the whistle, and bots fetch them.

var _passed := 0
var _failed := 0
var arena: Match
var cast: Dictionary = {}  # character id -> Player
var puppets: Dictionary = {}  # character id -> Puppet


class Puppet extends Controls:
	var move := Vector2.ZERO
	var hold := false
	var attack := false

	func think() -> Dictionary:
		var d := super.think()
		d["move"] = move
		d["interact"] = hold
		d["attack"] = attack
		attack = false
		return d


func _ready() -> void:
	get_tree().current_scene = null
	get_tree().create_timer(120.0, true, false, true).timeout.connect(func() -> void:
		check(false, "finished within two minutes")
		_finish())
	_run.call_deferred()


func check(ok: bool, what: String) -> void:
	if ok:
		_passed += 1
		print("  PASS  pickups: %s" % what)
	else:
		_failed += 1
		print("  FAIL  pickups: %s" % what)


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _finish() -> void:
	print("[pickups] %d passed, %d failed" % [_passed, _failed])
	Audio.quit_game()


func _run() -> void:
	await _start(["biscuit", "pepper"], ["zoomba", "butler", "bass"])
	var willow: Player = cast["willow"]
	var biscuit: Player = cast["biscuit"]
	var butler: Player = cast["butler"]

	# ------------------------------------------------------------ the war
	var took := await _give(willow, Pickups.Kind.ZOOMIES, "")
	check(took and willow.buff_mult == Pickups.ZOOMIES_SPEED, "the Zoomies make you faster")
	willow.hp = 10
	await _give(willow, Pickups.Kind.SNACK, "")
	check(willow.hp == 10 + Pickups.SNACK_HEAL, "a Snack heals (10 -> %d)" % willow.hp)
	willow.gag_charge = 0.1
	await _give(willow, Pickups.Kind.TREAT, "")
	check(willow.gag_charge >= 1.0, "a Treat gets your gag ready")
	# Bubble wrap soaks up hits before your health does.
	await _give(biscuit, Pickups.Kind.BUBBLE_WRAP, "")
	check(biscuit.shield == Pickups.SHIELD, "Bubble Wrap wraps you up (%d)" % biscuit.shield)
	var hp := biscuit.hp
	arena._apply_hit(butler, biscuit, {"damage": 30, "knock": 0.0}, Vector2.RIGHT)
	check(biscuit.hp == hp and biscuit.shield == Pickups.SHIELD - 30, "...and soaks up a hit")
	arena._apply_hit(butler, biscuit, {"damage": 30, "knock": 0.0}, Vector2.RIGHT)
	check(biscuit.hp == hp - 20 and biscuit.shield == 0, "...until it's used up (%d HP)" % biscuit.hp)
	# Someone else's weapon.
	biscuit.hp = biscuit.max_hp
	took = await _give(willow, Pickups.Kind.WEAPON, "biscuit")
	check(took and willow.weapon_spec()["name"] == "Catnip Bazooka" and willow.weapon_ability() == 4,
		"Willow picks up Biscuit's Catnip Bazooka")
	# She really fires it: a lobbed catnip rocket, like Biscuit's.
	_place(willow, 12.0, 14.0)
	willow.attack_cd = 0.0
	puppets["willow"].attack = true
	await frames(3)
	var shells := arena.level.entities.get_children().filter(func(n: Node) -> bool:
		return n is Projectile and n.shooter == willow)
	check(shells.size() == 1 and shells[0].lob and shells[0].ability == 4, "...and fires it: a lobbed rocket, like Biscuit's")
	await frames(90)
	_park(willow)
	var target: Player = cast["zoomba"]
	_place(target, 10.0, 12.0)
	target.invuln = 0.0
	hp = target.hp
	arena._srv_hit(willow.pid, target.pid, 4, Vector2.RIGHT, false)
	var bazooka := int(Roster.get_char("biscuit")["weapon"]["damage"])
	check(target.hp == hp - bazooka, "the host accepts a hit from it, at its damage (%d -> %d)" % [hp, target.hp])
	willow.borrow_t = -1.0
	target.invuln = 0.0
	hp = target.hp
	arena._srv_hit(willow.pid, target.pid, 4, Vector2.RIGHT, false)
	check(target.hp == hp and willow.weapon_ability() == 0, "...but not once it's run out (she's back to her laser)")
	_park(target)
	took = await _give(biscuit, Pickups.Kind.WEAPON, "biscuit")
	check(not took and arena.pickups.size() == 1, "nobody picks up their own weapon")
	arena._cl_pickup_remove(arena.pickups.keys()[0])

	# They turn up on their own, away from the bases and the rug, and pop.
	arena.pickups_on = true
	arena._pickup_t = 0.0
	await frames(2)
	arena.pickups_on = false
	check(arena.pickups.size() == 1, "pickups turn up on their own")
	if arena.pickups.size() == 1:
		var p0: Pickup = arena.pickups.values()[0]
		var at := p0.position
		var clear: bool = not arena.level.home.contains(at) and not arena.level.bases[0].contains(at) and not arena.level.bases[1].contains(at)
		check(clear, "...somewhere open, not on a base or the rug")
		p0.life = 0.01
		await frames(3)
		check(arena.pickups.is_empty(), "...and pop if nobody takes them")
	# A bot goes and gets one close by.
	var pepper: Player = cast["pepper"]
	_place(pepper, 11.0, 11.0)
	var bait := _drop(Pickups.Kind.SNACK, "", pepper.position + Iso.to_screen(Vector2(40, 0))).pickup_id
	pepper.brain = BotBrain.new(pepper, arena)
	for k in 30:
		await frames(6)
		if not arena.pickups.has(bait):
			break
	check(not arena.pickups.has(bait), "a bot fetches a pickup nearby")
	var pp := Puppet.new()
	pepper.brain = pp
	puppets["pepper"] = pp
	_park(pepper)
	# The whistle clears the floor.
	_drop(Pickups.Kind.ZOOMIES, "", Iso.tile_to_local(Vector2(14, 14)))
	_mess_far()
	arena._end_war()
	arena.time_left = 0.0
	while arena.phase != Match.Phase.CLEANUP:
		await frames(5)
	arena.time_left = 999.0
	check(arena.pickups.is_empty(), "the whistle clears away what's left on the floor")

	# ----------------------------------------------------------- the cleanup
	# A turbo tool for Unit-7's chore: only Unit-7 can take it...
	_refresh()
	var tool := _drop(Pickups.Kind.TOOL, str(Chores.Chore.REPAIR), Iso.tile_to_local(Vector2(10.2, 5.6)))
	var tool_id := tool.pickup_id
	var tool_at := tool.position
	_place_at(biscuit, tool_at)
	await frames(3)
	check(arena.pickups.has(tool_id), "a turbo tool is only for its chore's owner (Biscuit walks past)")
	_park(biscuit)
	_place_at(butler, tool_at)
	await frames(3)
	check(not arena.pickups.has(tool_id) and butler.turbo_t > 0.0 and butler.turbo_chore == Chores.Chore.REPAIR,
		"...who picks it up")
	# ...and makes them faster at it.
	var desk := _furniture("DenDesk")
	arena._damage_furniture(desk, 20.0, butler)
	_refresh()
	var rate := await _rate(butler, desk, 30)
	check(absf(rate - Pickups.TURBO_RATE) < 0.12, "a turbo owner works %.2fx as fast (%.2f)" % [Pickups.TURBO_RATE, rate])
	_park(butler)
	# With nobody owning a chore, its tool is anyone's.
	var free_tool := _drop(Pickups.Kind.TOOL, str(Chores.Chore.HIGH), Iso.tile_to_local(Vector2(12.0, 12.0))).pickup_id
	_place_at(biscuit, Iso.tile_to_local(Vector2(12.0, 12.0)))
	await frames(3)
	check(not arena.pickups.has(free_tool), "a tool for a chore nobody plays (Kiwi's) is anyone's")
	_park(biscuit)
	await _give(willow, Pickups.Kind.SKATES, "")
	check(willow.buff_mult == Pickups.SKATES_SPEED, "roller skates speed anyone up in the cleanup")
	arena.pickups_on = true
	arena._pickup_t = 0.0
	await frames(2)
	arena.pickups_on = false
	var kinds := arena.pickups.values().map(func(q: Pickup) -> int: return q.kind)
	check(kinds.size() == 1 and (kinds[0] == Pickups.Kind.TOOL or kinds[0] == Pickups.Kind.SKATES),
		"cleanup pickups are tools and skates (%s)" % str(kinds.map(func(k: int) -> String: return Pickups.Kind.keys()[k])))
	_finish()


# ================================================================ helpers

func _start(pets: Array, robots: Array) -> void:
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
	arena.pickups_on = false  # the test puts them where it wants them
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


func _drop(kind: int, arg: String, at: Vector2) -> Pickup:
	var id := arena._next_pickup_id
	arena._next_pickup_id += 1
	arena._cl_pickup_add(id, kind, arg, at, 20.0)
	return arena.pickups[id]


## Puts a pickup down in the living room and walks `p` onto it; did they take it?
func _give(p: Player, kind: int, arg: String) -> bool:
	_place(p, 12.0, 14.0)
	var pu := _drop(kind, arg, p.position + Iso.to_screen(Vector2(30, 0)))
	var id := pu.pickup_id
	await frames(2)
	_place_at(p, pu.position)
	await frames(3)
	_park(p)
	return not arena.pickups.has(id)


func _refresh() -> void:
	for pid: int in arena.players:
		arena._last_work[pid] = arena.work_clock
	arena._update_owners()


## Something far away that stays dirty, so the house is never finished early.
func _mess_far() -> void:
	for k in 2:
		var id := arena._next_debris_id
		arena._next_debris_id += 1
		arena._cl_debris_add(id, "scorch", _at(16.0 + k * 0.5, 2.0))


func _rate(p: Player, job: Object, n: int) -> float:
	var puppet: Puppet = puppets[p.char_id]
	var start := arena.progress_of(job)
	p.focus_job = job
	puppet.hold = true
	await frames(n)
	puppet.hold = false
	await frames(1)
	p.focus_job = null
	return (arena.progress_of(job) - start) * arena.time_of(job) / (n / 60.0)


func _furniture(node_name: String) -> Furniture:
	for f in arena.level.furniture:
		if f.name == node_name:
			return f
	return null
