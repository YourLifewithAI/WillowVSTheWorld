class_name Hud
extends CanvasLayer
## Scoreboard, clock, a card per person on this screen (health, cooldowns,
## gag meter; their chore in cleanup), the event feed, banners, the cleanup
## panel (see ChorePanel), the menu and the results card. Built in code; it sits on top of the pixel-art world at full
## resolution so text stays crisp.
##
## Controllers never move the menus' focus (several people share one screen,
## see Seats); the menu and results are driven by each seat's + / - and bottom
## buttons instead (see _poll_menus). Only the keyboard and mouse can end the
## session: a menu opened from a controller offers "Keep playing" and "Back to
## lobby".

const KEY_HINT := "Move: WASD   Attack: J   Special: K   Up close (or throw the remote): E   Gag: I   Dash: Space"
const PAD_HINT := "Stick: move   Bottom: dash   Left: attack   Top: special   Right: up close (or throw the remote)   SL/SR: gag   + or -: menu"

var arena: Match

var _root: Control
var _score_l: Label
var _score_r: Label
var _clock: Label
var _phase: Label
var _chore_panel: ChorePanel
## One per person on this screen: {player, hp, special_bar, dash_bar, gag_bar, gag_label, special_label}.
var _cards: Array[Dictionary] = []
var _feed: VBoxContainer
var _banner: VBoxContainer
var _banner_title: Label
var _banner_sub: Label
var _banner_tween: Tween
var _hint: Label
var _results: Control
var _pause: Control
var _pause_buttons: Array[Button] = []
## Who opened the menu: a seat, or -1 for the keyboard/mouse.
var _pause_seat := -1
var _pause_sel := 0
var _muted_seat := -1
## Why the game is paused right now ("menu", "lost").
var _pause_reasons: Dictionary = {}
var _lost_panel: Control
## Seats whose dropped controller everyone agreed to carry on without (Esc).
var _lost_dismissed: Dictionary = {}
var _rematch: Button
var _results_ready := false


func setup(match_node: Match) -> void:
	arena = match_node
	process_mode = Node.PROCESS_MODE_ALWAYS  # the menu works while the game is paused
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UiTheme.build()
	add_child(_root)
	_build_scoreboard()
	_build_cards()
	_build_feed()
	_build_banner()
	_hint = UiTheme.label("", 8, Color.WHITE, true)
	_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint.position.y -= 14 if not arena.shared_screen() else 58
	_root.add_child(_hint)
	on_phase_changed()


func _exit_tree() -> void:
	# Leaving with the menu open (Back to lobby, or the host ending the match)
	# mustn't leave anyone's character ignoring them next match.
	if _muted_seat >= 0:
		Seats.set_muted(_muted_seat, false)
		_muted_seat = -1
	if get_tree() and get_tree().paused:
		get_tree().paused = false


## Pauses while there's any reason to (and only when everyone playing is on this screen).
func _set_paused(reason: String, on: bool) -> void:
	if on:
		_pause_reasons[reason] = true
	else:
		_pause_reasons.erase(reason)
	get_tree().paused = arena.can_pause() and not _pause_reasons.is_empty()


## Someone's controller dropped out: wait for it (when everyone is on this
## screen), and tell them how to get back in.
func show_lost(lost: Array[Player]) -> void:
	# Forget "carry on without them" for anyone who came back.
	var still := {}
	for p in lost:
		still[p.seat] = true
	for k: int in _lost_dismissed.keys():
		if not still.has(k):
			_lost_dismissed.erase(k)
	var fresh := lost.filter(func(p: Player) -> bool: return not _lost_dismissed.has(p.seat))
	if _lost_panel:
		_lost_panel.queue_free()
		_lost_panel = null
	if fresh.is_empty() or _results:
		_set_paused("lost", false)
		return
	_lost_panel = _centered_panel()
	if _pause:
		# An open menu stays on top.
		_root.move_child(_lost_panel.get_parent(), _pause.get_parent().get_index())
	var col: VBoxContainer = _lost_panel.get_child(0)
	var who := ", ".join(lost.map(func(p: Player) -> String: return Seats.tag(p.seat)))
	col.add_child(UiTheme.label("%s: controller disconnected" % who, 12, Seats.color(lost[0].seat).darkened(0.35)))
	var help := UiTheme.label("Wake it up by pressing any button on it (if its lights keep running, pair it again:\n"
		+ "hold the small round button on its inner edge). Or hold a spare Joy-Con sideways and press SL + SR.", 8)
	col.add_child(help)
	if arena.can_pause():
		col.add_child(UiTheme.label("The game waits for them. Esc: carry on without them.", 8, UiTheme.COCOA))
	_set_paused("lost", true)


