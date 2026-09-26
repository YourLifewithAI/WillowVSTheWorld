class_name Player
extends CharacterBody2D
## One pet or robot.
##
## Networking model: whoever controls this character (a human's machine, or
## the host for bots) is its multiplayer authority. That machine reads input,
## moves the body, and streams position to everyone else, which keeps movement
## snappy. Anything that matters for fairness (health, KOs, the remote, the
## score, furniture) is decided by the host in Match; the owner only *reports*
## what it hit.
##
## Stealth is streamed as a flag. Each machine then decides for itself how to
## draw a hidden character: invisible to enemies, ghostly to teammates, and
## visible to enemies who have a nose or x-ray vision nearby (Match.is_revealed).

enum Action { ATTACK, SPECIAL, DASH }

const SEND_RATE := 30.0
const DASH_SPEED := 430.0
const DASH_TIME := 0.16
const DASH_COOLDOWN := 1.1
const KNOCK_DECAY := 7.0
const TUMBLE_SPEED := 140.0
## Body radius on the floor, used for hit checks.
const BODY_RADIUS := 7.0
## Seconds of standing still before a sneaky cat disappears.
const SNEAK_DELAY := 1.0
## Damage done to furniture by a character slamming into it.
const CRASH_DAMAGE := 18.0

var pid := 0
var char_id := "willow"
var data: Dictionary = {}
var team := 0
var display_name := ""
var is_bot := false
## Drives this character instead of the keyboard (bots and --autopilot).
var brain: BotBrain
var arena: Match

# --- Mirrored from the host.
var hp := 100
var max_hp := 100
var is_ko := false
var invuln := 0.0
var carrying := false
## Host only: when this character was last seen hidden (validates ambushes).
var last_stealth_time := -100.0

# --- Simulated by the owner, streamed to everyone else.
var facing := Vector2.RIGHT
var z := 0.0
var moving := false
var dashing := false
var interacting := false
var tumbling := false
var stealthed := false
## Stealthed because it's under furniture (Zoomba).
var hiding := false

# --- Owner only.
var knock_vel := Vector2.ZERO
var stun := 0.0
var attack_cd := 0.0
var special_cd := 0.0
var dash_cd := 0.0
var buff_mult := 1.0
var vanish_t := 0.0
var _buff_t := 0.0
var _dash_t := 0.0
var _slam_t := 0.0
var _slam_ambush := false
var _still_t := 0.0
var _reveal_t := 0.0
var _send_accum := 0.0
var _proj_counter := 0
var _ghost_t := 0.0
var _crash_cd: Dictionary = {}

# --- Everyone else: smoothing toward the last received position.
var _net_pos := Vector2.ZERO
var _has_net := false

# --- Visuals.
var _visual: Node2D
var _sprite: Sprite2D
var _weapon: Sprite2D
var _overlay: Node2D
var _anim_t := 0.0
var _flash := 0.0
var _squash := 0.0
var _recoil := 0.0
var _swing := 0.0
var _face_left := false
var _telegraph := 0.0
var _stun_vis := 0.0
var _flip_t := 0.0
var _revealed := false


func setup(p_id: int, info: Dictionary, p_arena: Match) -> void:
	pid = p_id
	name = "P%d" % p_id
	char_id = info.get("char", "willow")
	data = Roster.get_char(char_id)
	team = data["team"]
	display_name = info.get("name", data["name"])
	is_bot = info.get("bot", false)
	max_hp = data["hp"]
	hp = max_hp
	arena = p_arena
	set_multiplayer_authority(1 if is_bot else p_id)


