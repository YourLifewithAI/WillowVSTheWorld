extends Control
## Pick your side, pick your character, wait for friends, start.
##
## Friends on the same screen join on their own controller (see Seats for the
## gestures). Each seat then flips through the characters with its stick, and
## anyone's + or - starts a 3-second countdown (+ or - again cancels it).
## Controllers never move the menu's focus; the keyboard and mouse work the
## menu as usual.

const COUNTDOWN := 3.0

var _players_box: VBoxContainer
var _info: Label
var _start: Button
var _char_buttons: Dictionary = {}
var _detail: Label
var _map_pick: OptionButton
var _map_label: Label
var _built := false
var _badges: Dictionary = {}  # character id -> HBoxContainer of seat tags
var _notice: Label
var _free: Label
var _countdown := -1.0


func _ready() -> void:
	theme = UiTheme.build()
	_build()
	Audio.music("menu")
	Seats.accepting_joins = Net.is_host()
	Net.roster_changed.connect(_refresh)
	Seats.changed.connect(_refresh)
	Seats.notice.connect(_on_notice)
	_refresh()


func _exit_tree() -> void:
	Seats.accepting_joins = false


func _process(delta: float) -> void:
	if _countdown >= 0.0:
		var before := ceili(_countdown)
		_countdown -= delta
		if _countdown <= 0.0:
			_countdown = -1.0
			if Net.can_start():
				Net.start_match()
			return
		if ceili(_countdown) != before:
			Audio.play("tick")
			_on_notice("Starting in %d...  (+ or - to wait)" % ceili(_countdown), Color("3a9f6a"))
	for st in Seats.seats:
		# Seat 0 on the keyboard uses the buttons; anyone with their own controller
		# (or a guest on the keyboard) flips through characters instead.
		if not st.has_controller() and not (st.device == Seats.KEYBOARD and st.index != 0):
			continue
		var n := Seats.nav(st.index)
		if n["x"] != 0:
			Seats.cycle_character(st.index, n["x"])
			_show_detail(Seats.char_of(st.index))
		if n["menu"]:
			_try_start()
	var free := Seats.free_controllers()
	_free.text = "" if free.is_empty() else "Connected but not playing yet: " + ", ".join(free)
	_free.visible = not free.is_empty()


## A controller's + or -: start the countdown, or call it off.
func _try_start() -> void:
	if not Net.is_host():
		return
	if _countdown >= 0.0:
		_countdown = -1.0
		_on_notice("Waiting. Press + or - when everyone's ready.", UiTheme.COCOA)
	elif Net.can_start():
		Audio.play("start")
		_countdown = COUNTDOWN
		_on_notice("Starting in 3...  (+ or - to wait)", Color("3a9f6a"))
	else:
		_on_notice("Each side needs at least one player: pick someone from the other team, or add a bot.", Color("e05a5a"))


