extends Node
## Shared-screen test with fake controllers (run by tools/smoke_test.sh):
##   godot --headless --fixed-fps 60 --path game res://tests/couch_test.tscn
##
## Plugs in a Joy-Con pair (split between two people), a lone left Joy-Con and
## a Pro-style controller, joins four people in the lobby, flips a character,
## starts a match, then checks that each person's stick moves only their own
## character, in the direction they pushed, and that buttons, pausing and a
## controller dropping out and coming back all work.
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

var _passed := 0
var _failed := 0


func _ready() -> void:
	# Stay alive while the game swaps scenes underneath us.
	get_tree().current_scene = null
	Seats.add_fake_device(PAIR, Seats.Kind.PAIR)
	Seats.add_fake_device(LONE_L, Seats.Kind.JOYCON_L)
	Seats.add_fake_device(PRO, Seats.Kind.FULL)
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


func button(device: int, b: JoyButton, down: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.device = device
	e.button_index = b
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


func tap(device: int, b: JoyButton) -> void:
	button(device, b, true)
	await frames(3)
	button(device, b, false)
	await frames(3)


## Holds a sideways Joy-Con's stick toward `dir` (x right, y toward the top of
## the screen = -1), as SDL would report it.
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


func release_sticks() -> void:
	for dev in [PAIR, LONE_L, PRO]:
		for a in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y, JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y]:
			axis(dev, a, 0.0)


func _run() -> void:
	print("== Shared screen (fake Joy-Cons)")
	Net.practice()
	await frames(10)
	check(Seats.seats.size() == 1 and Seats.seat(0).device == -1, "before anyone joins, you're listening to every controller")

	# The bottom button of each sideways Joy-Con: A on the right half (a pair
	# reports it as EAST), the Left arrow on the left half (D-pad left in a pair).
	await tap(PAIR, JOY_BUTTON_B)
	var p1 := Seats.seat(0)
	check(p1.device == PAIR and p1.side == "R", "the right half of a pair takes P1")
	await tap(PAIR, JOY_BUTTON_DPAD_LEFT)
	var p2 := Seats.seat(1)
	check(p2 != null and p2.device == PAIR and p2.side == "L", "the left half of the same pair joins as P2")
	await tap(LONE_L, JOY_BUTTON_A)
	await tap(PRO, JOY_BUTTON_A)
	check(Seats.seats.size() == 4, "a lone Joy-Con and a controller join as P3 and P4")
	var humans := Net.roster.values().filter(func(e: Dictionary) -> bool: return not e["bot"])
	check(humans.size() == 4, "four people in the roster")
	var counts := Net.team_counts()
	check(counts[0] == 2 and counts[1] == 2, "new people are spread over both teams (%d v %d)" % [counts[0], counts[1]])
	await tap(PAIR, JOY_BUTTON_DPAD_LEFT)
	check(Seats.seats.size() == 4, "pressing again doesn't add anyone twice")

	# P2 pushes their stick right (toward the SR button end) to change character.
	var before := Seats.char_of(1)
	push("pair_L", Vector2.RIGHT)
	await frames(4)
	release_sticks()
	await frames(4)
	var ids: Array = Roster.CHARACTERS.keys()
	check(Seats.char_of(1) == ids[(ids.find(before) + 1) % ids.size()], "P2's stick flips to the next character (%s -> %s)" % [before, Seats.char_of(1)])

	# P4 presses + to start.
	await tap(PRO, JOY_BUTTON_START)
	await frames(30)
	check(Match.current != null, "+ on a controller starts the match")
	if Match.current == null:
		_finish()
		return
	var arena := Match.current
	while arena.phase != Match.Phase.WAR:
		await frames(10)
	var locals := arena.local_players()
	check(locals.size() == 4 and arena.shared_screen(), "four characters are played on this screen")

	# Each person pushes up, then right: only their character moves, and the right way.
	for who in [["pair_R", 0], ["pair_L", 1], ["lone_L", 2], ["pro", 3]]:
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

	# Buttons: the left button attacks (B on the right half, which a pair reports as SOUTH).
	var p1_char: Player = locals[0]
	p1_char.attack_cd = 0.0
	await tap(PAIR, JOY_BUTTON_A)
	check(p1_char.attack_cd > 0.0, "P1's left button (B) attacks")
	var p2_char: Player = locals[1]
	p2_char.dash_cd = 0.0
	button(PAIR, JOY_BUTTON_DPAD_LEFT, true)
	await frames(2)
	check(p2_char.dash_cd > 0.0, "P2's bottom button (Left arrow) dashes")
	button(PAIR, JOY_BUTTON_DPAD_LEFT, false)

	# The menu: P3's minus pauses (offline), and again resumes.
	await tap(LONE_L, JOY_BUTTON_START)
	check(get_tree().paused, "P3's - opens the menu and pauses the game")
	await tap(LONE_L, JOY_BUTTON_START)
	check(not get_tree().paused, "pressing it again resumes")

	# P3's Joy-Con drops out, then comes back (as a new device id).
	Seats.remove_fake_device(LONE_L)
	await frames(3)
	check(Seats.seat(2).lost, "P3's seat notices its Joy-Con disconnected")
	Seats.add_fake_device(LONE_L_AGAIN, Seats.Kind.JOYCON_L)
	await frames(3)
	check(not Seats.seat(2).lost and Seats.seat(2).device == LONE_L_AGAIN, "P3 gets the Joy-Con back when it reconnects")
	_finish()


func _finish() -> void:
	print("[couch] %d passed, %d failed" % [_passed, _failed])
	Audio.quit_game()