func _ready() -> void:
	collision_layer = 4
	# Flyers pass over furniture; Zoomba drives under it.
	var over_furniture: bool = data.get("flying", false) or data.get("low_profile", false)
	collision_mask = 1 if over_furniture else 3
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	z = hover()
	_net_pos = position
	_visual = Node2D.new()
	add_child(_visual)
	_sprite = Sprite2D.new()
	_sprite.texture = Roster.texture(char_id)
	_sprite.centered = false
	var s := _sprite.texture.get_size()
	_sprite.offset = Vector2(-floor(s.x / 2.0), -s.y + 1)
	_visual.add_child(_sprite)
	var w: Dictionary = data["weapon"]
	if w.has("sprite"):
		_weapon = Sprite2D.new()
		_weapon.texture = Roster.texture(w["sprite"])
		if int(w["kind"]) == Roster.Weapon.MELEE:
			# Hangs from its top (the wrecking ball's chain).
			_weapon.centered = false
			_weapon.offset = Vector2(-floor(_weapon.texture.get_width() / 2.0), 0)
		_visual.add_child(_weapon)
	_overlay = Node2D.new()
	_overlay.z_index = 30
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)


func hover() -> float:
	return float(data.get("hover", 0.0))


func is_local() -> bool:
	return is_multiplayer_authority() and not is_bot


func sprite_height() -> float:
	return _sprite.texture.get_size().y if _sprite else 16.0


# ================================================================ simulation

func _physics_process(delta: float) -> void:
	if arena == null:
		return
	if is_multiplayer_authority():
		_owner_tick(delta)
		_send_accum += delta
		if arena.live and _send_accum >= 1.0 / SEND_RATE:
			_send_accum = 0.0
			_net_state.rpc(position, facing, z, _flags())
	elif _has_net:
		if position.distance_to(_net_pos) > 80.0:
			position = _net_pos
		else:
			position = position.lerp(_net_pos, 1.0 - exp(-18.0 * delta))
	if stealthed and multiplayer.is_server():
		last_stealth_time = Time.get_ticks_msec() / 1000.0


func _gather_input() -> Dictionary:
	if brain:
		return brain.think()
	return {
		"move": Input.get_vector("move_left", "move_right", "move_up", "move_down"),
		"attack": Input.is_action_just_pressed("attack"),
		# Holding attack keeps firing automatic weapons (the gatling).
		"attack_held": Input.is_action_pressed("attack"),
		"special": Input.is_action_just_pressed("special"),
		"dash": Input.is_action_just_pressed("dash"),
		"interact": Input.is_action_pressed("interact"),
		"interact_pressed": Input.is_action_just_pressed("interact"),
	}


func _owner_tick(delta: float) -> void:
	attack_cd = maxf(0.0, attack_cd - delta)
	special_cd = maxf(0.0, special_cd - delta)
	dash_cd = maxf(0.0, dash_cd - delta)
	stun = maxf(0.0, stun - delta)
	vanish_t = maxf(0.0, vanish_t - delta)
	_reveal_t = maxf(0.0, _reveal_t - delta)
	_buff_t = maxf(0.0, _buff_t - delta)
	if _buff_t <= 0.0:
		buff_mult = 1.0

	var inp := _gather_input()
	var free_to_act := arena.can_move() and not is_ko and stun <= 0.0
	var move: Vector2 = inp["move"] if free_to_act and _slam_t <= 0.0 else Vector2.ZERO
	if move.length() > 1.0:
		move = move.normalized()
	if move.length() > 0.2:
		facing = move.normalized()

	var speed: float = data["speed"] * buff_mult
	if carrying:
		speed *= data["carry_speed"]
	var v := move * speed

	if _dash_t > 0.0:
		_dash_t -= delta
		v = facing * DASH_SPEED
	if _slam_t > 0.0:
		_slam_t -= delta
		var sp: Dictionary = data["special"]
		var k := clampf(1.0 - _slam_t / float(sp["windup"]), 0.0, 1.0)
		z = hover() + float(sp["rise"]) * sin(k * PI * 0.5)
		if _slam_t <= 0.0:
			_land_slam()

	v += knock_vel
	knock_vel *= exp(-KNOCK_DECAY * delta)
	if knock_vel.length() < 5.0:
		knock_vel = Vector2.ZERO
	if is_ko:
		v = Vector2.ZERO
	velocity = Iso.to_screen(v)
	move_and_slide()
	_check_crashes(delta)

	moving = v.length() > 5.0
	dashing = _dash_t > 0.0
	tumbling = knock_vel.length() > TUMBLE_SPEED
	interacting = bool(inp["interact"]) and not is_ko and arena.can_move()
	_update_stealth(delta)

	if not free_to_act:
		return
	var at_war := arena.phase == Match.Phase.WAR
	if inp["interact_pressed"] and carrying:
		arena.request_throw(self, facing)
	if inp["dash"] and dash_cd <= 0.0 and not carrying and _slam_t <= 0.0:
		_dash_t = DASH_TIME * float(data.get("dash_mult", 1.0))
		dash_cd = DASH_COOLDOWN
		_play_action.rpc(Action.DASH, facing)
	if not at_war or carrying or _slam_t > 0.0:
		return
	var auto_fire: bool = inp.get("attack_held", false) and float(data["weapon"]["cooldown"]) < 0.2
	if (inp["attack"] or auto_fire) and attack_cd <= 0.0:
		_do_attack()
	elif inp["special"] and special_cd <= 0.0:
		_do_special()