func _on_notice(text: String, color: Color) -> void:
	_notice.text = text
	_notice.add_theme_color_override("font_color", color.darkened(0.35))
	var shown := text
	get_tree().create_timer(5.0).timeout.connect(func() -> void:
		if is_instance_valid(_notice) and _notice.text == shown:
			_notice.text = "")


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color("ffe6cc")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	add_child(margin)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 10)
	margin.add_child(cols)

	# Left: who's here.
	var left := PanelContainer.new()
	left.custom_minimum_size.x = 190
	cols.add_child(left)
	var lcol := VBoxContainer.new()
	left.add_child(lcol)
	lcol.add_child(UiTheme.label("Who's home", 14))
	_info = UiTheme.label("", 8, UiTheme.COCOA)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD
	_info.custom_minimum_size.x = 170
	lcol.add_child(_info)
	_players_box = VBoxContainer.new()
	_players_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_players_box.add_theme_constant_override("separation", 0)
	lcol.add_child(_players_box)
	_notice = UiTheme.label("", 8)
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD
	_notice.custom_minimum_size.x = 170
	lcol.add_child(_notice)
	var map_row := HBoxContainer.new()
	map_row.add_child(UiTheme.label("Home:", 10))
	if Net.is_host():
		_map_pick = OptionButton.new()
		_map_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for id in Maps.ORDER:
			_map_pick.add_item(Maps.get_map(id)["name"])
		_map_pick.item_selected.connect(func(k: int) -> void: Net.set_map(Maps.ORDER[k]))
		map_row.add_child(_map_pick)
	else:
		_map_label = UiTheme.label("", 10, UiTheme.COCOA)
		map_row.add_child(_map_label)
	lcol.add_child(map_row)
	if Net.is_host():
		var bot_row := HBoxContainer.new()
		for team in [Roster.Team.PETS, Roster.Team.ROBOTS]:
			var b := Button.new()
			b.text = "+ %s bot" % ("Pet" if team == Roster.Team.PETS else "Robot")
			b.add_theme_font_size_override("font_size", 8)
			b.pressed.connect(Net.add_bot.bind(team))
			bot_row.add_child(b)
		var clear := Button.new()
		clear.text = "No bots"
		clear.add_theme_font_size_override("font_size", 8)
		clear.pressed.connect(Net.remove_bots)
		bot_row.add_child(clear)
		lcol.add_child(bot_row)
	var btn_row := HBoxContainer.new()
	lcol.add_child(btn_row)
	var leave := Button.new()
	leave.text = "Leave"
	leave.pressed.connect(func() -> void: Net.leave())
	btn_row.add_child(leave)
	if Net.is_host():
		_start = Button.new()
		_start.set_meta("silent", true)
		_start.text = "Start! (parents leave)"
		_start.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_start.pressed.connect(func() -> void:
			Audio.play("start")
			Net.start_match())
		btn_row.add_child(_start)

	# Right: pick a character.
	var right := PanelContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	var rcol := VBoxContainer.new()
	rcol.add_theme_constant_override("separation", 4)
	right.add_child(rcol)
	for team in [Roster.Team.PETS, Roster.Team.ROBOTS]:
		var head := UiTheme.label("Team %s" % Roster.TEAM_NAMES[team], 12, Roster.TEAM_COLORS[team].darkened(0.25))
		rcol.add_child(head)
		var grid := HBoxContainer.new()
		grid.add_theme_constant_override("separation", 4)
		rcol.add_child(grid)
		for id in Roster.ids_for_team(team):
			var c: Dictionary = Roster.get_char(id)
			var b := Button.new()
			b.set_meta("silent", true)  # says hello instead of clicking
			b.toggle_mode = true
			b.custom_minimum_size = Vector2(88, 64)
			b.tooltip_text = c["blurb"]
			var v := VBoxContainer.new()
			v.mouse_filter = Control.MOUSE_FILTER_IGNORE
			v.set_anchors_preset(Control.PRESET_FULL_RECT)
			v.alignment = BoxContainer.ALIGNMENT_CENTER
			var icon := UiTheme.sprite_icon(id, 32)
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			v.add_child(icon)
			var nl := UiTheme.label("%s\n%s" % [c["name"], c["role"]], 8)
			nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			v.add_child(nl)
			b.add_child(v)
			# "P1 P3": who on this screen is playing this character.
			var badges := HBoxContainer.new()
			badges.mouse_filter = Control.MOUSE_FILTER_IGNORE
			badges.position = Vector2(3, 1)
			badges.add_theme_constant_override("separation", 2)
			b.add_child(badges)
			_badges[id] = badges
			b.pressed.connect(_pick.bind(id))
			b.mouse_entered.connect(_show_detail.bind(id))
			b.focus_entered.connect(_on_char_focus.bind(id))
			grid.add_child(b)
			_char_buttons[id] = b
	if Net.is_host():
		var join := UiTheme.label("Join: hold a Joy-Con sideways and press SL + SR (two held as one, or a controller: L + R). "
			+ "Stick: change character.  + or -: start.  Your number is on screen (not the Joy-Con's lights).", 8, UiTheme.COCOA)
		join.autowrap_mode = TextServer.AUTOWRAP_WORD
		join.custom_minimum_size.x = 360
		rcol.add_child(join)
	_free = UiTheme.label("", 7, UiTheme.COCOA)
	rcol.add_child(_free)
	_detail = UiTheme.label("", 8)
	_detail.max_lines_visible = 7
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD
	_detail.custom_minimum_size = Vector2(360, 60)
	rcol.add_child(_detail)
	_show_detail(Net.local_char)
	_char_buttons[Net.local_char].grab_focus()
	_built = true


## Moving between characters with the keyboard or a gamepad blips.
func _on_char_focus(id: String) -> void:
	if _built and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		Audio.play("select", -6.0)
	_show_detail(id)


## A click (or Enter) on a character: it's for whoever plays on the keyboard
## and mouse, which is P1 unless P1 took a controller and the keyboard joined later.
func _pick(id: String) -> void:
	var c: Dictionary = Roster.get_char(id)
	Audio.play("hi_" + String(c.get("voice", "cat")), 0.0, float(c.get("voice_pitch", 1.0)))
	var kb := Seats.keyboard_seat()
	if kb > 0:
		Net.set_guest_character(Seats.roster_id(kb), id)
	else:
		Net.choose_character(id)
	_show_detail(id)
	_refresh()


