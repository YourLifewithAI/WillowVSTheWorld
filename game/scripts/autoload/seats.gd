extends Node
## Seats (autoload): the people playing on THIS screen, and their controllers.
##
## Seat 0 is you: the roster entry this machine always has (the same one used
## online). On a shared screen more people join in the lobby, each on their
## own controller, and get guest seats: roster entries owned by this machine,
## like bots are by the host, so the rules and the network code treat them
## like any other player.
##
## Joining uses the Switch's own gestures:
##   - a Joy-Con held sideways: press SL + SR together;
##   - two Joy-Cons held together as one controller, a Pro Controller or any
##     other gamepad: press L + R together (other gamepads: any face button too);
##   - the keyboard: press J.
## Until anyone joins with a controller, you're playing alone and seat 0
## listens to the keyboard AND every controller, so solo play needs no setup.
## After that, each seat hears only its own controller.
##
## The gameplay actions in project.godot are keyboard-only, and controllers
## never move the menus' focus (the ui_* joypad events are removed at start).
## Controllers are read here, one at a time:
##   - a lone Joy-Con is already turned sideways by the engine (SDL);
##   - a left + right pair, which SDL always merges into one controller, is
##     split back into its halves when people hold them sideways, each half's
##     stick and buttons turned a quarter turn (see _unit_state);
##   - anything else is an ordinary gamepad.
## Buttons are positional, whatever is printed on them: bottom = dash,
## left = attack, top = special, right = throw / hold to tidy, the shoulder
## buttons (SL/SR on a sideways Joy-Con) = gag, + or - = menu.

## Seats were added or removed, or got or lost a controller.
signal changed
## Something worth telling the players ("P3's Joy-Con disconnected").
signal notice(text: String, color: Color)

enum Kind { FULL, JOYCON_L, JOYCON_R, PAIR }

const MAX_SEATS := 8
## The device id used for the keyboard.
const KEYBOARD := -2
const DEADZONE := 0.25
## One colour per seat (P1..P8) for tags, arrows and HUD cards: the usual
## party-game red, blue, yellow, green first.
const COLORS: Array[Color] = [Color("ff4f7b"), Color("4a7dff"), Color("ffd23f"), Color("3ccf6e"),
	Color("b57bff"), Color("ff9ed2"), Color("a0e05a"), Color("f2f2f2")]

# SDL's gamepad buttons, as Godot numbers them (engine drivers/sdl/joypad_sdl.cpp).
const B_SOUTH := 0
const B_EAST := 1
const B_WEST := 2
const B_NORTH := 3
const B_BACK := 4
const B_START := 6
const B_LEFT_SHOULDER := 9
const B_RIGHT_SHOULDER := 10
const B_UP := 11
const B_DOWN := 12
const B_LEFT := 13
const B_RIGHT := 14
const B_PADDLE1 := 16  # right half of a pair: SR
const B_PADDLE2 := 17  # left half of a pair: SL
const B_PADDLE3 := 18  # right half of a pair: SL
const B_PADDLE4 := 19  # left half of a pair: SR

## Which buttons do what. A lone Joy-Con uses FULL too: SDL has already turned
## it sideways, and its SL/SR are the shoulder buttons. The halves of a pair
## are read the way each is held sideways (checked against SDL's own handling
## of lone Joy-Cons in tests/couch_test.gd):
##   left half, a quarter turn anticlockwise: the arrow buttons are the face buttons;
##   right half, a quarter turn clockwise: A is at the bottom.
const MAP_FULL := {"attack": [B_WEST], "special": [B_NORTH], "dash": [B_SOUTH], "interact": [B_EAST],
	"gag": [B_LEFT_SHOULDER, B_RIGHT_SHOULDER], "menu": [B_START, B_BACK]}
const MAP_LEFT_HALF := {"attack": [B_UP], "special": [B_RIGHT], "dash": [B_LEFT], "interact": [B_DOWN],
	"gag": [B_PADDLE2, B_PADDLE4], "menu": [B_BACK]}
const MAP_RIGHT_HALF := {"attack": [B_SOUTH], "special": [B_WEST], "dash": [B_EAST], "interact": [B_NORTH],
	"gag": [B_PADDLE1, B_PADDLE3], "menu": [B_START]}
const ACTIONS: Array[String] = ["attack", "special", "dash", "interact", "gag", "menu"]