func _flags() -> int:
	return int(moving) | int(dashing) << 1 | int(interacting) << 2 | int(tumbling) << 3 \
		| int(stealthed) << 4 | int(hiding) << 5


@rpc("authority", "call_remote", "unreliable_ordered")
func _net_state(p: Vector2, f: Vector2, pz: float, flags: int) -> void:
	_net_pos = p
	_has_net = true
	facing = f
	z = pz
	moving = flags & 1 != 0
	dashing = flags & 2 != 0
	interacting = flags & 4 != 0
	tumbling = flags & 8 != 0
	stealthed = flags & 16 != 0
	hiding = flags & 32 != 0


## Knocked into furniture hard enough? That furniture takes a beating.
func _check_crashes(delta: float) -> void:
	for key in _crash_cd.keys():
		_crash_cd[key] -= delta
		if _crash_cd[key] <= 0.0:
			_crash_cd.erase(key)
	if knock_vel.length() < TUMBLE_SPEED or arena.phase != Match.Phase.WAR:
		return
	for k in get_slide_collision_count():
		var f := get_slide_collision(k).get_collider() as Furniture
		if f and not _crash_cd.has(f):
			_crash_cd[f] = 0.4
			arena.report_furniture_hit(f, CRASH_DAMAGE)


# ==================================================================== stealth

func _update_stealth(delta: float) -> void:
	if moving or dashing or tumbling:
		_still_t = 0.0
	else:
		_still_t += delta
	var can_hide := not carrying and not is_ko and _reveal_t <= 0.0 and arena.phase == Match.Phase.WAR
	hiding = can_hide and data.get("low_profile", false) and arena.level.furniture_at(position) != null
	var sneaking: bool = data.get("sneaky", false) and _still_t >= SNEAK_DELAY
	stealthed = can_hide and (sneaking or vanish_t > 0.0 or hiding)


## Attacking or getting hit gives your position away for a moment.
func _break_stealth(for_seconds: float) -> void:
	vanish_t = 0.0
	_still_t = 0.0
	_reveal_t = maxf(_reveal_t, for_seconds)
	stealthed = false
	hiding = false


# =================================================================== combat

func _do_attack() -> void:
	var w: Dictionary = data["weapon"]
	attack_cd = w["cooldown"]
	var ambush := stealthed
	_break_stealth(0.6)
	_play_action.rpc(Action.ATTACK, facing)
	if int(w["kind"]) == Roster.Weapon.MELEE:
		_hit_arc(w, ambush)
	else:
		_fire(0, w, ambush)


