extends Control
## Pick your side, pick your character, wait for friends, start.

var _players_box: VBoxContainer
var _info: Label
var _start: Button
var _char_buttons: Dictionary = {}
var _detail: Label


func _ready() -> void:
	theme = UiTheme.build()
	_build()
	Net.roster_changed.connect(_refresh)
	_refresh()


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
	lcol.add_child(_players_box)
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
		_start.text = "Start! (parents leave)"
		_start.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_start.pressed.connect(Net.start_match)
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
			b.pressed.connect(_pick.bind(id))
			b.mouse_entered.connect(_show_detail.bind(id))
			b.focus_entered.connect(_show_detail.bind(id))
			grid.add_child(b)
			_char_buttons[id] = b
	_detail = UiTheme.label("", 9)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD
	_detail.custom_minimum_size = Vector2(360, 60)
	rcol.add_child(_detail)
	_show_detail(Net.local_char)
	_char_buttons[Net.local_char].grab_focus()


func _pick(id: String) -> void:
	Net.choose_character(id)
	_show_detail(id)
	_refresh()


func _show_detail(id: String) -> void:
	var c: Dictionary = Roster.get_char(id)
	var sp: Dictionary = c["special"]
	_detail.text = "%s the %s (%s)  —  %s\nHP %d · Speed %d%s\nAttack: %s   ·   Special: %s (%ds cooldown)\nCleanup: %s" % [
		c["name"], c["species"], c["role"], c["blurb"],
		c["hp"], c["speed"], "  · Flies over furniture" if c["flying"] else "",
		c["attack"]["name"], sp["name"], int(sp["cooldown"]), c["tidy_note"]]


func _refresh() -> void:
	for child in _players_box.get_children():
		child.queue_free()
	var ids: Array = Net.roster.keys()
	ids.sort()
	for team in [Roster.Team.PETS, Roster.Team.ROBOTS]:
		for id: int in ids:
			var entry: Dictionary = Net.roster[id]
			if entry["team"] != team:
				continue
			var row := HBoxContainer.new()
			row.add_child(UiTheme.sprite_icon(entry["char"], 18))
			var you := "  (you)" if id == Net.my_id() else ""
			var host := "  ★ host" if id == 1 else ""
			row.add_child(UiTheme.label("%s%s%s" % [entry["name"], you, host], 9, Roster.TEAM_COLORS[team].darkened(0.35)))
			_players_box.add_child(row)
	for id: String in _char_buttons:
		_char_buttons[id].button_pressed = id == Net.local_char
	var counts := Net.team_counts()
	if Net.is_host():
		var where := "Practice mode (offline)." if not Net.online else "Friends can join at %s  (port %d)." % [", ".join(Net.local_addresses()) if not Net.local_addresses().is_empty() else "your IP", Net.DEFAULT_PORT]
		_info.text = "%s  Pets %d vs Robots %d." % [where, counts[0], counts[1]]
		_start.disabled = not Net.can_start()
		if _start.disabled:
			_info.text += "  Each side needs at least one player (add a bot!)."
	else:
		_info.text = "Pets %d vs Robots %d. Waiting for the host to start..." % [counts[0], counts[1]]
