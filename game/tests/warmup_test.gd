extends Node
## Warm-up test (run by tools/smoke_test.sh):
##   godot --headless --fixed-fps 60 --path game res://tests/warmup_test.tscn
##
## P1 joins on a fake controller while a Joy-Con sits connected but unjoined:
## starting asks first. The warm-up then: the bots stand still, the clock
## doesn't run, P1's super is ready, nobody gets knocked out (and hurt
## characters heal), the remote doesn't score, one of each powerup lies around,
## and what P1 tries gets ticked off. The Joy-Con joins partway through (the
## warm-up reloads with two people), both press + and a fresh match starts,
## with the bots playing and the clock running.

const PAD := 40
const JOYCON := 41

var _passed := 0
var _failed := 0


func _ready() -> void:
	get_tree().current_scene = null
	Seats.add_fake_device(PAD, Seats.Kind.FULL)
	get_tree().create_timer(120.0, true, false, true).timeout.connect(func() -> void:
		check(false, "finished within two minutes")
		_finish())
	_run.call_deferred()


func check(ok: bool, what: String) -> void:
	if ok:
		_passed += 1
		print("  PASS  warmup: %s" % what)
	else:
		_failed += 1
		print("  FAIL  warmup: %s" % what)


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func button(device: int, b: int, down: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.device = device
	e.button_index = b as JoyButton
	e.pressed = down
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func tap(device: int, b: int) -> void:
	button(device, b, true)
	await frames(3)
	button(device, b, false)
	await frames(3)


func _finish() -> void:
	print("[warmup] %d passed, %d failed" % [_passed, _failed])
	Audio.quit_game()


## Waits for a match that isn't `old` to reach the war.
func _next_match(old) -> Match:
	var waited := 0
	while (Match.current == null or Match.current == old or Match.current.phase != Match.Phase.WAR) and waited < 900:
		await frames(10)
		waited += 10
	return Match.current if Match.current != old else null


func _run() -> void:
	Net.local_char = "willow"
	Net.map_id = "living_room"
	Net.practice()
	await frames(10)
	await tap(PAD, Seats.B_SOUTH)
	check(Seats.seat(0).device == PAD, "P1 joins on a controller")
	Net.add_bot(Roster.Team.ROBOTS)
	for entry: Dictionary in Net.roster.values():
		if entry["bot"]:
			entry["char"] = "butler"
	# A Joy-Con is connected, but nobody's joined with it.
	Seats.add_fake_device(JOYCON, Seats.Kind.JOYCON_L)
	await frames(3)
	await tap(PAD, Seats.B_START)
	await frames(260)
	check(Match.current == null, "starting with a Joy-Con left out asks first (no countdown)")
	await tap(PAD, Seats.B_START)
	var arena := await _next_match(null)
	check(arena != null and arena.warmup, "pressing + again goes ahead: a warm-up")
	if arena == null:
		_finish()
		return
	var me: Player = arena.local_players()[0]
	var robot: Player = null
	for p: Player in arena.players.values():
		if p.is_bot:
			robot = p
	check(robot != null and not robot.brain is BotBrain, "the bots are practice dummies")
	var clock := arena.time_left
	var at := robot.position
	await frames(60)
	check(arena.time_left == clock and robot.position.distance_to(at) < 0.5, "the clock doesn't run and the bot stands still")
	check(me.gag_charge >= 1.0, "your super's ready to try")

	# Nobody gets knocked out, and the hurt heal back up.
	for k in 30:
		robot.invuln = 0.0
		arena._srv_hit(me.pid, robot.pid, 0, Vector2.RIGHT, false)
	check(robot.hp == 1 and not robot.is_ko, "hit over and over, the bot hangs on at %d HP" % robot.hp)
	await frames(150)
	check(robot.hp == robot.max_hp, "...and heals back up a couple of seconds later")

	# The remote can be carried home, but doesn't score.
	arena.remote.state = TVRemote.State.CARRIED
	arena.remote.carrier_pid = me.pid
	me.position = arena.level.bases[me.team].position
	me._net_pos = me.position
	await frames(roundi((Match.CHANNEL_TIME + 0.5) * 60.0))
	check(arena.scores == [0, 0] and arena.remote.state == TVRemote.State.HOME, "changing the channel doesn't score (and the remote goes back)")
	var kinds := {}
	for pu: Pickup in arena.pickups.values():
		kinds[pu.kind] = true
	var war_kinds := Pickups.MENU.filter(func(k: int) -> bool: return Pickups.in_war(k))
	check(kinds.size() == war_kinds.size(), "one of each powerup is lying around (%d of %d)" % [kinds.size(), war_kinds.size()])

	# The checklist ticks off what you try.
	me.position = arena.level.home.position + Iso.to_screen(Vector2(0, 60))
	me._net_pos = me.position
	await tap(PAD, Seats.B_WEST)
	await tap(PAD, Seats.B_NORTH)
	await tap(PAD, Seats.B_SOUTH)
	await tap(PAD, Seats.B_LEFT_SHOULDER)
	await frames(10)
	check(me.tried.has("attack") and me.tried.has("special") and me.tried.has("dash") and me.tried.has("gag"),
		"fire, special, dash and super get ticked off (%s)" % [me.tried.keys()])

	# J fires here (P1 alone hears the keyboard too): it mustn't add a keyboard player.
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = KEY_J
		e.physical_keycode = KEY_J
		e.pressed = down
		Input.parse_input_event(e)
		Input.flush_buffered_events()
		await frames(4)
	await frames(10)
	check(Seats.seats.size() == 1 and Match.current == arena, "J on the keyboard fires, and doesn't join anyone mid-warm-up")

	# The Joy-Con joins partway through: the warm-up reloads with them in it.
	await tap(JOYCON, Seats.B_SOUTH)
	var again := await _next_match(arena)
	check(again != null and again.warmup and again.local_players().size() == 2, "a Joy-Con joining mid-warm-up reloads it with two people")
	if again == null:
		_finish()
		return
	arena = again
	await frames(20)
	await tap(PAD, Seats.B_START)
	await frames(5)
	check(arena.ready_pids.size() == 1 and Match.current == arena, "P1 presses +: ready (1 of 2), still warming up")
	await tap(PAD, Seats.B_START)
	await frames(5)
	check(arena.ready_pids.is_empty(), "+ again: not ready after all")
	await tap(PAD, Seats.B_START)
	await tap(JOYCON, Seats.B_BACK)
	var real := await _next_match(arena)
	check(real != null and not real.warmup, "everyone's ready: a fresh match starts")
	if real:
		var bot_brains := real.players.values().filter(func(p: Player) -> bool: return p.is_bot and p.brain is BotBrain)
		var t0 := real.time_left
		await frames(60)
		check(not bot_brains.is_empty() and real.time_left < t0, "...with the bots playing and the clock running")
	_finish()