func _do_special() -> void:
	var sp: Dictionary = data["special"]
	special_cd = sp["cooldown"]
	var ambush := stealthed
	if int(sp["kind"]) == Roster.Special.VANISH:
		vanish_t = float(sp["duration"])
		_still_t = 0.0
		_reveal_t = 0.0
		_play_action.rpc(Action.SPECIAL, facing)
		return
	_break_stealth(0.6)
	_play_action.rpc(Action.SPECIAL, facing)
	match int(sp["kind"]):
		Roster.Special.SLAM:
			_slam_t = sp["windup"]
			_slam_ambush = ambush
		Roster.Special.PROJECTILE:
			_fire(1, sp, ambush)
		Roster.Special.PULL:
			hit_area(position, sp["radius"], 1, 0.0, 0.0, ambush)
			arena.report_special_effect(self)
		Roster.Special.AURA:
			arena.report_special_effect(self)


func _fire(which: int, spec: Dictionary, ambush: bool) -> void:
	var count := int(spec.get("count", 1))
	var spread := deg_to_rad(float(spec.get("spread", 0.0)))
	for k in count:
		# Several pellets fan out across the spread; a single shot wobbles within it.
		var ang := spread * (float(k) / (count - 1) - 0.5) if count > 1 else randf_range(-0.5, 0.5) * spread
		_proj_counter += 1
		_spawn_projectile.rpc(which, facing.rotated(ang), _proj_counter, ambush)


func _land_slam() -> void:
	var sp: Dictionary = data["special"]
	z = hover()
	hit_area(position, sp["radius"], 1, sp["knock"], sp.get("demolition", 0.0), _slam_ambush)
	_squash = 0.45


## Reports every enemy, breakable and piece of furniture in a cone in front of us.
func _hit_arc(w: Dictionary, ambush: bool) -> void:
	var reach: float = w["range"]
	var half_arc: float = float(w["arc"]) * 0.5
	for other: Player in arena.players.values():
		if other.team == team or other.is_ko:
			continue
		var off := Iso.to_floor(other.position - position)
		var d := off.length()
		if d > reach + BODY_RADIUS:
			continue
		if d > 4.0 and absf(rad_to_deg(facing.angle_to(off))) > half_arc:
			continue
		arena.report_hit(self, other, 0, off.normalized() if d > 0.1 else facing, ambush)
	for item in arena.level.mess_items:
		var off := Iso.to_floor(item.position - position)
		if off.length() <= reach + 6.0 and (off.length() < 4.0 or absf(rad_to_deg(facing.angle_to(off))) <= half_arc):
			arena.report_mess_hit(item, w["knock"], off)
	for f in arena.level.furniture:
		var off := Iso.to_floor(f.position - position)
		if f.can_be_damaged() and off.length() <= reach + f.reach() and absf(rad_to_deg(facing.angle_to(off))) <= half_arc:
			arena.report_furniture_hit(f, w.get("demolition", 0.0))


## Reports every enemy, breakable and piece of furniture within a radius of a point.
func hit_area(center: Vector2, radius: float, ability: int, force: float, demolition: float, ambush: bool) -> void:
	for other: Player in arena.players.values():
		if other.team == team or other.is_ko:
			continue
		var off := Iso.to_floor(other.position - center)
		if off.length() <= radius + BODY_RADIUS:
			arena.report_hit(self, other, ability, off.normalized() if off.length() > 0.1 else facing, ambush)
	if force > 0.0:
		for item in arena.level.mess_items:
			var off := Iso.to_floor(item.position - center)
			if off.length() <= radius + 6.0:
				arena.report_mess_hit(item, force, off)
	if demolition > 0.0:
		for f in arena.level.furniture:
			if f.can_be_damaged() and Iso.fdist(center, f.position) <= radius + f.reach():
				arena.report_furniture_hit(f, demolition)


@rpc("authority", "call_local", "reliable")
func _spawn_projectile(which: int, dir: Vector2, proj_id: int, ambush: bool) -> void:
	var p := Projectile.new()
	p.setup(self, which, dir, proj_id, is_multiplayer_authority(), ambush)
	arena.level.entities.add_child(p)


