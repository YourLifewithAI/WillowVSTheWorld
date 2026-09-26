extends Node
## Seats (autoload): the people playing on THIS screen, and their controllers.
##
## Seat 0 is you: the roster entry this machine always has (the same one used
## online). On a shared screen more people join by pressing a button on their
## own controller in the lobby. Each gets a guest seat, a roster entry and a
## character. Guests are owned by this machine, like bots are by the host, so
## the rules and the network code treat them like any other player.
##
## The gameplay actions in project.godot are keyboard-only. Controllers are
## read here, one at a time, so every seat drives its own character:
##   - a lone Joy-Con is already turned sideways by the engine (SDL);
##   - a Joy-Con pair, which SDL always merges into one controller, is split
##     back into its two halves, each held sideways by a different person;
##   - anything else (Pro Controller, Xbox, a pair in its grip...) is read as
##     an ordinary gamepad.
## Buttons are positional, whatever is printed on them: bottom = dash,
## left = attack, top = special, right = throw / hold to tidy, the shoulder
## buttons (SL/SR on a sideways Joy-Con) = gag, + or - = menu.
##
## Until someone joins with a controller, seat 0 listens to the keyboard AND
## every controller, so solo play needs no setup.

## Seats were added, removed, or got or lost a controller.
signal changed
## Something worth telling the players ("P3's controller disconnected").
signal notice(text: String, color: Color)

enum Kind { FULL, JOYCON_L, JOYCON_R, PAIR }

const MAX_SEATS := 8
## The device id used for the keyboard.
const KEYBOARD := -2
const DEADZONE := 0.25
## One colour per seat, used for rings, tags and HUD cards (P1..P8).
const COLORS: Array[Color] = [Color("ff5a6e"), Color("4d9dff"), Color("ffd23f"), Color("58d68d"),
	Color("c38cff"), Color("ff9ed2"), Color("3fd8d0"), Color("f2f2f2")]

# SDL's gamepad buttons, as Godot numbers them (see engine drivers/sdl/joypad_sdl.cpp).
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


## One person on this screen.
class Seat:
	var index := 0
	## Roster id of the character this seat plays (seat 0: this machine's own id).
	var roster_id := 0
	## Joypad id, KEYBOARD, or -1 (not claimed, or its controller dropped out).
	var device := -1
	## "L" or "R" when the seat holds one half of a Joy-Con pair.
	var side := ""
	## What the controller was, to recognise it when it comes back.
	var kind := 0
	## Its controller disconnected: the next one that fits (or any button press) takes over.
	var lost := false
	var prev: Dictionary = {}
	var nav_x := 0
	var nav_menu := false
	var nav_ok := false

	func has_controller() -> bool:
		return device >= 0


var seats: Array[Seat] = []
## Lobby: presses on free controllers add people. (Always on: a free controller
## pressing a button also takes over a seat whose controller dropped out.)
var accepting_joins := false

var _devices: Dictionary = {}  # joypad id -> Kind, connected right now
var _fake: Dictionary = {}  # joypad id -> Kind, fake controllers for tests
var _free_prev: Dictionary = {}  # unit key -> face button held last frame (join presses)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for spec in String(Net.options.get("fake-pads", "")).split(",", false):
		var parts := spec.split(":")
		if parts.size() == 2:
			add_fake_device(int(parts[0]), kind_from_name(parts[1]))
	reset()
	Net.roster_changed.connect(_on_roster_changed)


## Back to just you (leaving a session).
func reset() -> void:
	seats.clear()
	var me := Seat.new()
	seats.append(me)
	changed.emit()


func seat(index: int) -> Seat:
	for s in seats:
		if s.index == index:
			return s
	return null


func roster_id(index: int) -> int:
	return Net.my_id() if index == 0 else (seat(index).roster_id if seat(index) else 0)


func color(index: int) -> Color:
	return COLORS[index % COLORS.size()]


## Guests on this screen, not counting you.
func guest_count() -> int:
	return seats.size() - 1


# ================================================================ devices

## Tests: pretend a controller is plugged in (joypad events for this id can
## then be faked with Input.parse_input_event).
func add_fake_device(id: int, kind: Kind) -> void:
	_fake[id] = kind


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


func kind_of(id: int) -> Kind:
	if _fake.has(id):
		return _fake[id]
	var info := Input.get_joy_info(id)
	var product := str(info.get("product_id", ""))
	var joy_name := Input.get_joy_name(id)
	if product == "8200" or joy_name.contains("Joy-Con (L/R)"):
		return Kind.PAIR
	if product == "8198" or joy_name.contains("Joy-Con (L)"):
		return Kind.JOYCON_L
	if product == "8199" or joy_name.contains("Joy-Con (R)"):
		return Kind.JOYCON_R
	return Kind.FULL