## One person on this screen.
class Seat:
	var index := 0
	## Roster id of the character this seat plays (seat 0: this machine's own id).
	var roster_id := 0
	## Joypad id, KEYBOARD, or -1 (nothing claimed, or its controller dropped out).
	var device := -1
	## "L" or "R": one half of a Joy-Con pair, held sideways. "" for anything else,
	## including a whole pair held together.
	var side := ""
	var kind := 0
	## The Joy-Con's Bluetooth address, to recognise it when it comes back.
	var mac := ""
	## Its controller disconnected: it waits for that controller (or a spare one like it).
	var lost := false
	## Its menu is open: its character ignores it.
	var muted := false
	var prev: Dictionary = {}
	var last_read := -100
	var nav_x := 0
	var nav_repeat := 0.0
	var nav_menu := false
	var nav_ok := false

	func has_controller() -> bool:
		return device >= 0


var seats: Array[Seat] = []
## Lobby: joining is open (only the host adds people).
var accepting_joins := false

var _devices: Dictionary = {}  # joypad id -> {"kind", "serial"}, connected right now
var _fake: Dictionary = {}  # joypad id -> {"kind", "serial"}, fake controllers for tests
var _gesture_prev: Dictionary = {}  # unit key -> join gesture held last frame
var _latch: Dictionary = {}  # device * 100 + button -> pressed since last read (keeps quick taps)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Several people share one screen, so no controller may move the menus'
	# single focus (or press whatever it lands on). Menus hear controllers
	# through Seats instead.
	for action in InputMap.get_actions():
		if String(action).begins_with("ui_"):
			for e in InputMap.action_get_events(action):
				if e is InputEventJoypadButton or e is InputEventJoypadMotion:
					InputMap.action_erase_event(action, e)
	for spec in String(Net.options.get("fake-pads", "")).split(",", false):
		var parts := spec.split(":")
		if parts.size() >= 2:
			add_fake_device(int(parts[0]), kind_from_name(parts[1]), parts[2] if parts.size() > 2 else "")
	reset()
	Net.roster_changed.connect(_on_roster_changed)


## Back to just you (leaving a session).
func reset() -> void:
	seats.clear()
	seats.append(Seat.new())
	_gesture_prev.clear()
	changed.emit()


func seat(index: int) -> Seat:
	for s in seats:
		if s.index == index:
			return s
	return null


func roster_id(index: int) -> int:
	if index == 0:
		return Net.my_id()
	var s := seat(index)
	return s.roster_id if s else 0


func color(index: int) -> Color:
	return COLORS[index % COLORS.size()]


func tag(index: int) -> String:
	return "P%d" % (index + 1)


## Nobody has joined with a controller: seat 0 hears everything.
func solo() -> bool:
	for s in seats:
		if s.has_controller() or s.lost:
			return false
	return true


func lost_seats() -> Array[Seat]:
	var out: Array[Seat] = []
	for s in seats:
		if s.lost:
			out.append(s)
	return out


# ================================================================ devices

## Tests: pretend a controller is plugged in. Joypad events for this id can then
## be faked with Input.parse_input_event.
func add_fake_device(id: int, kind: Kind, serial: String = "") -> void:
	_fake[id] = {"kind": kind, "serial": serial}


func remove_fake_device(id: int) -> void:
	_fake.erase(id)


static func kind_from_name(n: String) -> Kind:
	match n:
		"pair":
			return Kind.PAIR
		"joycon_l":
			return Kind.JOYCON_L
		"joycon_r":
			return Kind.JOYCON_R
	return Kind.FULL


## What a connected controller is. Only Joy-Cons that SDL's own Switch driver
## (HIDAPI) is handling get the Joy-Con treatment: other drivers (macOS's, or
## Windows' fallback) lay them out differently, so they're read as ordinary pads.
func _identify(id: int) -> Dictionary:
	if _fake.has(id):
		return _fake[id]
	var info := Input.get_joy_info(id)
	var serial := str(info.get("serial_number", ""))
	var guid := Input.get_joy_guid(id)
	var hidapi := guid.length() >= 30 and guid.substr(28, 2) == "68"  # 'h'
	if str(info.get("vendor_id", "")) == "1406" and hidapi:
		match str(info.get("product_id", "")):
			"8200":
				return {"kind": Kind.PAIR, "serial": serial}
			"8198":
				return {"kind": Kind.JOYCON_L, "serial": serial}
			"8199":
				return {"kind": Kind.JOYCON_R, "serial": serial}
	return {"kind": Kind.FULL, "serial": serial}


func _kind(device: int) -> Kind:
	return _devices.get(device, {}).get("kind", Kind.FULL)