@rpc("authority", "call_local", "reliable")
func despawn_projectile(proj_id: int) -> void:
	var n := arena.level.entities.get_node_or_null("Proj_%d_%d" % [pid, proj_id])
	if n:
		n.queue_free()


## Cosmetics for everyone (the owner already did the gameplay part).
@rpc("authority", "call_local", "reliable")
func _play_action(action: int, dir: Vector2) -> void:
	facing = dir
	var fx_parent := arena.level.entities
	match action:
		Action.ATTACK:
			var w: Dictionary = data["weapon"]
			if int(w["kind"]) == Roster.Weapon.MELEE:
				_swing = 1.0
				_squash = 0.2
				Fx.swing(fx_parent, position + Vector2(0, -z + 8), dir, float(w["range"]) * 0.8, Color(1, 1, 1, 0.8))
			else:
				_recoil = 1.0
				_squash = 0.1
		Action.DASH:
			_squash = 0.3
			if not stealthed:
				Fx.puff(fx_parent, position, Color(1, 1, 1, 0.8))
		Action.SPECIAL:
			var sp: Dictionary = data["special"]
			match int(sp["kind"]):
				Roster.Special.VANISH:
					Fx.puff(fx_parent, position, Color(0.8, 0.8, 0.9, 0.9))
					return  # No shout: that would give it away.
				Roster.Special.SLAM:
					_telegraph = sp["windup"]
				Roster.Special.PULL:
					Fx.ring(fx_parent, position, sp["radius"], Color("62f2ff"), true)
				Roster.Special.AURA:
					Fx.ring(fx_parent, position, sp["radius"], Color("62f2ff"), false)
					for k in 5:
						Fx.note(fx_parent, position + Iso.to_screen(Vector2.from_angle(TAU * k / 5.0) * 20.0))
			Fx.text(fx_parent, position + Vector2(0, -sprite_height() - z - 6), String(sp["name"]).to_upper() + "!", Roster.TEAM_COLORS[team].lightened(0.3))


# ================================================= events from the host

func on_damaged(new_hp: int, knock: Vector2, stun_time: float, ambushed: bool) -> void:
	hp = new_hp
	_flash = 0.15
	_squash = 0.3
	if stun_time > 0.0:
		_stun_vis = stun_time
	if data.get("flips", false) and stun_time >= 1.4:
		_flip_t = stun_time
		Fx.text(arena.level.entities, position + Vector2(0, -18 - z), "FLIPPED!", Color.WHITE)
	Fx.burst(arena.level.entities, position + Vector2(0, -8 - z), Color.WHITE)
	if ambushed:
		Fx.text(arena.level.entities, position + Vector2(0, -26 - z), "AMBUSH!", Color("ff5a6e"))
	if is_multiplayer_authority():
		knock_vel = knock
		stun = maxf(stun, stun_time)
		_dash_t = 0.0
		_break_stealth(1.0)


func set_ko(value: bool) -> void:
	is_ko = value
	if value:
		hp = 0
		interacting = false
		if is_multiplayer_authority():
			knock_vel = Vector2.ZERO
			_dash_t = 0.0
			_slam_t = 0.0
			_break_stealth(0.0)
			z = 0.0
		Fx.text(arena.level.entities, position + Vector2(0, -24), "KO!", Color("ffd84d"))


func respawn(at: Vector2) -> void:
	is_ko = false
	hp = max_hp
	invuln = 1.5
	position = at
	_net_pos = at
	z = hover()
	if is_multiplayer_authority():
		knock_vel = Vector2.ZERO
		stun = 0.0
	Fx.puff(arena.level.entities, at, Roster.TEAM_COLORS[team])


func apply_buff(mult: float, duration: float, heal_to: int) -> void:
	hp = heal_to
	Fx.text(arena.level.entities, position + Vector2(0, -sprite_height() - z - 4), "+HYPE", Color("62f2ff"))
	if is_multiplayer_authority():
		buff_mult = mult
		_buff_t = duration