func _show_detail(id: String) -> void:
	var c: Dictionary = Roster.get_char(id)
	var sp: Dictionary = c["special"]
	var g: Dictionary = c["gag"]
	var m: Dictionary = c["melee"]
	_detail.text = "%s the %s (%s): %s\nWeapon: %s   ·   Up close: %s   ·   Special: %s   ·   HP %d   ·   Speed %d\nGag: %s. %s\n+ %s\n- %s\nCleanup: %s" % [
		c["name"], c["species"], c["role"], c["blurb"],
		c["weapon"]["name"], m["name"], sp["name"], c["hp"], c["speed"],
		g["name"], g["blurb"], c["strength"], c["weakness"], c["tidy_note"]]


func _row_order(id: int) -> int:
	var entry: Dictionary = Net.roster[id]
	if id == Net.my_id() or int(entry.get("owner", 0)) == Net.my_id():
		return int(entry.get("seat", 0)) - 1000
	return 0 if not entry["bot"] else 1000 - id


func _refresh() -> void:
	for child in _players_box.get_children():
		child.queue_free()
	# People on this screen first (by seat), then everyone else.
	var ids: Array = Net.roster.keys()
	ids.sort_custom(func(a: int, b: int) -> bool: return _row_order(a) < _row_order(b))
	for team in [Roster.Team.PETS, Roster.Team.ROBOTS]:
		for id: int in ids:
			var entry: Dictionary = Net.roster[id]
			if entry["team"] != team:
				continue
			var row := HBoxContainer.new()
			row.add_child(UiTheme.sprite_icon(entry["char"], 18))
			var mine := id == Net.my_id() or int(entry.get("owner", 0)) == Net.my_id()
			var seat_index := int(entry.get("seat", 0))
			var name_col := Roster.TEAM_COLORS[team].darkened(0.35)
			var shared := mine and Seats.seats.size() > 1
			if shared:
				name_col = Seats.color(seat_index).darkened(0.35)
			var you := "  (you)" if id == Net.my_id() and not shared else ""
			var host := "  ★ host" if id == 1 else ""
			var holding := Seats.device_label(seat_index) if shared else ""
			var label := UiTheme.label("%s%s%s" % [entry["name"], you, host], 9, name_col)
			row.add_child(label)
			if not holding.is_empty():
				row.add_child(UiTheme.label(holding, 7, UiTheme.COCOA))
			if Net.is_host() and entry.has("owner") and not entry["bot"]:
				var kick := Button.new()
				kick.text = "x"
				kick.tooltip_text = "Remove %s" % entry["name"]
				kick.focus_mode = Control.FOCUS_NONE
				kick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				kick.add_theme_font_size_override("font_size", 7)
				for state in ["normal", "hover", "pressed"]:
					kick.add_theme_stylebox_override(state, UiTheme.box(UiTheme.PEACH, UiTheme.COCOA, 3, 1, 1))
				kick.pressed.connect(Seats.remove.bind(seat_index))
				row.add_child(kick)
			_players_box.add_child(row)
	# A keyboard guest flips characters with the arrow keys like a stick (see
	# _process), so the tiles mustn't also take arrow-key focus.
	var kb := Seats.keyboard_seat()
	var kb_char := Seats.char_of(kb) if kb > 0 else Net.local_char
	for id: String in _char_buttons:
		var b: Button = _char_buttons[id]
		b.button_pressed = id == kb_char
		b.focus_mode = Control.FOCUS_NONE if kb > 0 else Control.FOCUS_ALL
		if kb > 0 and b.has_focus():
			b.release_focus()
	# Seat tags on the characters people on this screen have picked.
	for id: String in _badges:
		for child in _badges[id].get_children():
			child.queue_free()
	if Seats.seats.size() > 1:
		for st in Seats.seats:
			var picked := Seats.char_of(st.index)
			if _badges.has(picked):
				_badges[picked].add_child(UiTheme.label(Seats.tag(st.index), 8, Seats.color(st.index), true))
	var map: Dictionary = Maps.get_map(Net.map_id)
	if _map_pick:
		_map_pick.select(Maps.ORDER.find(Net.map_id))
	if _map_label:
		_map_label.text = map["name"]
	var counts := Net.team_counts()
	if Net.is_host():
		var where := "Practice mode (offline)." if not Net.online else "Friends can join at %s  (port %d)." % [", ".join(Net.local_addresses()) if not Net.local_addresses().is_empty() else "your IP", Net.DEFAULT_PORT]
		_info.text = "%s  Pets %d vs Robots %d.\n%s: %s (best with %s)" % [where, counts[0], counts[1], map["name"], map["blurb"], map["players"]]
		_start.disabled = not Net.can_start()
		if _start.disabled:
			_info.text += "  Each side needs at least one player (add a bot!)."
			if _countdown >= 0.0:
				_countdown = -1.0
				_on_notice("Each side needs at least one player: pick someone from the other team, or add a bot.", Color("e05a5a"))
	else:
		_info.text = "Pets %d vs Robots %d. Waiting for the host to start...\n%s: %s" % [counts[0], counts[1], map["name"], map["blurb"]]