## The Bluetooth address of what (device, side) is: a pair's serial is "L,R".
func _mac(device: int, side: String) -> String:
	var serial: String = _devices.get(device, {}).get("serial", "")
	var parts := serial.split(",")
	if side == "L" and parts.size() == 2:
		return parts[0]
	if side == "R" and parts.size() == 2:
		return parts[1]
	return serial


## What people can pick up and join with: [device, side] for every connected
## controller. A pair offers its two halves and itself as a whole.
func _units() -> Array:
	var out := []
	for id: int in _devices:
		if _kind(id) == Kind.PAIR:
			out.append([id, "L"])
			out.append([id, "R"])
		out.append([id, ""])
	return out


func _owner_of(device: int, side: String) -> Seat:
	for s in seats:
		if s.device == device and (s.side == side or s.side == "" or side == ""):
			return s
	return null


## Controllers are checked before the characters read them each tick, so nobody
## reads a controller whose id the engine has just handed to someone else's.
func _physics_process(_delta: float) -> void:
	_scan_devices()


func _process(delta: float) -> void:
	_scan_devices()
	_poll_joins()
	for s in seats:
		s.nav_repeat = maxf(0.0, s.nav_repeat - delta)


## Remembers quick taps (pressed and released between two ticks) until the seat reads them.
func _input(event: InputEvent) -> void:
	var jb := event as InputEventJoypadButton
	if jb and jb.pressed:
		_latch[jb.device * 100 + jb.button_index] = true


## Notices controllers coming and going (polled: Input.joy_connection_changed
## arrives a frame late, after the engine may already have reused the id).
func _scan_devices() -> void:
	var now := {}
	for id in Input.get_connected_joypads():
		now[id] = _identify(id)
	for id: int in _fake:
		now[id] = _fake[id]
	for id: int in _devices.keys():
		if not now.has(id) or now[id] != _devices[id]:
			_device_gone(id)
	for id: int in now:
		if not _devices.has(id):
			_devices[id] = now[id]
			_device_came(id)


func _device_gone(id: int) -> void:
	_devices.erase(id)
	for s in seats:
		if s.device == id:
			s.device = -1
			s.lost = true
			s.prev = {}
			notice.emit("%s's controller disconnected. Wake it up (press any button on it)." % tag(s.index), color(s.index))
	changed.emit()


## A controller turned up: give it back to whoever had it. Joy-Cons are
## recognised by their Bluetooth address, which also covers SDL swapping two
## lone Joy-Cons for a pair (each person gets their own half back). Anything
## without an address goes to the one seat waiting for that kind of controller.
func _device_came(id: int) -> void:
	var kind := _kind(id)
	var sides := ["L", "R"] if kind == Kind.PAIR else [""]
	var any := false
	for side: String in sides:
		var mac := _mac(id, side)
		for s in lost_seats():
			if not s.mac.is_empty() and s.mac == mac:
				_claim(s, id, side)
				any = true
				break
	if not any and lost_seats().size() == 1 and _mac(id, "").is_empty():
		var s: Seat = lost_seats()[0]
		if _fits(s, kind, ""):
			_claim(s, id, "")
	changed.emit()


## Could a seat that held (s.kind, s.side) carry on with (kind, side)?
func _fits(s: Seat, kind: Kind, side: String) -> bool:
	var was_left := s.kind == Kind.JOYCON_L or (s.kind == Kind.PAIR and s.side == "L")
	var was_right := s.kind == Kind.JOYCON_R or (s.kind == Kind.PAIR and s.side == "R")
	var is_left := kind == Kind.JOYCON_L or (kind == Kind.PAIR and side == "L")
	var is_right := kind == Kind.JOYCON_R or (kind == Kind.PAIR and side == "R")
	if was_left or was_right:
		return (was_left and is_left) or (was_right and is_right)
	return not (is_left or is_right)


func _claim(s: Seat, device: int, side: String) -> void:
	var was_lost := s.lost
	s.device = device
	s.side = side
	s.kind = _kind(device) if device >= 0 else Kind.FULL
	s.mac = _mac(device, side) if device >= 0 else ""
	s.lost = false
	_rebaseline(s)
	s.nav_menu = true  # the press that joined doesn't also count as a menu press
	s.nav_ok = true
	if was_lost:
		notice.emit("%s is back!" % tag(s.index), color(s.index))


# ================================================================ joining

