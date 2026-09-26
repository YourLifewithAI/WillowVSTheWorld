extends Control
## Title screen: pick a name, then practice against bots, host, or join.

var _name_edit: LineEdit
var _ip_edit: LineEdit
var _status: Label
var _parade: Array[Control] = []
var _t := 0.0


func _ready() -> void:
	theme = UiTheme.build()
	_build()
	Net.connection_failed.connect(_on_failed)
	Net.disconnected.connect(_on_failed)
	if not Net.last_error.is_empty():
		_on_failed(Net.last_error)
		Net.last_error = ""
	if Net.autolaunched:
		return
	Net.autolaunched = true
	if Net.options.has("practice"):
		Net.practice.call_deferred()
	elif Net.options.has("host"):
		_host.call_deferred()
	elif Net.options.has("join"):
		_join_address.call_deferred(Net.options["join"])


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color("ffe6cc")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var floor_strip := ColorRect.new()
	floor_strip.color = Color("d9a066")
	floor_strip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	floor_strip.offset_top = -70
	add_child(floor_strip)

	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	col.grow_horizontal = Control.GROW_DIRECTION_BOTH
	col.position.y = 18
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 4)
	add_child(col)

	var title := UiTheme.label("WILLOW VS THE WORLD", 30, Color("ff9f68"), true)
	title.add_theme_constant_override("outline_size", 8)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var tag := UiTheme.label("The parents just left. The pets and the robots want the remote.", 10)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(tag)

	var panel := PanelContainer.new()
	var holder := CenterContainer.new()
	holder.add_child(panel)
	col.add_child(holder)
	var form := VBoxContainer.new()
	form.add_theme_constant_override("separation", 5)
	form.custom_minimum_size.x = 220
	panel.add_child(form)

	var name_row := HBoxContainer.new()
	name_row.add_child(UiTheme.label("Your name", 10))
	_name_edit = LineEdit.new()
	_name_edit.text = Net.local_name
	_name_edit.max_length = 16
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.text_changed.connect(func(s: String) -> void: Net.local_name = s.strip_edges() if not s.strip_edges().is_empty() else "Player")
	name_row.add_child(_name_edit)
	form.add_child(name_row)

	var practice := Button.new()
	practice.text = "Practice vs bots"
	practice.pressed.connect(Net.practice)
	form.add_child(practice)
	var host := Button.new()
	host.text = "Host a game (port %d)" % Net.DEFAULT_PORT
	host.pressed.connect(_host)
	form.add_child(host)
	var join_row := HBoxContainer.new()
	_ip_edit = LineEdit.new()
	_ip_edit.text = "127.0.0.1"
	_ip_edit.placeholder_text = "host's IP address"
	_ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_row.add_child(_ip_edit)
	var join := Button.new()
	join.text = "Join"
	join.pressed.connect(func() -> void: _join_address(_ip_edit.text))
	join_row.add_child(join)
	form.add_child(join_row)
	var quit := Button.new()
	quit.text = "Quit"
	quit.pressed.connect(get_tree().quit)
	form.add_child(quit)

	_status = UiTheme.label("", 9, Color("e05a5a"))
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_status)
	practice.grab_focus()

	# Everybody lined up along the floor, bouncing.
	var ids := Roster.CHARACTERS.keys()
	for k in ids.size():
		var icon := UiTheme.sprite_icon(ids[k], 40)
		icon.position = Vector2(34 + k * 74, 360 - 62)
		icon.size = Vector2(40, 40)
		add_child(icon)
		_parade.append(icon)


func _process(delta: float) -> void:
	_t += delta
	for k in _parade.size():
		_parade[k].position.y = 360 - 62 - absf(sin(_t * 4.0 + k * 0.7)) * 6.0


func _host() -> void:
	var err := Net.host()
	if err != OK:
		_status.text = "Couldn't host on port %d (%s). Is another copy already hosting?" % [Net.DEFAULT_PORT, error_string(err)]


func _join_address(address: String) -> void:
	var err := Net.join(address.strip_edges())
	if err != OK:
		_status.text = "Couldn't start connecting: %s" % error_string(err)
	else:
		_status.add_theme_color_override("font_color", UiTheme.INK)
		_status.text = "Connecting to %s..." % address


func _on_failed(reason: String) -> void:
	if is_instance_valid(_status):
		_status.add_theme_color_override("font_color", Color("e05a5a"))
		_status.text = reason
