class_name Hud
extends CanvasLayer
## Scoreboard, clock, your health and cooldowns, the event feed, banners,
## the cleanup meter and the results card. Built in code; it sits on top of
## the pixel-art world at full resolution so text stays crisp.

var arena: Match

var _root: Control
var _score_l: Label
var _score_r: Label
var _clock: Label
var _phase: Label
var _tidy_box: Control
var _tidy_bar: ProgressBar
var _tidy_label: Label
var _hp_bar: ProgressBar
var _special_bar: ProgressBar
var _special_label: Label
var _dash_bar: ProgressBar
var _card: Control
var _feed: VBoxContainer
var _banner: VBoxContainer
var _banner_title: Label
var _banner_sub: Label
var _banner_tween: Tween
var _hint: Label
var _results: Control
var _pause: Control


func setup(match_node: Match) -> void:
	arena = match_node
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UiTheme.build()
	add_child(_root)
	_build_scoreboard()
	_build_card()
	_build_feed()
	_build_banner()
	_hint = UiTheme.label("", 8, Color.WHITE, true)
	_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint.position.y -= 14
	_root.add_child(_hint)
	on_phase_changed()


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

	_tidy_box = VBoxContainer.new()
	_tidy_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_tidy_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_tidy_box.position.y = 44
	_root.add_child(_tidy_box)
	_tidy_label = UiTheme.label("House tidiness", 8, Color.WHITE, true)
	_tidy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tidy_box.add_child(_tidy_label)
	_tidy_bar = UiTheme.bar(Color("8ff0a4"), 140, 6)
	_tidy_box.add_child(_tidy_bar)


func _build_card() -> void:
	var me := arena.local_player()
	if me == null:
		return
	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", UiTheme.box(Color(0.23, 0.16, 0.19, 0.85), Roster.TEAM_COLORS[me.team], 8, 1, 4))
	_card.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_card.position += Vector2(6, -6)
	_root.add_child(_card)
	var row := HBoxContainer.new()
	_card.add_child(row)
	row.add_child(UiTheme.sprite_icon(me.char_id, 28))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	row.add_child(col)
	col.add_child(UiTheme.label("%s  ·  %s" % [me.data["name"], me.data["role"]], 8, Color.WHITE))
	_hp_bar = UiTheme.bar(Color("8ff0a4"), 80, 5)
	col.add_child(_hp_bar)
	_special_label = UiTheme.label("", 7, Color("ffe9c7"))
	col.add_child(_special_label)
	var bars := HBoxContainer.new()
	bars.add_theme_constant_override("separation", 3)
	col.add_child(bars)
	_special_bar = UiTheme.bar(Color("ffd84d"), 56, 3)
	_dash_bar = UiTheme.bar(Color("9fd8ff"), 21, 3)
	bars.add_child(_special_bar)
	bars.add_child(_dash_bar)


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
	_tidy_box.visible = phase == Match.Phase.CLEANUP
	match phase:
		Match.Phase.LOADING:
			_phase.text = "waiting for everyone..."
			_hint.text = ""
		Match.Phase.COUNTDOWN:
			_phase.text = "GET READY"
			_hint.text = "Move: WASD / Arrows   Attack: J   Special: K   Dash: Space   Throw remote: E"
		Match.Phase.WAR:
			_phase.text = "WAR FOR THE REMOTE"
			_hint.text = "Move: WASD / Arrows   Attack: J   Special: K   Dash: Space   Throw remote: E"
		Match.Phase.WHISTLE:
			_phase.text = "TRUCE!"
			_hint.text = ""
		Match.Phase.CLEANUP:
			_phase.text = "CLEAN UP BEFORE THEY'RE IN"
			_hint.text = "Hold E by anything broken or knocked over   ·   \"x2\" needs two helpers (or Unit-7 / The Claw)   ·   Return the remote"


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
	if arena.phase == Match.Phase.CLEANUP:
		var tidy := arena.tidiness()
		_tidy_bar.value = tidy
		_tidy_label.text = "House tidiness  %d%%   (parents need %d%%)" % [roundi(tidy * 100.0), roundi(Match.TIDY_PASS * 100.0)]
	var me := arena.local_player()
	if me and _hp_bar:
		_hp_bar.value = float(me.hp) / float(me.max_hp)
		var sp: Dictionary = me.data["special"]
		_special_bar.value = 1.0 - me.special_cd / float(sp["cooldown"])
		_dash_bar.value = 1.0 - me.dash_cd / Player.DASH_COOLDOWN
		var ready := "ready!" if me.special_cd <= 0.0 else "%.1fs" % me.special_cd
		if arena.phase == Match.Phase.CLEANUP:
			_special_label.text = "Hold E to fix things (%s)" % me.data["tidy_note"].trim_suffix(".").to_lower()
		elif me.is_ko:
			_special_label.text = "KO'd! Back in a moment..."
		elif me.carrying:
			_special_label.text = "Carrying the remote! E: pass it  (no dashing)"
		elif me.hiding:
			_special_label.text = "Hidden under the furniture. Pounce!"
		elif me.stealthed:
			_special_label.text = "Invisible! Your next hit does double damage."
		else:
			_special_label.text = "K: %s  %s" % [sp["name"], ready]


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and arena.phase != Match.Phase.RESULTS:
		_toggle_pause()
		get_viewport().set_input_as_handled()


func _toggle_pause() -> void:
	if _pause:
		_pause.queue_free()
		_pause = null
		return
	_pause = _centered_panel()
	var col: VBoxContainer = _pause.get_child(0)
	col.add_child(UiTheme.label("Leave the match?", 12))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)
	var stay := Button.new()
	stay.text = "Keep playing"
	stay.pressed.connect(_toggle_pause)
	row.add_child(stay)
	var leave := Button.new()
	leave.text = "Leave"
	leave.pressed.connect(func() -> void: Net.leave())
	row.add_child(leave)
	stay.grab_focus()


func _centered_panel() -> PanelContainer:
	var holder := CenterContainer.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
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
	_tidy_box.visible = false
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
	for line in _awards():
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
		again.grab_focus()
	else:
		row.add_child(UiTheme.label("Waiting for the host...", 8))
	var leave := Button.new()
	leave.text = "Leave"
	leave.pressed.connect(func() -> void: Net.leave())
	row.add_child(leave)


func _awards() -> Array[String]:
	var out: Array[String] = []
	for award in [["caps", "Remote runner"], ["bonks", "Most bonks"], ["fixes", "Tidiest"]]:
		var best_pid := 0
		var best := 0
		for pid: int in arena.stats:
			var v: int = arena.stats[pid][award[0]]
			if v > best:
				best = v
				best_pid = pid
		if best > 0 and arena.players.has(best_pid):
			out.append("%s: %s (%d)" % [award[1], arena.players[best_pid].display_name, best])
	return out