## The join gestures, on controllers nobody holds.
func _poll_joins() -> void:
	var units := _units()
	units.append([KEYBOARD, ""])
	var seen := {}
	for u: Array in units:
		var key := "%d:%s" % [u[0], u[1]]
		seen[key] = true
		var held: bool = _owner_of(u[0], u[1]) == null and _join_gesture(u[0], u[1])
		if held and not _gesture_prev.get(key, false):
			_on_join(u[0], u[1])
		_gesture_prev[key] = held
	for key: String in _gesture_prev.keys():
		if not seen.has(key):
			_gesture_prev.erase(key)


func _join_gesture(device: int, side: String) -> bool:
	if device == KEYBOARD:
		# Only J joins from the keyboard (Space and Enter work the menus).
		return Input.is_physical_key_pressed(KEY_J)
	var kind := _kind(device)
	if side == "L" or side == "R":
		# A half of a pair held sideways: SL + SR.
		var m: Dictionary = MAP_LEFT_HALF if side == "L" else MAP_RIGHT_HALF
		return _b(device, m["gag"][0]) and _b(device, m["gag"][1])
	# L + R together (on a lone Joy-Con those are SL and SR).
	var shoulders := _b(device, B_LEFT_SHOULDER) and _b(device, B_RIGHT_SHOULDER)
	if kind == Kind.PAIR:
		return shoulders  # its face buttons belong to two different people
	# A lone Joy-Con or any other controller: any face button works too.
	return shoulders or _b(device, B_SOUTH) or _b(device, B_EAST) or _b(device, B_WEST) or _b(device, B_NORTH)


func _on_join(device: int, side: String) -> void:
	var kind := _kind(device)
	# Someone whose controller dropped out picks up one like it.
	if device != KEYBOARD:
		for s in lost_seats():
			if _fits(s, kind, side):
				_claim(s, device, side)
				changed.emit()
				return
	if not accepting_joins:
		return
	var me := seats[0]
	if device == KEYBOARD:
		# The keyboard is already yours unless a controller took seat 0.
		if me.has_controller() or me.lost:
			_add_guest(device, side)
		return
	if not me.has_controller() and not me.lost and me.device != KEYBOARD:
		_claim(me, device, side)
		_joined(me)
	else:
		_add_guest(device, side)


func _add_guest(device: int, side: String) -> void:
	if not Net.is_host() or seats.size() >= MAX_SEATS or not Net.has_room_for_guest():
		notice.emit("The house is full (8 at most)!", Color("e05a5a"))
		return
	var s := Seat.new()
	s.index = _free_index()
	_claim(s, device, side)
	s.roster_id = Net.add_guest(s.index)
	seats.append(s)
	seats.sort_custom(func(a: Seat, b: Seat) -> bool: return a.index < b.index)
	_joined(s)


func _joined(s: Seat) -> void:
	var c: Dictionary = Roster.get_char(char_of(s.index))
	Audio.play("hi_" + String(c.get("voice", "cat")), 0.0, float(c.get("voice_pitch", 1.0)))
	Net.name_my_player()
	changed.emit()


func _free_index() -> int:
	var i := 1
	while seat(i) != null:
		i += 1
	return i


## Removes a guest (the host's "x" button).
func remove(index: int) -> void:
	var s := seat(index)
	if s == null or index == 0:
		return
	seats.erase(s)
	if Net.roster.has(s.roster_id):
		Net.remove_guest(s.roster_id)
	Net.name_my_player()
	changed.emit()


func _on_roster_changed() -> void:
	for s in seats.duplicate():
		if s.index != 0 and not Net.roster.has(s.roster_id):
			seats.erase(s)
			changed.emit()


func char_of(index: int) -> String:
	var entry: Dictionary = Net.roster.get(roster_id(index), {})
	return entry.get("char", Net.local_char)


## Lobby: step this seat's character through the whole cast.
func cycle_character(index: int, step: int) -> void:
	var ids: Array = Roster.CHARACTERS.keys()
	var at := ids.find(char_of(index))
	var next: String = ids[posmod(at + step, ids.size())]
	if index == 0:
		Net.choose_character(next)
	else:
		Net.set_guest_character(roster_id(index), next)
	Audio.play("select", -6.0)


# ================================================================ reading