## What people can hold: [device, side] for every connected controller, with a
## pair counted as two halves.
func _units() -> Array:
	var out := []
	for id: int in _devices:
		if _devices[id] == Kind.PAIR:
			out.append([id, "L"])
			out.append([id, "R"])
		else:
			out.append([id, ""])
	return out


func _owner_of(device: int, side: String) -> Seat:
	for s in seats:
		if s.device == device and (s.side == side or s.side == "" or side == ""):
			return s
	return null


func _process(_delta: float) -> void:
	_scan_devices()
	_poll_presses()


## Notices controllers coming and going. (Polled rather than waiting for
## Input.joy_connection_changed, which arrives a frame late.)
func _scan_devices() -> void:
	var now := {}
	for id in Input.get_connected_joypads():
		now[id] = kind_of(id)
	for id: int in _fake:
		now[id] = _fake[id]
	for id: int in _devices.keys():
		if not now.has(id) or now[id] != _devices[id]:
			_device_gone(id)
	for id: int in now:
		if not _devices.has(id) or _devices[id] != now[id]:
			_devices[id] = now[id]
			_device_came(id, now[id])


func _device_gone(id: int) -> void:
	_devices.erase(id)
	for s in seats:
		if s.device == id:
			s.device = -1
			s.lost = true
			s.prev = {}
			notice.emit("%s's controller disconnected. Press a button to take it back." % tag(s.index), color(s.index))
	changed.emit()


## A controller turned up: give it to whoever lost one just like it. (When a
## second Joy-Con connects, SDL swaps the two single ones for one pair, so the
## people holding them get their halves of the pair back.)
func _device_came(id: int, kind: Kind) -> void:
	var sides := ["L", "R"] if kind == Kind.PAIR else [""]
	for side: String in sides:
		for s in seats:
			if s.lost and _fits(s, kind, side):
				_claim(s, id, side, kind)
				break
	changed.emit()


## Would a seat that used to hold (s.kind, s.side) recognise this (kind, side)?
func _fits(s: Seat, kind: Kind, side: String) -> bool:
	var was_left := s.kind == Kind.JOYCON_L or (s.kind == Kind.PAIR and s.side == "L")
	var was_right := s.kind == Kind.JOYCON_R or (s.kind == Kind.PAIR and s.side == "R")
	var is_left := kind == Kind.JOYCON_L or (kind == Kind.PAIR and side == "L")
	var is_right := kind == Kind.JOYCON_R or (kind == Kind.PAIR and side == "R")
	if is_left or is_right:
		return (was_left and is_left) or (was_right and is_right)
	return s.kind == Kind.FULL and kind == Kind.FULL


func _claim(s: Seat, device: int, side: String, kind: Kind) -> void:
	var was_lost := s.lost
	s.device = device
	s.side = side
	s.kind = kind
	s.lost = false
	s.prev = {}
	if was_lost:
		notice.emit("%s is back!" % tag(s.index), color(s.index))


# ================================================================ joining

## Presses on controllers nobody holds: join (lobby) or take over a seat whose
## controller dropped out (any time).
func _poll_presses() -> void:
	var units := _units()
	units.append([KEYBOARD, ""])
	var seen := {}
	for u: Array in units:
		var key := "%d:%s" % [u[0], u[1]]
		seen[key] = true
		var free := _owner_of(u[0], u[1]) == null
		var pressed: bool = free and _face_pressed(u[0], u[1])
		if pressed and not _free_prev.get(key, false):
			_on_free_press(u[0], u[1])
		_free_prev[key] = pressed
	for key: String in _free_prev.keys():
		if not seen.has(key):
			_free_prev.erase(key)


func _face_pressed(device: int, side: String) -> bool:
	if device == KEYBOARD:
		# Only the attack key joins from the keyboard (Space and Enter work the menus).
		return Input.is_physical_key_pressed(KEY_J)
	var st := _unit_state(device, side)
	return st["attack"] or st["special"] or st["dash"] or st["interact"]


func _on_free_press(device: int, side: String) -> void:
	var kind: Kind = _devices.get(device, Kind.FULL)
	# Someone whose controller dropped out takes this one. (Not the keyboard:
	# pressing J is how whoever plays on it attacks.)
	for s in seats:
		if s.lost and device != KEYBOARD:
			_claim(s, device, side, kind)
			changed.emit()
			return
	if not accepting_joins:
		return
	var me := seats[0]
	if device == KEYBOARD:
		# The keyboard is already yours unless a controller took seat 0.
		if me.has_controller():
			_add_guest(device, side, kind)
		return
	if me.device == -1:
		_claim(me, device, side, kind)
		_joined(me)
	else:
		_add_guest(device, side, kind)


