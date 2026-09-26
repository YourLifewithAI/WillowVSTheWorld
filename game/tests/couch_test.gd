extends Node
## Shared-screen test with fake controllers (run by tools/smoke_test.sh):
##   godot --headless --fixed-fps 60 --path game res://tests/couch_test.tscn
##
## Plugs in two Joy-Con pairs, a lone left Joy-Con and a Pro-style controller.
## Five people join in the lobby (the first pair split between two of them,
## held sideways; the second held together by one person), one flips their
## character, and + starts a match. Then it checks that each person's stick
## moves only their own character, in the direction they pushed; that buttons,
## quick taps, pausing and resuming work; that the keyboard doesn't steer
## someone else's character; and that dropped controllers pause the game and
## find their way back to the right people.
##
## The fake controllers report what SDL reports for real ones. How a sideways
## push shows up is worked out here from SDL's own code for a LONE sideways
## Joy-Con (thirdparty/sdl/joystick/hidapi/SDL_hidapi_switch.c,
## HandleMiniControllerStateL/R) and for a pair (HandleCombinedControllerStateL/R),
## independently of the rotation in Seats, so a mistake there shows up here.

const PAIR := 12
const LONE_L := 13
const PRO := 14
const LONE_L_AGAIN := 15
const PAIR2 := 16
const SPLIT_R := 20
const SPLIT_L := 21

var _passed := 0
var _failed := 0


func _ready() -> void:
	# Stay alive while the game swaps scenes underneath us.
	get_tree().current_scene = null
	Seats.add_fake_device(PAIR, Seats.Kind.PAIR, "aa-aa-aa-aa-aa-01,bb-bb-bb-bb-bb-02")
	Seats.add_fake_device(LONE_L, Seats.Kind.JOYCON_L)
	Seats.add_fake_device(PRO, Seats.Kind.FULL)
	Seats.add_fake_device(PAIR2, Seats.Kind.PAIR, "cc-cc-cc-cc-cc-03,dd-dd-dd-dd-dd-04")
	# If anything hangs, fail rather than hold up the whole test run.
	get_tree().create_timer(60.0, true, false, true).timeout.connect(func() -> void:
		check(false, "finished within a minute")
		_finish())
	_run.call_deferred()


func check(ok: bool, what: String) -> void:
	if ok:
		_passed += 1
		print("  PASS  couch: %s" % what)
	else:
		_failed += 1
		print("  FAIL  couch: %s" % what)


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


func axis(device: int, a: JoyAxis, value: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.device = device
	e.axis = a
	e.axis_value = value
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func tap(device: int, b: int) -> void:
	button(device, b, true)
	await frames(3)
	button(device, b, false)
	await frames(3)


## Two buttons pressed together (SL + SR, L + R).
func chord(device: int, a: int, b: int) -> void:
	button(device, a, true)
	button(device, b, true)
	await frames(3)
	button(device, a, false)
	button(device, b, false)
	await frames(3)


## Holds a stick toward `dir` (x right, y toward the top of the screen = -1)
## the way that person holds it, as SDL would report it.
func push(who: String, dir: Vector2) -> void:
	match who:
		"pair_L":
			# Lone left Joy-Con: LEFTX = -rawY, LEFTY = -rawX. In a pair: LEFTX = rawX, LEFTY = -rawY.
			var raw_x := -dir.y
			var raw_y := -dir.x
			axis(PAIR, JOY_AXIS_LEFT_X, raw_x)
			axis(PAIR, JOY_AXIS_LEFT_Y, -raw_y)
		"pair_R":
			# Lone right Joy-Con: LEFTX = rawY, LEFTY = rawX. In a pair: RIGHTX = rawX, RIGHTY = -rawY.
			var raw_x := dir.y
			var raw_y := dir.x
			axis(PAIR, JOY_AXIS_RIGHT_X, raw_x)
			axis(PAIR, JOY_AXIS_RIGHT_Y, -raw_y)
		"lone_L":
			# SDL already turns a lone Joy-Con sideways.
			axis(LONE_L, JOY_AXIS_LEFT_X, dir.x)
			axis(LONE_L, JOY_AXIS_LEFT_Y, dir.y)
		"pro":
			axis(PRO, JOY_AXIS_LEFT_X, dir.x)
			axis(PRO, JOY_AXIS_LEFT_Y, dir.y)
		"pair2":
			# Held together as one controller: the left stick, upright.
			axis(PAIR2, JOY_AXIS_LEFT_X, dir.x)
			axis(PAIR2, JOY_AXIS_LEFT_Y, dir.y)


func release_sticks() -> void:
	for dev in [PAIR, LONE_L, PRO, PAIR2]:
		for a in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y, JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y]:
			axis(dev, a, 0.0)