## This seat's controls for one physics tick (the same shape BotBrain returns).
func read(index: int) -> Dictionary:
	var out := {"move": Vector2.ZERO, "attack": false, "attack_held": false, "special": false, "dash": false,
		"gag": false, "interact": false, "interact_pressed": false}
	var s := seat(index)
	if s == null:
		return out
	var frame := Engine.get_physics_frames()
	if frame - s.last_read > 1:
		# Not read for a while (paused, captured, just joined): nothing that was
		# already held, or pressed in the meantime, counts as a new press.
		_rebaseline(s)
	s.last_read = frame
	var now := _seat_state(s)
	var pressed := _pressed_since_last_read(s, now)
	s.prev = now
	if s.muted:
		return out
	out["move"] = now["move"]
	out["attack"] = pressed["attack"]
	out["attack_held"] = now["attack"]
	out["special"] = pressed["special"]
	out["dash"] = pressed["dash"]
	out["gag"] = pressed["gag"]
	out["interact"] = now["interact"]
	out["interact_pressed"] = pressed["interact"]
	return out


## Menus: this seat's stick left/right (-1, 0, 1) as a step (repeating while
## held), and whether + / - ("menu") or the bottom button ("ok") was just pressed.
func nav(index: int) -> Dictionary:
	var s := seat(index)
	if s == null:
		return {"x": 0, "menu": false, "ok": false}
	var st := _seat_state(s)
	var x: float = st["move"].x
	var step := 0
	if absf(x) < 0.3:
		s.nav_x = 0
	elif absf(x) > 0.6:
		var dir := 1 if x > 0.0 else -1
		if s.nav_x != dir or s.nav_repeat <= 0.0:
			step = dir
			s.nav_repeat = 0.4 if s.nav_x != dir else 0.15
			s.nav_x = dir
	var menu: bool = st["menu"] and not s.nav_menu
	s.nav_menu = st["menu"]
	var ok: bool = st["dash"] and not s.nav_ok
	s.nav_ok = st["dash"]
	return {"x": step, "menu": menu, "ok": ok}


## While a seat's menu is open (online, where the game doesn't pause), its
## character stands still.
func set_muted(index: int, value: bool) -> void:
	var s := seat(index)
	if s:
		s.muted = value
		_rebaseline(s)


func _rebaseline(s: Seat) -> void:
	s.prev = _seat_state(s)
	for u: Array in _seat_units(s):
		if u[0] >= 0:
			for b: int in _buttons_of(u[0], u[1], ACTIONS):
				_latch.erase(u[0] * 100 + b)


func _pressed_since_last_read(s: Seat, now: Dictionary) -> Dictionary:
	var out := {}
	for a in ACTIONS:
		out[a] = now[a] and not s.prev.get(a, false)
	for u: Array in _seat_units(s):
		if u[0] == KEYBOARD:
			for a in ["attack", "special", "dash", "interact", "gag"]:
				out[a] = out[a] or Input.is_action_just_pressed(a)
			continue
		for a in ACTIONS:
			for b: int in _buttons_of(u[0], u[1], [a]):
				if _latch.has(u[0] * 100 + b):
					out[a] = true
					_latch.erase(u[0] * 100 + b)
	return out


## Every controller (and/or the keyboard) this seat is holding right now.
func _seat_units(s: Seat) -> Array:
	var out := []
	if s.device >= 0:
		out.append([s.device, s.side])
	if _keyboard_owner() == s:
		out.append([KEYBOARD, ""])
	if s.index == 0 and solo():
		# Playing alone: every controller works, a pair as one gamepad.
		for id: int in _devices:
			out.append([id, ""])
	return out


## The seat the keyboard plays for, or -1.
func keyboard_seat() -> int:
	var s := _keyboard_owner()
	return s.index if s else -1


## Who the keyboard plays for: whoever joined with it, else seat 0 (unless a
## controller took seat 0, in which case the keyboard plays nobody until it joins).
func _keyboard_owner() -> Seat:
	for s in seats:
		if s.device == KEYBOARD:
			return s
	var me := seats[0]
	return null if me.has_controller() or me.lost else me


func _seat_state(s: Seat) -> Dictionary:
	var out := {"move": Vector2.ZERO, "attack": false, "special": false, "dash": false, "interact": false,
		"gag": false, "menu": false}
	for u: Array in _seat_units(s):
		var st := _unit_state(u[0], u[1])
		out["move"] += st["move"]
		for a in ACTIONS:
			out[a] = out[a] or st[a]
	out["move"] = out["move"].limit_length(1.0)
	return out


func _map_of(device: int, side: String) -> Dictionary:
	if _kind(device) == Kind.PAIR and side == "L":
		return MAP_LEFT_HALF
	if _kind(device) == Kind.PAIR and side == "R":
		return MAP_RIGHT_HALF
	return MAP_FULL


