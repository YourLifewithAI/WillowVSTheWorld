class_name PowerupsPanel
extends Control
## The lobby's powerups menu: every kind of powerup that can pop up around the
## house, what it does, and whether it's switched on for this session (see
## Net.powerups). The host switches them; everyone else can look.
##
## The mouse and keyboard click and tab through it as usual. Controllers can't
## move the menu's focus (see Seats), so the lobby hands the seat that opened
## it to nav_input(): stick up/down picks, the bottom button switches, the top
## button (or + / -) closes.

signal closed

## Icons for the kinds that don't have their own (someone's weapon; a tool).
const EXTRA_ICONS := {Pickups.Kind.WEAPON: "w_bazooka", Pickups.Kind.TOOL: "face_zoomba"}

var seat := -1
var _rows: Array[Button] = []
var _kinds: Array[int] = []
var _sel := 0
var _hint: HintLine
var _count: Label


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.23, 0.16, 0.19, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	panel.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	head.add_child(UiTheme.label("Powerups", 14))
	_count = UiTheme.label("", 8, UiTheme.COCOA)
	_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(_count)
	var intro := "They pop up around the house now and then: run over one to grab it. " + (
		"Pick which ones can turn up this session." if Net.is_host() else "The host picks which ones can turn up.")
	var intro_l := UiTheme.label(intro, 8, UiTheme.COCOA)
	intro_l.autowrap_mode = TextServer.AUTOWRAP_WORD
	intro_l.custom_minimum_size.x = 420
	col.add_child(intro_l)
	var war_done := false
	col.add_child(_section("IN THE WAR"))
	for kind: int in Pickups.MENU:
		if not Pickups.in_war(kind) and not war_done:
			war_done = true
			col.add_child(_section("IN THE CLEANUP"))
		var row := _row(kind)
		col.add_child(row)
		_rows.append(row)
		_kinds.append(kind)
	_hint = HintLine.new(maxi(seat, 0), "", 7, UiTheme.INK)
	_hint.outline = false
	_hint.accent = Color("ff9f68")
	col.add_child(_hint)
	var done := Button.new()
	done.text = "Done"
	done.pressed.connect(close)
	col.add_child(done)
	refresh()
	if seat < 0:
		_rows[0].grab_focus()


func _section(text: String) -> Label:
	var l := UiTheme.label(text, 8, UiTheme.COCOA.darkened(0.2))
	return l


func _row(kind: int) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(420, 26)
	b.disabled = not Net.is_host()
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 5
	h.offset_right = -5
	h.add_theme_constant_override("separation", 5)
	b.add_child(h)
	var mark := UiTheme.label("", 10)
	mark.custom_minimum_size.x = 14
	mark.name = "Mark"
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(mark)
	var icon := UiTheme.sprite_icon(EXTRA_ICONS.get(kind, Pickups.ICONS.get(kind, "pu_treat")), 18)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(icon)
	var words := VBoxContainer.new()
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.add_theme_constant_override("separation", 0)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(words)
	words.add_child(UiTheme.label(Pickups.TITLES[kind], 9))
	var about := UiTheme.label(Pickups.about(kind), 7, UiTheme.COCOA)
	about.autowrap_mode = TextServer.AUTOWRAP_WORD
	about.custom_minimum_size.x = 360
	words.add_child(about)
	b.toggled.connect(func(on: bool) -> void:
		Net.set_powerup(kind, on)
		Audio.play("select", -6.0))
	return b


## Shows what's switched on (after the host changes something).
func refresh() -> void:
	var on := 0
	for k in _rows.size():
		var enabled: bool = _kinds[k] in Net.powerups
		_rows[k].set_pressed_no_signal(enabled)
		var mark: Label = _rows[k].find_child("Mark", true, false)
		mark.text = "ON" if enabled else "off"
		mark.add_theme_color_override("font_color", Color("3a9f6a") if enabled else Color("a39488"))
		mark.add_theme_font_size_override("font_size", 8)
		on += int(enabled)
	_count.text = "%d of %d on" % [on, _rows.size()]
	if seat >= 0:
		_hint.text = "{move} choose   {dash} switch on / off   {special} done" if Net.is_host() else "{special} done"
	else:
		_hint.text = "Click one to switch it on or off." if Net.is_host() else ""
	_hint.visible = _hint.text != ""
	if seat >= 0 and not _rows.is_empty():
		_rows[_sel].grab_focus()


## A controller's step: up/down picks, the bottom button switches, the top
## button (or + / -) closes.
func nav_input(n: Dictionary) -> void:
	if n["alt"] or n["menu"]:
		close()
		return
	if n["y"] != 0:
		_sel = posmod(_sel + n["y"], _rows.size())
		_rows[_sel].grab_focus()
		Audio.play("select", -8.0)
	if n["ok"] and Net.is_host():
		_rows[_sel].button_pressed = not _rows[_sel].button_pressed


func close() -> void:
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