func _add_guest(device: int, side: String, kind: Kind) -> void:
	if not Net.is_host() or Net.roster.size() >= Net.MAX_PLAYERS or seats.size() >= MAX_SEATS:
		notice.emit("The house is full!", Color.WHITE)
		return
	var s := Seat.new()
	s.index = _free_index()
	_claim(s, device, side, kind)
	s.roster_id = Net.add_guest(s.index)
	seats.append(s)
	seats.sort_custom(func(a: Seat, b: Seat) -> bool: return a.index < b.index)
	_joined(s)


func _joined(s: Seat) -> void:
	var c: Dictionary = Roster.get_char(char_of(s.index))
	Audio.play("hi_" + String(c.get("voice", "cat")), 0.0, float(c.get("voice_pitch", 1.0)))
	changed.emit()


func _free_index() -> int:
	var i := 1
	while seat(i) != null:
		i += 1
	return i


## Removes a guest (the host's "x" button, or their roster entry went away).
func remove(index: int) -> void:
	var s := seat(index)
	if s == null or index == 0:
		return
	seats.erase(s)
	if Net.roster.has(s.roster_id):
		Net.remove_guest(s.roster_id)
	changed.emit()


## Lets go of seat 0's controller (it goes back to listening to all of them).
func release_me() -> void:
	var me := seats[0]
	me.device = -1
	me.side = ""
	me.lost = false
	changed.emit()


func _on_roster_changed() -> void:
	for s in seats.duplicate():
		if s.index != 0 and not Net.roster.has(s.roster_id):
			seats.erase(s)
			changed.emit()


func char_of(index: int) -> String:
	var entry: Dictionary = Net.roster.get(roster_id(index), {})
	return entry.get("char", Net.local_char)


## Lobby: step this seat's character left or right through the whole cast.
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
	var s := seat(index)
	var out := {"move": Vector2.ZERO, "attack": false, "attack_held": false, "special": false, "dash": false,
		"gag": false, "interact": false, "interact_pressed": false}
	if s == null:
		return out
	var now := _seat_state(s)
	var prev := s.prev
	out["move"] = now["move"]
	out["attack"] = now["attack"] and not prev.get("attack", false)
	out["attack_held"] = now["attack"]
	out["special"] = now["special"] and not prev.get("special", false)
	out["dash"] = now["dash"] and not prev.get("dash", false)
	out["gag"] = now["gag"] and not prev.get("gag", false)
	out["interact"] = now["interact"]
	out["interact_pressed"] = now["interact"] and not prev.get("interact", false)
	s.prev = now
	return out


## Lobby and menus: this seat's stick/D-pad left or right (-1, 0, 1) as a
## single step per push, whether + or - was just pressed ("menu"), and
## whether the bottom button was just pressed ("ok").
func nav(index: int) -> Dictionary:
	var s := seat(index)
	if s == null:
		return {"x": 0, "menu": false, "ok": false}
	var st := _seat_state(s)
	var x: float = st["move"].x
	var step := 0
	if s.nav_x == 0 and absf(x) > 0.6:
		step = 1 if x > 0.0 else -1
		s.nav_x = step
	elif absf(x) < 0.3:
		s.nav_x = 0
	var menu: bool = st["menu"] and not s.nav_menu
	s.nav_menu = st["menu"]
	var ok: bool = st["dash"] and not s.nav_ok
	s.nav_ok = st["dash"]
	return {"x": step, "menu": menu, "ok": ok}


## Everything this seat is holding right now.
func _seat_state(s: Seat) -> Dictionary:
	var states := []
	if s.device >= 0:
		states.append(_unit_state(s.device, s.side))
	var keyboard_owner := _keyboard_owner()
	if keyboard_owner == s:
		states.append(_unit_state(KEYBOARD, ""))
	if s.index == 0 and not s.has_controller() and not s.lost:
		# Nobody has joined with a controller: every free one drives you.
		for u: Array in _units():
			if _owner_of(u[0], u[1]) == null:
				states.append(_unit_state(u[0], _whole_or_half(u[0], u[1])))
	return _merge(states)


## A pair nobody has split is one ordinary gamepad (e.g. in its grip).
func _whole_or_half(device: int, side: String) -> String:
	if side == "":
		return ""
	for s in seats:
		if s.device == device:
			return side
	return ""


func _keyboard_owner() -> Seat:
	for s in seats:
		if s.device == KEYBOARD:
			return s
	return seats[0]