## Called when a phase ends, so nobody is mid-air, stunned or invisible.
func reset_for_phase() -> void:
	is_ko = false
	hp = max_hp
	stealthed = false
	hiding = false
	if is_multiplayer_authority():
		knock_vel = Vector2.ZERO
		stun = 0.0
		vanish_t = 0.0
		_slam_t = 0.0
		z = hover()


# ================================================================== visuals

func _process(delta: float) -> void:
	_anim_t += delta
	_flash = maxf(0.0, _flash - delta)
	invuln = maxf(0.0, invuln - delta)
	_telegraph = maxf(0.0, _telegraph - delta)
	_stun_vis = maxf(0.0, _stun_vis - delta)
	_flip_t = maxf(0.0, _flip_t - delta)
	_squash = move_toward(_squash, 0.0, delta * 2.5)
	_recoil = move_toward(_recoil, 0.0, delta * 8.0)
	_swing = move_toward(_swing, 0.0, delta * 4.0)
	if absf(facing.x) > 0.2:
		_face_left = facing.x < 0.0
	_sprite.flip_h = _face_left
	_sprite.flip_v = _flip_t > 0.0

	var flying: bool = data.get("flying", false)
	var bob := 0.0
	var sx := 1.0 + _squash
	var sy := 1.0 - _squash
	if is_ko:
		_sprite.rotation = PI * 0.5 * (-1.0 if _face_left else 1.0)
		_sprite.modulate = Color(0.7, 0.7, 0.75)
	else:
		_sprite.rotation = 0.0
		if flying:
			bob = sin(_anim_t * 6.0) * 1.5
		elif moving:
			bob = -absf(sin(_anim_t * 16.0)) * 2.0
		if dashing:
			sx += 0.2
			sy -= 0.15
		var tint := Color.WHITE
		if _flash > 0.0:
			tint = Color(1.0, 0.45, 0.45)
		if invuln > 0.0 and int(_anim_t * 16.0) % 2 == 0:
			tint.a = 0.35
		_sprite.modulate = tint
	_sprite.scale = Vector2(sx, sy)
	_visual.position = Vector2(0, round(-z + bob))
	_update_weapon()

	# How visible are we to whoever is looking at this screen?
	var target_alpha := 1.0
	_revealed = false
	if stealthed and not is_ko:
		var viewer := arena.local_player()
		var viewer_team := viewer.team if viewer else team
		if viewer_team == team:
			target_alpha = 0.4
		elif arena.is_revealed(self, viewer_team):
			target_alpha = 0.85
			_revealed = true
		else:
			target_alpha = 0.08 if moving and not hiding else 0.0
	modulate.a = move_toward(modulate.a, target_alpha, delta * 5.0)

	if dashing and not is_ko and not stealthed:
		_ghost_t -= delta
		if _ghost_t <= 0.0:
			_ghost_t = 0.03
			Fx.ghost(arena.level.entities, _sprite, global_position)
	queue_redraw()
	_overlay.queue_redraw()


func _update_weapon() -> void:
	if _weapon == null:
		return
	_weapon.visible = not is_ko and _flip_t <= 0.0
	var hold: Vector2 = data["weapon"]["hold"]
	var side := -1.0 if _face_left else 1.0
	_weapon.flip_h = _face_left
	if int(data["weapon"]["kind"]) == Roster.Weapon.MELEE:
		# The wrecking ball dangles, and swings out when used.
		_weapon.position = Vector2(hold.x * side, hold.y)
		_weapon.rotation = -side * sin(_swing * PI) * 1.6 + sin(_anim_t * 3.0) * 0.08
	else:
		_weapon.position = Vector2((hold.x - _recoil * 3.0) * side, hold.y + (0.0 if moving else sin(_anim_t * 3.0) * 0.5))
		_weapon.rotation = -side * _recoil * 0.25