func _build_scoreboard() -> void:
	var top := HBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top.position.y = 3
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	_root.add_child(top)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.box(Color(0.23, 0.16, 0.19, 0.85), Color("fff4e3"), 8, 1, 4))
	top.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)
	row.add_child(UiTheme.sprite_icon("willow", 18))
	_score_l = UiTheme.label("0", 16, Roster.TEAM_COLORS[0], true)
	row.add_child(_score_l)
	var mid := VBoxContainer.new()
	mid.add_theme_constant_override("separation", -2)
	_clock = UiTheme.label("3:00", 14, Color.WHITE, true)
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_phase = UiTheme.label("", 7, Color("ffe9c7"), true)
	_phase.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid.add_child(_clock)
	mid.add_child(_phase)
	mid.custom_minimum_size.x = 96
	row.add_child(mid)
	_score_r = UiTheme.label("0", 16, Roster.TEAM_COLORS[1], true)
	row.add_child(_score_r)
	row.add_child(UiTheme.sprite_icon("butler", 18))

	_chore_panel = ChorePanel.new(arena)
	_chore_panel.position = Vector2(6, 6)
	_root.add_child(_chore_panel)


## A card per person on this screen: along the bottom when several share it,
## in the corner when it's just you.
func _build_cards() -> void:
	var locals := arena.local_players()
	if locals.is_empty():
		return
	var shared := locals.size() > 1
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 4)
	if shared:
		strip.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
		strip.grow_horizontal = Control.GROW_DIRECTION_BOTH
		strip.alignment = BoxContainer.ALIGNMENT_CENTER
		strip.position.y -= 4
	else:
		strip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
		strip.position += Vector2(6, -6)
	strip.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_root.add_child(strip)
	# Everyone's card has to fit across the 640px screen.
	var width := 80.0 if not shared else clampf((632.0 - 4.0 * locals.size()) / locals.size() - 34.0, 40.0, 96.0)
	for p in locals:
		_cards.append(_build_card(strip, p, width, shared))