func _buttons_of(device: int, side: String, actions: Array) -> Array:
	var m := _map_of(device, side)
	var out := []
	for a: String in actions:
		out.append_array(m[a])
	return out


## One controller (or one half of a pair, or the keyboard), right now.
func _unit_state(device: int, side: String) -> Dictionary:
	var st := {"move": Vector2.ZERO, "attack": false, "special": false, "dash": false, "interact": false,
		"gag": false, "menu": false}
	if device == KEYBOARD:
		st["move"] = Input.get_vector("move_left", "move_right", "move_up", "move_down")
		for a in ["attack", "special", "dash", "interact", "gag"]:
			st[a] = Input.is_action_pressed(a)
		return st
	var d := device
	var m := _map_of(d, side)
	for a in ACTIONS:
		for b: int in m[a]:
			st[a] = st[a] or _b(d, b)
	if m == MAP_LEFT_HALF:
		st["move"] = Vector2(Input.get_joy_axis(d, JOY_AXIS_LEFT_Y), -Input.get_joy_axis(d, JOY_AXIS_LEFT_X))
	elif m == MAP_RIGHT_HALF:
		st["move"] = Vector2(-Input.get_joy_axis(d, JOY_AXIS_RIGHT_Y), Input.get_joy_axis(d, JOY_AXIS_RIGHT_X))
	else:
		var stick := Vector2(Input.get_joy_axis(d, JOY_AXIS_LEFT_X), Input.get_joy_axis(d, JOY_AXIS_LEFT_Y))
		var pad := Vector2(float(_b(d, B_RIGHT)) - float(_b(d, B_LEFT)), float(_b(d, B_DOWN)) - float(_b(d, B_UP)))
		st["move"] = stick + pad
		st["gag"] = st["gag"] or Input.get_joy_axis(d, JOY_AXIS_TRIGGER_LEFT) > 0.5 \
			or Input.get_joy_axis(d, JOY_AXIS_TRIGGER_RIGHT) > 0.5
	st["move"] = _deadzone(st["move"])
	return st


func _b(device: int, button: int) -> bool:
	return Input.is_joy_button_pressed(device, button as JoyButton)


static func _deadzone(v: Vector2) -> Vector2:
	var l := v.length()
	if l < DEADZONE:
		return Vector2.ZERO
	return v / l * minf(1.0, (l - DEADZONE) / (1.0 - DEADZONE))


# ================================================================ labels

## What a seat is holding, in words ("Left Joy-Con", "Keyboard", ...).
func device_label(index: int) -> String:
	var s := seat(index)
	if s == null:
		return ""
	if s.lost:
		return "controller lost"
	if s.device == KEYBOARD:
		return "Keyboard"
	if s.device < 0:
		return "Keyboard" + (" or any controller" if index == 0 and solo() else "")
	match s.kind:
		Kind.JOYCON_L:
			return "Left Joy-Con"
		Kind.JOYCON_R:
			return "Right Joy-Con"
		Kind.PAIR:
			return "Left Joy-Con" if s.side == "L" else "Right Joy-Con" if s.side == "R" else "Joy-Con pair"
	return "Controller"


## Controllers nobody has joined with yet, in words (for the lobby).
func free_controllers() -> Array[String]:
	var out: Array[String] = []
	for id: int in _devices:
		var kind := _kind(id)
		if kind == Kind.PAIR:
			for side in ["L", "R"]:
				if _owner_of(id, side) == null:
					out.append("Left Joy-Con" if side == "L" else "Right Joy-Con")
		elif _owner_of(id, "") == null:
			out.append({Kind.JOYCON_L: "Left Joy-Con", Kind.JOYCON_R: "Right Joy-Con"}.get(kind, "Controller"))
	return out


## What to call each control for this seat, for on-screen hints.
func button_names(index: int) -> Dictionary:
	var s := seat(index)
	if s == null or not uses_controller(index):
		return {"attack": "J", "special": "K", "dash": "Space", "interact": "E", "gag": "I"}
	var sideways := s.kind == Kind.JOYCON_L or s.kind == Kind.JOYCON_R or s.side != ""
	return {"attack": "Left", "special": "Top", "dash": "Bottom", "interact": "Right",
		"gag": "SL/SR" if sideways else "L/R"}


## True when this seat plays on a controller (so hints should name buttons, not keys).
func uses_controller(index: int) -> bool:
	var s := seat(index)
	return s != null and (s.device >= 0 or s.lost)