func _draw() -> void:
	# Shadow, shrinking as we go up.
	var shadow_r := 7.0 - clampf(z / 12.0, 0.0, 3.0)
	draw_colored_polygon(Iso.ellipse(shadow_r, 16), Color(0, 0, 0, 0.25))
	# Team ring (brighter for your own character; red dashes when revealed).
	var ring := Iso.ellipse(9.0 if is_local() else 8.0, 20)
	ring.append(ring[0])
	var col: Color = Color("ff5a6e") if _revealed else Roster.TEAM_COLORS[team]
	col.a = 0.95 if is_local() or _revealed else 0.55
	draw_polyline(ring, col, 1.0)
	# The Claw hangs from a cable on a trolley that rides the ceiling rails.
	if char_id == "claw" and not is_ko:
		var top := Vector2(0, round(-z) - sprite_height() + 2)
		var ceiling := Vector2(0, -arena.level.room.wall_height - 6.0)
		draw_line(top, ceiling, Color("3b4150"), 1.0)
		draw_rect(Rect2(ceiling + Vector2(-5, -3), Vector2(10, 3)), Color("3b4150"))
		draw_rect(Rect2(ceiling + Vector2(-4, -2), Vector2(8, 1)), Color("ffc93c"))
	# Telegraph for slams, so the other team can get out of the way.
	if _telegraph > 0.0:
		var sp: Dictionary = data["special"]
		var r := float(sp["radius"])
		var k := 1.0 - _telegraph / float(sp["windup"])
		var tele := Iso.ellipse(r * k, 28)
		draw_colored_polygon(tele, Color(1, 0.3, 0.3, 0.25))
		var edge := Iso.ellipse(r, 28)
		edge.append(edge[0])
		draw_polyline(edge, Color(1, 0.35, 0.35, 0.8), 1.0)


func _draw_overlay() -> void:
	if is_ko:
		var zz := Vector2(4, -14 - sin(_anim_t * 3.0) * 2.0)
		_overlay.draw_string(ThemeDB.fallback_font, zz, "z", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color.WHITE)
		_overlay.draw_string(ThemeDB.fallback_font, zz + Vector2(4, -5), "z", HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color.WHITE)
		return
	var head := Vector2(0, round(-z) - sprite_height() - 3)
	if arena.phase != Match.Phase.WAR and arena.phase != Match.Phase.COUNTDOWN:
		if is_local():
			var tip0 := head + Vector2(0, sin(_anim_t * 5.0))
			_overlay.draw_colored_polygon(PackedVector2Array([tip0 + Vector2(-3, -3), tip0 + Vector2(3, -3), tip0]), Color.WHITE)
		return
	# Health pip bar.
	var w := 14.0
	var bar := Rect2(head + Vector2(-w / 2.0, -1), Vector2(w, 2))
	_overlay.draw_rect(bar.grow(1), Color("2b1d2a"))
	var frac := clampf(float(hp) / float(max_hp), 0.0, 1.0)
	var hp_col := Color("8ff0a4") if frac > 0.5 else (Color("ffd84d") if frac > 0.25 else Color("ff5a6e"))
	_overlay.draw_rect(Rect2(bar.position, Vector2(round(w * frac), 2)), hp_col)
	if is_local():
		var tip := head + Vector2(0, -4 + sin(_anim_t * 5.0))
		_overlay.draw_colored_polygon(PackedVector2Array([tip + Vector2(-3, -3), tip + Vector2(3, -3), tip]), Color.WHITE)
	if _revealed:
		# A little eye: someone's nose or x-ray vision has spotted you.
		var eye := head + Vector2(0, -7)
		_overlay.draw_colored_polygon(Transform2D(0, eye) * Iso.ellipse(4.0, 10), Color.WHITE)
		_overlay.draw_circle(eye, 1.2, Color("ff5a6e"))
	if _stun_vis > 0.0:
		for k in 3:
			var a := _anim_t * 6.0 + TAU * k / 3.0
			var p := head + Vector2(cos(a) * 6.0, sin(a) * 2.0 - 3.0)
			_overlay.draw_rect(Rect2(p, Vector2(1, 1)), Color("ffd84d"))