func _run() -> void:
	print("== Shared screen (fake Joy-Cons)")
	Net.practice()
	await frames(10)
	check(Seats.seats.size() == 1 and Seats.solo(), "before anyone joins, you're playing alone on every controller")

	# Face buttons on a pair don't join: its halves belong to two people.
	await tap(PAIR, Seats.B_EAST)
	check(Seats.solo(), "a face button on a Joy-Con pair doesn't join anyone")
	# SL + SR on the right half (paddles 1 and 3 in a pair), then on the left half (2 and 4).
	await chord(PAIR, Seats.B_PADDLE1, Seats.B_PADDLE3)
	var p1 := Seats.seat(0)
	check(p1.device == PAIR and p1.side == "R", "SL + SR on the right half of a pair takes P1")
	await chord(PAIR, Seats.B_PADDLE2, Seats.B_PADDLE4)
	var p2 := Seats.seat(1)
	check(p2 != null and p2.device == PAIR and p2.side == "L", "SL + SR on its left half joins as P2")
	await tap(LONE_L, Seats.B_SOUTH)
	await tap(PRO, Seats.B_SOUTH)
	await chord(PAIR2, Seats.B_LEFT_SHOULDER, Seats.B_RIGHT_SHOULDER)
	var p5 := Seats.seat(4)
	check(Seats.seats.size() == 5 and p5 != null and p5.device == PAIR2 and p5.side == "",
		"a lone Joy-Con and a controller join with any button, and L + R takes a whole pair (5 people)")
	var humans := Net.roster.values().filter(func(e: Dictionary) -> bool: return not e["bot"])
	check(humans.size() == 5, "five people in the roster")
	var counts := Net.team_counts()
	check(absi(counts[0] - counts[1]) <= 1, "new people are spread over both teams (%d v %d)" % [counts[0], counts[1]])
	check(Net.roster[Net.my_id()]["name"] == "P1", "with several people on screen, your player is called P1")
	await chord(PAIR, Seats.B_PADDLE2, Seats.B_PADDLE4)
	check(Seats.seats.size() == 5, "joining again doesn't add anyone twice")

	# P2 pushes their stick right (toward the SR end) to change character.
	var before := Seats.char_of(1)
	push("pair_L", Vector2.RIGHT)
	await frames(4)
	release_sticks()
	await frames(4)
	var ids: Array = Roster.CHARACTERS.keys()
	check(Seats.char_of(1) == ids[(ids.find(before) + 1) % ids.size()], "P2's stick flips to the next character (%s -> %s)" % [before, Seats.char_of(1)])

	# P4 presses +: a countdown, which P4 calls off, then starts again.
	await tap(PRO, Seats.B_START)
	await frames(30)
	check(Match.current == null, "+ starts a countdown rather than the match")
	await tap(PRO, Seats.B_START)
	await frames(200)
	check(Match.current == null, "+ again calls the countdown off")
	await tap(PRO, Seats.B_START)
	var waited := 0
	while Match.current == null and waited < 400:
		await frames(10)
		waited += 10
	check(Match.current != null, "the match starts when the countdown runs out")
	if Match.current == null:
		_finish()
		return
	var arena := Match.current
	while arena.phase != Match.Phase.WAR:
		await frames(10)
	var locals := arena.local_players()
	check(locals.size() == 5 and arena.shared_screen(), "five characters are played on this screen")

	# Each person pushes up, then right: only their character moves, and the right way.
	for who in [["pair_R", 0], ["pair_L", 1], ["lone_L", 2], ["pro", 3], ["pair2", 4]]:
		for dir: Vector2 in [Vector2.UP, Vector2.RIGHT]:
			var start := {}
			for p in locals:
				start[p.seat] = p.position
			push(who[0], dir)
			await frames(12)
			release_sticks()
			await frames(2)
			var mover: Player = locals[who[1]]
			var moved: Vector2 = mover.position - start[mover.seat]
			var screen_dir := Iso.to_screen(dir).normalized()
			var ok := moved.length() > 4.0 and moved.normalized().dot(screen_dir) > 0.8
			var others_still := true
			for p in locals:
				if p != mover and p.position.distance_to(start[p.seat]) > 0.5:
					others_still = false
			check(ok and others_still, "%s pushed %s moves %s that way, and nobody else (moved %s)" % [
				who[0], "up" if dir == Vector2.UP else "right", Seats.tag(who[1]), moved.round()])

	# The keyboard belongs to nobody now (a controller took P1).
	var start_pos := {}
	for p in locals:
		start_pos[p.seat] = p.position
	Input.action_press("move_right")
	await frames(10)
	Input.action_release("move_right")
	var still := true
	for p in locals:
		if p.position.distance_to(start_pos[p.seat]) > 0.5:
			still = false
	check(still, "the laptop's keyboard doesn't steer anyone who joined on a controller")

	# Buttons: the left button attacks (B on the right half, which a pair reports as SOUTH).
	var p1_char: Player = locals[0]
	p1_char.attack_cd = 0.0
	await tap(PAIR, Seats.B_SOUTH)
	check(p1_char.attack_cd > 0.0, "P1's left button (B) attacks")
	# The right button, when you aren't carrying the remote: your close-up move.
	var p2_target: Player = locals[1]
	p1_char.facing = Vector2.RIGHT
	p2_target.position = p1_char.position + Iso.to_screen(Vector2(10, 0))
	p2_target.invuln = 0.0
	p1_char.melee_cd = 0.0
	var hp_before := p2_target.hp
	await tap(PAIR, Seats.B_NORTH)
	await frames(4)
	check(p1_char.melee_cd > 0.0 and p2_target.hp < hp_before,
		"P1's right button does their close-up move (%s): P2 %d -> %d HP" % [p1_char.data["melee"]["name"], hp_before, p2_target.hp])
	# A tap that's over before the game looks still counts, exactly once.
	var p2_char: Player = locals[1]
	p2_char.dash_cd = 0.0
	button(PAIR, Seats.B_LEFT, true)
	button(PAIR, Seats.B_LEFT, false)
	await frames(2)
	check(p2_char.dash_cd > 0.0, "P2's quick tap on the bottom button (Left arrow) still dashes")

	# The menu: P3's - (START on a lone Joy-Con) pauses; the bottom button picks "Keep playing".
	var p3_char: Player = locals[2]
	await tap(LONE_L, Seats.B_START)
	check(get_tree().paused, "P3's - opens the menu and pauses the game")
	p3_char.dash_cd = 0.0
	button(LONE_L, Seats.B_SOUTH, true)
	await frames(4)
	check(not get_tree().paused, "P3's bottom button picks Keep playing")
	await frames(4)
	button(LONE_L, Seats.B_SOUTH, false)
	await frames(2)
	check(p3_char.dash_cd <= 0.0, "...and the press that resumed doesn't make P3 dash")

	# P3's Joy-Con drops out: the game waits, then carries on when it's back.
	Seats.remove_fake_device(LONE_L)
	await frames(3)
	check(Seats.seat(2).lost and get_tree().paused, "P3's Joy-Con disconnecting pauses the game")
	Seats.add_fake_device(LONE_L_AGAIN, Seats.Kind.JOYCON_L)
	await frames(3)
	check(not Seats.seat(2).lost and Seats.seat(2).device == LONE_L_AGAIN and not get_tree().paused,
		"P3 gets the Joy-Con back when it reconnects, and the game carries on")

	# The first pair comes apart (SDL gives each half back as a lone Joy-Con, with
	# new ids): each person gets their own half, recognised by its address.
	Seats.remove_fake_device(PAIR)
	Seats.add_fake_device(SPLIT_R, Seats.Kind.JOYCON_R, "bb-bb-bb-bb-bb-02")
	Seats.add_fake_device(SPLIT_L, Seats.Kind.JOYCON_L, "aa-aa-aa-aa-aa-01")
	await frames(3)
	check(Seats.seat(0).device == SPLIT_R and Seats.seat(1).device == SPLIT_L and not get_tree().paused,
		"when a pair comes apart, both people keep their own halves")
	_finish()


func _finish() -> void:
	print("[couch] %d passed, %d failed" % [_passed, _failed])
	Audio.quit_game()
