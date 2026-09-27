extends Node
## Aiming test (run by tools/smoke_test.sh):
##   godot --headless --fixed-fps 60 --path game res://tests/aim_test.tscn -- --war=300 --pickups=0
##
## Willow joins on a fake Pro-style controller (so the keyboard drives her
## too: she's playing alone), with a robot to shoot at and a pet teammate to
## throw the remote to, neither of them moving. Checks: a tap fires when you
## let go, nudged onto an enemy just off to one side; holding attack plants
## you, the stick turns you and letting go fires that way; a second stick aims
## while the first one moves, and fires on the press; letting go of a
## diagonal's two keys a moment apart still faces the diagonal; the remote
## goes to a teammate roughly the way you throw it (a tap, or held to aim),
## and as far as it goes when nobody is that way.

const PAD := 30

var _passed := 0
var _failed := 0
var arena: Match
var me: Player
var robot: Player
var mate: Player
var spot := Vector2.ZERO


func _ready() -> void:
	get_tree().current_scene = null
	Seats.add_fake_device(PAD, Seats.Kind.FULL)
	get_tree().create_timer(90.0, true, false, true).timeout.connect(func() -> void:
		check(false, "finished within a minute and a half")
		_finish())
	_run.call_deferred()


func check(ok: bool, what: String) -> void:
	if ok:
		_passed += 1
		print("  PASS  aim: %s" % what)
	else:
		_failed += 1
		print("  FAIL  aim: %s" % what)


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func button(b: int, down: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.device = PAD
	e.button_index = b as JoyButton
	e.pressed = down
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func tap(b: int) -> void:
	button(b, true)
	await frames(3)
	button(b, false)
	await frames(3)


func stick(which: String, dir: Vector2) -> void:
	var axes := [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y] if which == "left" else [JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y]
	for k in 2:
		var e := InputEventJoypadMotion.new()
		e.device = PAD
		e.axis = axes[k]
		e.axis_value = dir.x if k == 0 else dir.y
		Input.parse_input_event(e)
	Input.flush_buffered_events()


func _finish() -> void:
	print("[aim] %d passed, %d failed" % [_passed, _failed])
	Audio.quit_game()


## Degrees between where `p` faces and `at`.
func _off(p: Player, at: Vector2) -> float:
	return absf(rad_to_deg(p.facing.angle_to(Iso.to_floor(at - p.position))))


func _run() -> void:
	Net.local_char = "willow"
	Net.map_id = "living_room"  # the open room: no walls in the way
	Net.practice()
	await frames(10)
	await tap(Seats.B_SOUTH)
	check(Seats.seat(0).device == PAD and Seats.keyboard_seat() == 0, "joined on the controller (alone: the keyboard works too)")
	Net.add_bot(Roster.Team.ROBOTS)
	Net.add_bot(Roster.Team.PETS)
	# Always the same two: walkers (a flyer can hover over an armchair, which
	# stops ground shots), and nobody who hides.
	for entry: Dictionary in Net.roster.values():
		if entry["bot"]:
			entry["char"] = "butler" if entry["team"] == Roster.Team.ROBOTS else "pepper"
	Net.start_match()
	while Match.current == null or Match.current.phase != Match.Phase.WAR:
		await frames(10)
	arena = Match.current
	arena.pickups_on = false
	for p: Player in arena.players.values():
		if p.seat == 0:
			me = p
		elif p.team == Roster.Team.ROBOTS:
			robot = p
			p.brain = Controls.new()  # stands still
		else:
			mate = p
			p.brain = Controls.new()
	check(me != null and me.brain is SeatInput and me.brain.hold_to_aim, "your character aims the people way (bots don't)")
	spot = _open_spot()
	_park_remote()

	# A tap fires when you let go, not on the press, nudged onto an enemy a
	# little off to one side.
	_place(me, spot, Vector2.RIGHT)
	_place(robot, spot + Iso.to_screen(Vector2(80, 0).rotated(deg_to_rad(18))), Vector2.LEFT)
	_place(mate, spot + Iso.to_screen(Vector2(-60, 90)), Vector2.LEFT)
	await frames(2)
	var hp := robot.hp
	button(Seats.B_WEST, true)
	await frames(2)
	check(me.attack_cd <= 0.0, "pressing attack doesn't fire yet")
	button(Seats.B_WEST, false)
	await frames(2)
	check(me.attack_cd > 0.0, "a quick tap fires as you let go")
	check(_off(me, robot.position) < 2.0, "aim assist turned the shot onto the robot 18 degrees off")
	await frames(20)
	check(robot.hp < hp, "...and it hit (%d -> %d HP)" % [hp, robot.hp])

	# Nobody near the line: the shot goes where you face.
	_place(me, spot, Vector2.RIGHT)
	_place(robot, spot + Iso.to_screen(Vector2(0, -80)), Vector2.LEFT)
	await frames(2)
	await tap(Seats.B_WEST)
	check(me.attack_cd > 0.0 and me.facing.angle_to(Vector2.RIGHT) == 0.0, "with nobody that way, a tap fires straight ahead")

	# Holding attack plants you; the stick turns you; letting go fires that way.
	_place(me, spot, Vector2.RIGHT)
	_place(robot, spot + Iso.to_screen(Vector2(0, -80)), Vector2.LEFT)
	await frames(2)
	hp = robot.hp
	button(Seats.B_WEST, true)
	await frames(15)
	check(me.aiming, "held for a quarter of a second: planted and aiming")
	var at := me.position
	stick("left", Vector2(0, -1))
	await frames(15)
	check(me.position.distance_to(at) < 0.5, "while aiming, the stick doesn't move you")
	check(me.facing.y < -0.99, "...it turns you (now facing up the screen)")
	stick("left", Vector2.ZERO)
	await frames(3)
	check(me.facing.y < -0.99 and me.attack_cd <= 0.0, "letting go of the stick keeps the aim, and nothing's fired yet")
	button(Seats.B_WEST, false)
	await frames(2)
	check(me.attack_cd > 0.0 and not me.aiming, "letting go of attack fires")
	await frames(20)
	check(robot.hp < hp, "...up the screen, into the robot (%d -> %d HP)" % [hp, robot.hp])

	# A second stick aims while the first one moves, and fires on the press.
	_place(me, spot, Vector2.RIGHT)
	await frames(2)
	at = me.position
	stick("left", Vector2(1, 0))
	stick("right", Vector2(0, -1))
	await frames(10)
	check(me.position.x > at.x + 5.0 and me.facing.y < -0.99, "left stick moves right while the right stick aims up")
	button(Seats.B_WEST, true)
	await frames(2)
	check(me.attack_cd > 0.0, "aiming with the right stick, attack fires on the press")
	button(Seats.B_WEST, false)
	stick("right", Vector2.ZERO)
	await frames(30)
	check(me.facing.x > 0.99, "a moment after the right stick lets go, you face where you move again")
	stick("left", Vector2.ZERO)
	await frames(3)

	# Keyboard diagonals: the two keys never come up on the same frame.
	_place(me, spot, Vector2.RIGHT)
	await frames(2)
	Input.action_press("move_up")
	Input.action_press("move_right")
	await frames(10)
	Input.action_release("move_up")
	await frames(3)
	Input.action_release("move_right")
	await frames(5)
	check(me.facing.x > 0.6 and me.facing.y < -0.6, "W+D let go a few frames apart still faces up-right (%s)" % me.facing)
	Input.action_press("move_up")
	Input.action_press("move_right")
	await frames(10)
	Input.action_release("move_up")
	await frames(20)
	Input.action_release("move_right")
	await frames(3)
	check(me.facing.x > 0.99, "...but keep holding one of them and you turn to it (%s)" % me.facing)

	# The remote: a tap throws it to a teammate roughly that way.
	_place(me, spot, Vector2.RIGHT)
	_place(robot, spot + Iso.to_screen(Vector2(-90, -60)), Vector2.LEFT)
	_place(mate, spot + Iso.to_screen(Vector2(90, 0).rotated(deg_to_rad(35))), Vector2.LEFT)
	await _hand_me_the_remote()
	await tap(Seats.B_EAST)
	check(arena.remote.state == TVRemote.State.FLYING and absf(arena.remote.flight - 90.0 / Match.THROW_SPEED) < 0.03,
		"a tap throws the remote just far enough to reach the teammate 35 degrees off (%.2f s)" % arena.remote.flight)
	await frames(45)
	check(arena.remote.state == TVRemote.State.CARRIED and arena.remote.carrier_pid == mate.pid, "...and they catch it")

	# Held to aim: planted, the stick picks the teammate, letting go throws.
	_place(me, spot, Vector2.RIGHT)
	_place(mate, spot + Iso.to_screen(Vector2(-10, 70)), Vector2.LEFT)
	await _hand_me_the_remote()
	button(Seats.B_EAST, true)
	await frames(15)
	check(me.aiming and arena.remote.state == TVRemote.State.CARRIED, "holding throw aims instead of throwing")
	at = me.position
	stick("left", Vector2(0, 1))
	await frames(10)
	check(me.position.distance_to(at) < 0.5 and me.pass_target(me.facing, Player.PASS_CONE_AIMED) == mate,
		"the stick turns you (without moving) until the teammate is picked")
	stick("left", Vector2.ZERO)
	await frames(2)
	button(Seats.B_EAST, false)
	await frames(45)
	check(arena.remote.state == TVRemote.State.CARRIED and arena.remote.carrier_pid == mate.pid, "letting go throws it to them")

	# Nobody that way: it flies as far as it goes.
	_place(me, spot, Vector2.LEFT)
	_place(mate, spot + Iso.to_screen(Vector2(80, 0)), Vector2.LEFT)
	await _hand_me_the_remote()
	await tap(Seats.B_EAST)
	check(arena.remote.state == TVRemote.State.FLYING and absf(arena.remote.flight - Match.THROW_RANGE / Match.THROW_SPEED) < 0.03,
		"with nobody that way, the remote flies its full distance (%.2f s)" % arena.remote.flight)
	_finish()


func _place(p: Player, at: Vector2, face: Vector2) -> void:
	p.position = at
	p._net_pos = at
	p.facing = face
	p.hp = p.max_hp
	p.invuln = 0.0
	p.stun = 0.0
	p.knock_vel = Vector2.ZERO
	p.attack_cd = 0.0
	p.stealthed = false


func _park_remote() -> void:
	arena.remote.position = spot + Iso.to_screen(Vector2(0, 150))
	arena.remote.state = TVRemote.State.DROPPED
	arena.remote.carrier_pid = 0
	arena.remote.timer = 999.0


func _hand_me_the_remote() -> void:
	arena.remote.state = TVRemote.State.CARRIED
	arena.remote.carrier_pid = me.pid
	arena.remote.position = me.position
	await frames(3)


## A stretch of floor with nothing in the way for 100 px around.
func _open_spot() -> Vector2:
	var level := arena.level
	var best := level.home.position
	var best_clear := -1
	for dj in range(-8, 9):
		for di in range(-8, 9):
			var c := level.home.position + Iso.to_screen(Vector2(di * 12.0, dj * 12.0))
			if not level.room.contains(c, 3.0):
				continue
			var clear := 0
			for a in 16:
				var ok := true
				for k in range(1, 11):
					var p := c + Iso.to_screen(Vector2.from_angle(TAU * a / 16.0) * k * 10.0)
					if level.furniture_at(p) != null or not level.room.contains(p, 1.0) \
							or Iso.fdist(p, level.home.position) < 20.0:
						ok = false
						break
				if ok:
					clear += 1
			if clear > best_clear:
				best = c
				best_clear = clear
	return best