func _merge(states: Array) -> Dictionary:
	var out := {"move": Vector2.ZERO, "attack": false, "special": false, "dash": false, "interact": false,
		"gag": false, "menu": false}
	var seen_halves := {}
	for st: Dictionary in states:
		if st.has("key"):
			if seen_halves.has(st["key"]):
				continue
			seen_halves[st["key"]] = true
		out["move"] += st["move"]
		for k in ["attack", "special", "dash", "interact", "gag", "menu"]:
			out[k] = out[k] or st[k]
	out["move"] = out["move"].limit_length(1.0)
	return out


## One controller (or one half of a pair, or the keyboard), right now.
func _unit_state(device: int, side: String) -> Dictionary:
	var st := {"move": Vector2.ZERO, "attack": false, "special": false, "dash": false, "interact": false,
		"gag": false, "menu": false, "key": "%d:%s" % [device, side]}
	if device == KEYBOARD:
		st["move"] = Input.get_vector("move_left", "move_right", "move_up", "move_down")
		st["attack"] = Input.is_action_pressed("attack")
		st["special"] = Input.is_action_pressed("special")
		st["dash"] = Input.is_action_pressed("dash")
		st["interact"] = Input.is_action_pressed("interact")
		st["gag"] = Input.is_action_pressed("gag")
		return st
	var d := device
	match side:
		"L":
			# The left half of a pair, turned sideways (a quarter turn anticlockwise):
			# the arrow buttons become the four face buttons.
			st["move"] = Vector2(Input.get_joy_axis(d, JOY_AXIS_LEFT_Y), -Input.get_joy_axis(d, JOY_AXIS_LEFT_X))
			st["dash"] = _b(d, B_LEFT)
			st["interact"] = _b(d, B_DOWN)
			st["attack"] = _b(d, B_UP)
			st["special"] = _b(d, B_RIGHT)
			st["gag"] = _b(d, B_PADDLE2) or _b(d, B_PADDLE4) or _b(d, B_LEFT_SHOULDER)
			st["menu"] = _b(d, B_BACK)
		"R":
			# The right half, turned a quarter turn clockwise: A is at the bottom.
			st["move"] = Vector2(-Input.get_joy_axis(d, JOY_AXIS_RIGHT_Y), Input.get_joy_axis(d, JOY_AXIS_RIGHT_X))
			st["dash"] = _b(d, B_EAST)
			st["interact"] = _b(d, B_NORTH)
			st["attack"] = _b(d, B_SOUTH)
			st["special"] = _b(d, B_WEST)
			st["gag"] = _b(d, B_PADDLE1) or _b(d, B_PADDLE3) or _b(d, B_RIGHT_SHOULDER)
			st["menu"] = _b(d, B_START)
		_:
			var stick := Vector2(Input.get_joy_axis(d, JOY_AXIS_LEFT_X), Input.get_joy_axis(d, JOY_AXIS_LEFT_Y))
			var pad := Vector2(float(_b(d, B_RIGHT)) - float(_b(d, B_LEFT)), float(_b(d, B_DOWN)) - float(_b(d, B_UP)))
			st["move"] = stick + pad
			st["dash"] = _b(d, B_SOUTH)
			st["interact"] = _b(d, B_EAST)
			st["attack"] = _b(d, B_WEST)
			st["special"] = _b(d, B_NORTH)
			st["gag"] = _b(d, B_LEFT_SHOULDER) or _b(d, B_RIGHT_SHOULDER) \
				or Input.get_joy_axis(d, JOY_AXIS_TRIGGER_LEFT) > 0.5 or Input.get_joy_axis(d, JOY_AXIS_TRIGGER_RIGHT) > 0.5
			st["menu"] = _b(d, B_START) or _b(d, B_BACK)
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

func tag(index: int) -> String:
	return "P%d" % (index + 1)


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
		return "Keyboard or any controller" if index == 0 else ""
	match s.kind:
		Kind.JOYCON_L:
			return "Left Joy-Con"
		Kind.JOYCON_R:
			return "Right Joy-Con"
		Kind.PAIR:
			return "Left Joy-Con" if s.side == "L" else "Right Joy-Con"
	return "Controller"


## What to call each control for this seat, for on-screen hints.
func button_names(index: int) -> Dictionary:
	var s := seat(index)
	if s == null or not uses_controller(index):
		return {"attack": "J", "special": "K", "dash": "Space", "interact": "E", "gag": "I"}
	var joycon := s.kind != Kind.FULL
	return {"attack": "Left", "special": "Top", "dash": "Bottom", "interact": "Right",
		"gag": "SL/SR" if joycon else "Bumper"}


## True when this seat plays on a controller (so hints should name buttons, not keys).
func uses_controller(index: int) -> bool:
	var s := seat(index)
	return s != null and (s.device >= 0 or s.lost)