func _build_card(parent: Control, p: Player, width: float, shared: bool) -> Dictionary:
	var border := p.marker_color() if shared else Roster.TEAM_COLORS[p.team]
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiTheme.box(Color(0.23, 0.16, 0.19, 0.85), border, 8, 2 if shared else 1, 4))
	parent.add_child(card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	card.add_child(row)
	row.add_child(UiTheme.sprite_icon(p.char_id, 20 if shared else 28))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	row.add_child(col)
	var small := 6 if shared else 7
	if shared:
		col.add_child(_status_label("%s  %s" % [Seats.tag(p.seat), p.data["name"]], width, 7, border.lightened(0.25)))
	else:
		col.add_child(UiTheme.label("%s  ·  %s" % [p.data["name"], p.data["role"]], 8, Color.WHITE))
	var c := {"player": p}
	c["hp"] = UiTheme.bar(Color("8ff0a4"), width, 4 if shared else 5)
	col.add_child(c["hp"])
	c["special_label"] = _status_label("", width, small, Color("ffe9c7"))
	col.add_child(c["special_label"])
	var bars := HBoxContainer.new()
	bars.add_theme_constant_override("separation", 3)
	col.add_child(bars)
	c["special_bar"] = UiTheme.bar(Color("ffd84d"), roundf(width * 0.7), 3)
	c["dash_bar"] = UiTheme.bar(Color("9fd8ff"), roundf(width * 0.3) - 3, 3)
	bars.add_child(c["special_bar"])
	bars.add_child(c["dash_bar"])
	c["gag_label"] = _status_label("", width, small, Color("e0b8ff"))
	col.add_child(c["gag_label"])
	c["gag_bar"] = UiTheme.bar(Color("c78cff"), width, 3)
	col.add_child(c["gag_bar"])
	return c


## A one-line label that trims itself rather than stretching the card.
func _status_label(text: String, width: float, size: int, color: Color) -> Label:
	var l := UiTheme.label(text, size, color)
	l.custom_minimum_size.x = width
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return l


func _build_feed() -> void:
	_feed = VBoxContainer.new()
	_feed.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_feed.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_feed.position += Vector2(-6, 6)
	_feed.alignment = BoxContainer.ALIGNMENT_BEGIN
	_feed.add_theme_constant_override("separation", 0)
	_root.add_child(_feed)


func _build_banner() -> void:
	_banner = VBoxContainer.new()
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.grow_vertical = Control.GROW_DIRECTION_BOTH
	_banner.position.y -= 50
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner_title = UiTheme.label("", 26, Color("ffd84d"), true)
	_banner_title.add_theme_constant_override("outline_size", 8)
	_banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_sub = UiTheme.label("", 10, Color.WHITE, true)
	_banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_child(_banner_title)
	_banner.add_child(_banner_sub)
	_banner.modulate.a = 0.0
	_root.add_child(_banner)


# ================================================================ updates

func banner(title: String, sub: String = "", color: Color = Color("ffd84d")) -> void:
	_banner_title.text = title
	_banner_title.add_theme_color_override("font_color", color)
	_banner_sub.text = sub
	if _banner_tween:
		_banner_tween.kill()
	_banner.pivot_offset = _banner.size / 2.0
	_banner.scale = Vector2(1.4, 1.4)
	_banner.modulate.a = 1.0
	_banner_tween = create_tween()
	_banner_tween.tween_property(_banner, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_banner_tween.tween_interval(1.8)
	_banner_tween.tween_property(_banner, "modulate:a", 0.0, 0.4)


func feed(text: String, color: Color) -> void:
	var l := UiTheme.label(text, 8, color, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_feed.add_child(l)
	while _feed.get_child_count() > 5:
		var old := _feed.get_child(0)
		_feed.remove_child(old)
		old.queue_free()
	var tw := l.create_tween()
	tw.tween_interval(5.0)
	tw.tween_property(l, "modulate:a", 0.0, 0.6)
	tw.tween_callback(l.queue_free)


func on_phase_changed() -> void:
	var phase := arena.phase
	_chore_panel.visible = phase == Match.Phase.CLEANUP
	match phase:
		Match.Phase.LOADING:
			_phase.text = "waiting for everyone..."
			_hint.text = ""
		Match.Phase.COUNTDOWN:
			_phase.text = "GET READY"
			_hint.text = PAD_HINT if _pads_on_screen() else KEY_HINT
		Match.Phase.WAR:
			_phase.text = "WAR FOR THE REMOTE"
			_hint.text = PAD_HINT if _pads_on_screen() else KEY_HINT
		Match.Phase.WHISTLE:
			_phase.text = "TRUCE!"
			_hint.text = ""
		Match.Phase.CLEANUP:
			_phase.text = "CLEAN UP BEFORE THEY'RE IN"
			_hint.text = "Your face = your job   ·   Grey hand = anyone's   ·   Two dots = two helpers   ·   Hold %s to help" % (
				"right" if _pads_on_screen() else "E")


## Who owns which chore changed (the whistle, or someone wandered off).
func on_chores_changed() -> void:
	if _chore_panel:
		_chore_panel.queue_redraw()


## Is anyone on this screen playing on a controller? (Then hints name buttons, not keys.)
func _pads_on_screen() -> bool:
	for p in arena.local_players():
		if Seats.uses_controller(p.seat):
			return true
	return false


func _process(_delta: float) -> void:
	if arena == null:
		return
	_score_l.text = str(arena.scores[0])
	_score_r.text = str(arena.scores[1])
	var t := int(ceil(arena.time_left))
	_clock.text = "%d:%02d" % [floori(t / 60.0), t % 60]
	if arena.phase == Match.Phase.COUNTDOWN:
		_clock.text = str(maxi(1, t))
	elif arena.phase == Match.Phase.RESULTS:
		_clock.text = "Home!"
	for c in _cards:
		_update_card(c)
	_poll_menus()


func _update_card(c: Dictionary) -> void:
	var me: Player = c["player"]
	if not is_instance_valid(me):
		return
	var keys := Seats.button_names(me.seat)
	c["hp"].value = float(me.hp) / float(me.max_hp)
	var sp: Dictionary = me.data["special"]
	c["special_bar"].value = 1.0 - me.special_cd / float(sp["cooldown"])
	c["dash_bar"].value = 1.0 - me.dash_cd / Player.DASH_COOLDOWN
	c["gag_bar"].value = me.gag_charge
	var gag_label: Label = c["gag_label"]
	var gag_name: String = me.data["gag"]["name"]
	if arena.phase == Match.Phase.CLEANUP or arena.phase == Match.Phase.WHISTLE:
		# How to do the chore this character got (a spare hand's isn't its usual one).
		gag_label.text = Chores.how(arena.my_chore(me), arena.has_owner_move(me)).replace("{interact}", keys["interact"])
		gag_label.modulate.a = 1.0
	elif me.gag_t > 0.0:
		gag_label.text = "%s!" % gag_name.to_upper()
	elif me.gag_charge >= 1.0:
		gag_label.text = "%s: %s READY!" % [keys["gag"], gag_name.to_upper()]
		gag_label.modulate.a = 0.6 + 0.4 * sin(Time.get_ticks_msec() / 120.0)
	else:
		gag_label.text = "%s: %s  %d%%" % [keys["gag"], gag_name, roundi(me.gag_charge * 100.0)]
		gag_label.modulate.a = 1.0
	var ready := "ready!" if me.special_cd <= 0.0 else "%.1fs" % me.special_cd
	var label: Label = c["special_label"]
	if Seats.seat(me.seat) and Seats.seat(me.seat).lost:
		label.text = "Controller lost! Press any button on it"
	elif me.captured_by != 0:
		label.text = "Swallowed! It's dark in here..." if me.capture_mode == Player.Capture.SWALLOWED else "Grabbed by the Claw!"
	elif me.dance_t > 0.0:
		label.text = "Can't stop dancing!"
	elif arena.phase == Match.Phase.CLEANUP:
		var mine := arena.my_chore(me)
		var left: int = arena.chore_totals().get(mine, [0, 0.0])[0]
		if mine == Chores.Chore.NONE:
			label.text = "Help out! Hold %s by anything" % keys["interact"]
		elif left > 0:
			label.text = "%s%s  %d left" % ["TURBO! " if me.turbo_t > 0.0 else "", Chores.VERB.get(mine, ""), left]
		else:
			label.text = "All done! Now help the others"
	elif me.is_ko:
		label.text = "KO'd! Back in a moment..."
	elif me.carrying:
		label.text = "Carrying the remote! %s: pass it  (no dashing)" % keys["interact"]
	elif me.pickup_status() != "":
		label.text = me.pickup_status()
	elif me.hiding:
		label.text = "Hidden under the furniture. Pounce!"
	elif me.stealthed:
		label.text = "Invisible! Your next hit does double damage."
	else:
		label.text = "%s: %s  %s" % [keys["special"], sp["name"], ready]


## Controllers can't move the menus' focus, so each seat's + / - opens the
## menu (anyone's closes it), and whoever opened it steers it.
func _poll_menus() -> void:
	for p in arena.local_players():
		var n := Seats.nav(p.seat)
		if _results:
			if n["menu"] and _results_ready and is_instance_valid(_rematch):
				_rematch.pressed.emit()
				return
		elif _pause:
			if n["menu"]:
				_toggle_pause()
				return
			if p.seat != _pause_seat or _pause_buttons.is_empty():
				continue
			if n["x"] != 0:
				_pause_sel = posmod(_pause_sel + n["x"], _pause_buttons.size())
				_highlight_pause_sel()
				Audio.play("select", -6.0)
			if n["ok"]:
				_pause_buttons[_pause_sel].pressed.emit()
				return
		elif n["menu"] and arena.phase != Match.Phase.RESULTS:
			_toggle_pause(p.seat)
			return


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and arena.phase != Match.Phase.RESULTS:
		if _lost_panel and not _pause:
			# Carry on without whoever dropped out (until someone else drops out).
			for p in arena.local_players():
				var st = Seats.seat(p.seat)
				if st != null and st.lost:
					_lost_dismissed[p.seat] = true
			_lost_panel.queue_free()
			_lost_panel = null
			_set_paused("lost", false)
		else:
			_toggle_pause(-1)
		get_viewport().set_input_as_handled()


## Opens (or closes) the menu. `opener` is the seat whose controller opened
## it, or -1 for the keyboard/mouse. The game pauses if everyone playing is on
## this screen; otherwise the opener's character stands still meanwhile.
func _toggle_pause(opener: int = -1) -> void:
	if _pause:
		_pause.queue_free()
		_pause = null
		_pause_buttons.clear()
		if _muted_seat >= 0:
			Seats.set_muted(_muted_seat, false)
			_muted_seat = -1
		_set_paused("menu", false)
		return
	_pause_seat = opener
	_pause_sel = 0
	_set_paused("menu", true)
	if not arena.can_pause():
		_muted_seat = opener if opener >= 0 else Seats.keyboard_seat()
		if _muted_seat >= 0:
			Seats.set_muted(_muted_seat, true)
	_pause = _centered_panel()
	var col: VBoxContainer = _pause.get_child(0)
	col.add_child(UiTheme.label("Paused" if arena.can_pause() else "Menu", 12))
	if opener >= 0:
		col.add_child(UiTheme.label("%s: stick left/right to choose, bottom button to pick, + or - to go back" % Seats.tag(opener), 8, UiTheme.COCOA))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)
	var stay := Button.new()
	stay.text = "Keep playing"
	stay.pressed.connect(_toggle_pause)
	row.add_child(stay)
	_pause_buttons = [stay]
	if Net.is_host():
		var lobby := Button.new()
		lobby.text = "Back to lobby"
		lobby.pressed.connect(func() -> void:
			get_tree().paused = false
			Net.return_to_lobby())
		row.add_child(lobby)
		_pause_buttons.append(lobby)
	if opener < 0:
		# Ending the whole session is for the keyboard or mouse only.
		var leave := Button.new()
		leave.text = "Leave the match"
		leave.pressed.connect(func() -> void:
			get_tree().paused = false
			Net.leave())
		row.add_child(leave)
	col.add_child(HSeparator.new())
	col.add_child(SoundSettings.build(false))
	if opener >= 0:
		# Steered by that seat's stick (see _poll_menus), never by keyboard focus:
		# someone else may be playing on the keyboard meanwhile.
		for b: Button in row.get_children():
			b.focus_mode = Control.FOCUS_NONE
		get_viewport().gui_release_focus()
		_highlight_pause_sel()
	else:
		stay.grab_focus()


## Shows which button a controller-opened menu has selected.
func _highlight_pause_sel() -> void:
	for i in _pause_buttons.size():
		var b: Button = _pause_buttons[i]
		if i == _pause_sel:
			b.add_theme_stylebox_override("normal", b.get_theme_stylebox("hover"))
			b.add_theme_color_override("font_color", b.get_theme_color("font_hover_color"))
		else:
			b.remove_theme_stylebox_override("normal")
			b.remove_theme_color_override("font_color")


func _centered_panel() -> PanelContainer:
	var holder := CenterContainer.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE  # only the panel itself takes clicks
	_root.add_child(holder)
	var panel := PanelContainer.new()
	holder.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)
	# Return the panel, but free the holder with it.
	panel.tree_exiting.connect(holder.queue_free)
	return panel


func show_results(results: Dictionary) -> void:
	if _pause:
		_toggle_pause()
	if _lost_panel:
		_lost_panel.queue_free()
		_lost_panel = null
	_set_paused("lost", false)
	_chore_panel.visible = false
	_hint.text = ""
	_phase.text = "THE PARENTS ARE HOME"
	_results = _centered_panel()
	var col: VBoxContainer = _results.get_child(0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	var verdict: int = results["verdict"]
	var winner: int = results["winner"]
	var tidy: float = results["tidy"]
	var title := ""
	var sub := ""
	match verdict:
		Match.Verdict.SPOTLESS:
			title = "Spotless!"
			sub = "\"Were you all asleep this whole time?\"  Treats for everyone."
		Match.Verdict.FINE:
			title = "Nobody noticed a thing"
			sub = "The house passes inspection. Mostly."
		Match.Verdict.GROUNDED:
			title = "GROUNDED!"
			sub = "\"WHAT HAPPENED IN HERE?!\"  The TV is unplugged for a week."
	var t := UiTheme.label(title, 22, Color("e05a5a") if verdict == Match.Verdict.GROUNDED else Color("3a9f6a"))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(t)
	var s := UiTheme.label(sub, 9)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(s)
	var tv := ""
	if verdict == Match.Verdict.GROUNDED:
		tv = "Nobody gets to watch anything."
	elif winner < 0:
		tv = "It's a tie, so the TV stays on the weather channel."
	else:
		tv = "The %s won the remote: tonight it's \"%s\"!" % [Roster.TEAM_NAMES[winner], Roster.TEAM_SHOWS[winner]]
	var tvl := UiTheme.label(tv, 10, Roster.TEAM_COLORS[winner].darkened(0.3) if winner >= 0 else UiTheme.INK)
	tvl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(tvl)
	var sc := UiTheme.label("Captures  %s %d  -  %d %s      Tidiness %d%%" % [
		Roster.TEAM_NAMES[0], arena.scores[0], arena.scores[1], Roster.TEAM_NAMES[1], roundi(tidy * 100.0)], 9)
	sc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sc)
	for line in _awards() + _cleanup_lines():
		var al := UiTheme.label(line, 8, UiTheme.COCOA)
		al.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(al)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)
	if Net.is_host():
		var again := Button.new()
		again.text = "Rematch"
		again.pressed.connect(Net.start_match)
		row.add_child(again)
		var lobby := Button.new()
		lobby.text = "Back to lobby"
		lobby.pressed.connect(Net.return_to_lobby)
		row.add_child(lobby)
		_rematch = again
		# Everyone is still mashing buttons as the verdict appears: wait a moment
		# before anything can start a rematch.
		get_tree().create_timer(3.0).timeout.connect(func() -> void:
			_results_ready = true
			if is_instance_valid(again):
				again.grab_focus())
		if _pads_on_screen():
			var hint := UiTheme.label("Press + or - on a controller to play again", 8, UiTheme.COCOA)
			hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			col.add_child(hint)
	else:
		row.add_child(UiTheme.label("Waiting for the host...", 8))
	var leave := Button.new()
	leave.text = "Leave"
	leave.pressed.connect(func() -> void: Net.leave())
	row.add_child(leave)


func _awards() -> Array[String]:
	var out: Array[String] = []
	for award in [["caps", "Remote runner"], ["bonks", "Most bonks"], ["tidied", "Tidiest"]]:
		var best_pid := 0
		var best := 0.0
		for pid: int in arena.stats:
			var v := float(arena.stats[pid].get(award[0], 0))
			if v > best:
				best = v
				best_pid = pid
		if best > 0.0 and arena.players.has(best_pid):
			out.append("%s: %s (%d)" % [award[1], arena.players[best_pid].display_name, roundi(best)])
	return out


## What everyone on this screen got done in their own job, and which rooms the
## parents will find a mess in.
const DONE_LINES := {
	Chores.Chore.FLOOR: "vacuumed up %d piles", Chores.Chore.CLUTTER: "hid %d things under the couch",
	Chores.Chore.STAIN: "thumped away %d stains", Chores.Chore.FETCH: "fetched %d things",
	Chores.Chore.SOFT: "fluffed %d cushions", Chores.Chore.REPAIR: "fixed %d things",
	Chores.Chore.LIFT: "lifted %d heavy things", Chores.Chore.HIGH: "put %d things back up high",
}


func _cleanup_lines() -> Array[String]:
	var out: Array[String] = []
	var parts: Array[String] = []
	var lumpy := false
	for p in arena.local_players():
		var c := arena.my_chore(p)
		var n := int(arena.stats.get(p.pid, {}).get("own", 0))
		if DONE_LINES.has(c) and n > 0:
			parts.append("%s %s" % [p.display_name, DONE_LINES[c] % n])
			lumpy = lumpy or (c == Chores.Chore.CLUTTER and n >= 10)
	if not parts.is_empty():
		out.append(",  ".join(parts) + ".")
	var rooms := arena.leftovers_by_room()
	if not rooms.is_empty():
		var bits: Array[String] = []
		for r: String in rooms:
			bits.append("%s: %d left" % [r, rooms[r]])
		out.append("Still a mess:  " + ",  ".join(bits.slice(0, 4)))
	if lumpy:
		out.append("\"Why is the couch so lumpy?\"")
	return out
