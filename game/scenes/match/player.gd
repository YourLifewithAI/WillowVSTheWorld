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

enum Action { ATTACK, SPECIAL, DASH, GAG, MELEE }
## How a character can be held by an enemy's gag.
enum Capture { NONE, SWALLOWED, GRABBED }

const SEND_RATE := 30.0
const DASH_SPEED := 430.0
const DASH_TIME := 0.16
const DASH_COOLDOWN := 1.1
const KNOCK_DECAY := 7.0
const TUMBLE_SPEED := 140.0
## Body radius on the floor, used for hit checks.
const BODY_RADIUS := 7.0
## How high a flyer can manage while carrying the remote (below the walls' tops).
const CARRY_HOVER := 6.0
## How long a knockup keeps you in the air (just a visual; the stun does the rest).
const HOP_TIME := 0.5
## After a close-up move, how long before your weapon can fire again.
const MELEE_WEAPON_LOCK := 0.25
## Seconds of standing still before a sneaky cat disappears.
const SNEAK_DELAY := 1.0
## Damage done to furniture by a character slamming into it.
const CRASH_DAMAGE := 18.0
## Seconds of war to fill the gag meter from empty (landing hits speeds it up).
const GAG_CHARGE_TIME := 55.0
## Gag meter gained per point of damage dealt (about 330 damage fills it).
const GAG_PER_DAMAGE := 0.003
## Speed while wading through an enemy litter cloud.
const CLOUD_SLOW := 0.6

var pid := 0
var char_id := "willow"
var data: Dictionary = {}
var team := 0
var display_name := ""
var is_bot := false
## Whatever drives this character on this machine: a person's seat (SeatInput)
## or a bot (BotBrain). Remote players have none.
var brain: Controls
## Which seat on this screen plays this character (-1: a bot or someone elsewhere).
var seat := -1
var arena: Match

# --- Mirrored from the host.
var hp := 100
var max_hp := 100
var is_ko := false
var invuln := 0.0
var carrying := false:
	set(v):
		if v != carrying:
			carrying = v
			_update_mask()
## Held by another player's gag (swallowed by Zoomba, grabbed by the Claw).
var captured_by := 0
var capture_mode: Capture = Capture.NONE
## Forced to dance by Bass.
var dance_t := 0.0
## Seconds left on this character's own gag (Big Bone, Flock Call, Mega Suck...).
var gag_t := 0.0
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
var melee_cd := 0.0
var dash_cd := 0.0
var buff_mult := 1.0
var vanish_t := 0.0
## 0..1; the gag is ready at 1.
var gag_charge := 0.3
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
var _showing_bone := false
var _hop_t := 0.0
var _seen := true
var _hop_h := 0.0
## A pounce in the air: the melee move to swing when it lands.
var _pounce: Dictionary = {}
var _pounce_ambush := false


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
	# Guests on a shared screen are owned by that screen's machine, like bots are by the host.
	set_multiplayer_authority(1 if is_bot else int(info.get("owner", p_id)))


func _ready() -> void:
	collision_layer = 4
	_update_mask()
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


## Can the people looking at this screen see us right now? (Stealthed enemies
## can't be; teammates and see-through hidden characters on a shared sofa can.)
func seen_here() -> bool:
	return _seen


## What this character bumps into: the room's shell (1), furniture (2) and
## walls (8). Flyers pass over furniture and the cutaway walls, but the remote
## weighs them down: carrying it, they fly low and have to use the doors.
## Zoomba drives under furniture, never through walls.
func _update_mask() -> void:
	if data.get("flying", false):
		collision_mask = 1 | WallPanel.LAYER if carrying else 1
	elif data.get("low_profile", false):
		collision_mask = 1 | WallPanel.LAYER
	else:
		collision_mask = 1 | 2 | WallPanel.LAYER


func hover() -> float:
	var h := float(data.get("hover", 0.0))
	if carrying and data.get("flying", false):
		return minf(h, CARRY_HOVER)
	return h


## Played by someone looking at this screen (you, or a guest sharing it).
func is_local() -> bool:
	return seat >= 0


## Arrow, tag and card colour: the seat's colour when several people share the
## screen (so everyone can find themselves), otherwise the team colour. (The
## ring under each character always shows its team.)
func marker_color() -> Color:
	if seat >= 0 and arena.shared_screen():
		return Seats.color(seat)
	return Roster.TEAM_COLORS[team]


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
		"gag": Input.is_action_just_pressed("gag"),
		"interact": Input.is_action_pressed("interact"),
		"interact_pressed": Input.is_action_just_pressed("interact"),
	}


func _owner_tick(delta: float) -> void:
	attack_cd = maxf(0.0, attack_cd - delta)
	melee_cd = maxf(0.0, melee_cd - delta)
	special_cd = maxf(0.0, special_cd - delta)
	dash_cd = maxf(0.0, dash_cd - delta)
	stun = maxf(0.0, stun - delta)
	vanish_t = maxf(0.0, vanish_t - delta)
	_reveal_t = maxf(0.0, _reveal_t - delta)
	_buff_t = maxf(0.0, _buff_t - delta)
	if _buff_t <= 0.0:
		buff_mult = 1.0

	if captured_by != 0:
		_pounce = {}
		_follow_captor()
		return
	if arena.phase == Match.Phase.WAR and not is_ko:
		var was_ready := gag_charge >= 1.0
		gag_charge = minf(1.0, gag_charge + delta / GAG_CHARGE_TIME)
		if gag_charge >= 1.0 and not was_ready and is_local():
			if arena.shared_screen():
				sound("gag_ready")
				Fx.text(arena.level.entities, position + Vector2(0, -sprite_height() - z - 10), "GAG READY!", marker_color())
			else:
				Audio.play("gag_ready")

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
	var cloud := arena.cloud_at(position)
	if cloud and cloud.team != team and not data.get("flying", false):
		speed *= CLOUD_SLOW
	var v := move * speed

	if _dash_t > 0.0:
		_dash_t -= delta
		v = facing * DASH_SPEED
	if data.get("flying", false) and not is_ko and _slam_t <= 0.0 and not is_equal_approx(z, hover()):
		z = move_toward(z, hover(), 60.0 * delta)  # sinking under the remote's weight, or rising again
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
	if not _pounce.is_empty():
		_resolve_pounce()

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
	if inp["interact_pressed"] and melee_cd <= 0.0:
		_do_melee()
	elif (inp["attack"] or auto_fire) and attack_cd <= 0.0:
		_do_attack()
	elif inp["special"] and special_cd <= 0.0:
		_do_special()
	elif inp.get("gag", false) and gag_charge >= 1.0:
		_do_gag()


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
		if f and not f is WallPanel and not _crash_cd.has(f):
			_crash_cd[f] = 0.4
			arena.report_furniture_hit(f, CRASH_DAMAGE, self, -1)


# ==================================================================== stealth

func _update_stealth(delta: float) -> void:
	if moving or dashing or tumbling:
		_still_t = 0.0
	else:
		_still_t += delta
	var can_hide := not carrying and not is_ko and _reveal_t <= 0.0 and arena.phase == Match.Phase.WAR
	hiding = can_hide and data.get("low_profile", false) and arena.level.furniture_at(position) != null
	var sneaking: bool = data.get("sneaky", false) and _still_t >= SNEAK_DELAY
	# Cats vanish inside their own team's litter cloud, even on the move.
	var cloud := arena.cloud_at(position)
	var in_litter: bool = data.get("sneaky", false) and cloud != null and cloud.team == team
	stealthed = can_hide and (sneaking or vanish_t > 0.0 or hiding or in_litter)


## Attacking or getting hit gives your position away for a moment.
func _break_stealth(for_seconds: float) -> void:
	vanish_t = 0.0
	_still_t = 0.0
	_reveal_t = maxf(_reveal_t, for_seconds)
	stealthed = false
	hiding = false


# =================================================================== combat

## Pepper's Big Bone replaces his weapon while it lasts.
func has_bone() -> bool:
	return gag_t > 0.0 and int(data["gag"]["kind"]) == Roster.Gag.BONE


func weapon_spec() -> Dictionary:
	return data["gag"] if has_bone() else data["weapon"]


func _weapon_is_melee() -> bool:
	return has_bone() or int(data["weapon"]["kind"]) == Roster.Weapon.MELEE


func _do_attack() -> void:
	var w := weapon_spec()
	attack_cd = w["cooldown"]
	var ambush := stealthed
	_break_stealth(0.6)
	_play_action.rpc(Action.ATTACK, facing)
	if _weapon_is_melee():
		_hit_arc(w, 2 if has_bone() else 0, ambush)
	else:
		_fire(0, w, ambush)


## The right button (when you aren't carrying the remote): this character's
## own close-up move (see "melee" in Roster).
func _do_melee() -> void:
	var m: Dictionary = data["melee"]
	melee_cd = float(m["cooldown"])
	# Swinging up close ties up your hands for a moment: no firing mid-swipe.
	attack_cd = maxf(attack_cd, MELEE_WEAPON_LOCK)
	var ambush := stealthed
	_break_stealth(0.6)
	_play_action.rpc(Action.MELEE, facing)
	if m.get("effect", "") == "lunge":
		# Hop forward first (a very short dash) and swipe where you land, or
		# as soon as someone is right in front of you.
		_dash_t = float(m["effect_value"]) / DASH_SPEED
		_pounce = m
		_pounce_ambush = ambush
		return
	_hit_arc(m, 3, ambush)


func _resolve_pounce() -> void:
	if stun > 0.0 or is_ko or arena.phase != Match.Phase.WAR:
		_pounce = {}
		return
	if _dash_t > 0.0 and not _enemy_ahead(float(_pounce["range"]) * 0.5, float(_pounce["arc"]) * 0.5):
		return
	_dash_t = 0.0
	_hit_arc(_pounce, 3, _pounce_ambush)
	_pounce = {}


func _enemy_ahead(reach: float, half_arc: float) -> bool:
	for other: Player in arena.players.values():
		if other.team == team or other.is_ko:
			continue
		var off := Iso.to_floor(other.position - position)
		if off.length() <= reach + BODY_RADIUS and (off.length() < 4.0 or absf(rad_to_deg(facing.angle_to(off))) <= half_arc):
			return true
	return false


func _do_gag() -> void:
	var g: Dictionary = data["gag"]
	gag_charge = 0.0
	_break_stealth(0.3)
	_play_action.rpc(Action.GAG, facing)
	match int(g["kind"]):
		Roster.Gag.LITTER:
			_proj_counter += 1
			_spawn_projectile.rpc(2, facing, _proj_counter, false)
		Roster.Gag.BONE:
			arena.log_event("gag %s by %d" % [g["name"], pid])
		Roster.Gag.FLOCK:
			arena.log_event("gag %s by %d" % [g["name"], pid])
			_flock_hits(g)
			buff_mult = g["speed_mult"]
			_buff_t = g["duration"]
		Roster.Gag.SATELLITE:
			arena.report_gag(self, _satellite_target(g))
		Roster.Gag.MEGA_SUCK, Roster.Gag.CLAW_MACHINE, Roster.Gag.DANCE:
			arena.report_gag(self, position)


## Flock Call: everyone in a wide lane ahead gets bowled over at once.
func _flock_hits(g: Dictionary) -> void:
	var side := Vector2(-facing.y, facing.x)
	# The stampede stops at the first wall.
	var lane := float(g["length"])
	var wall := arena.level.wall_between(position, position + Iso.to_screen(facing * lane))
	if not wall.is_empty():
		lane = Iso.fdist(position, wall["point"])
	for other: Player in arena.players.values():
		if other.team == team or other.is_ko:
			continue
		var off := Iso.to_floor(other.position - position)
		var along := off.dot(facing)
		if along > 0.0 and along <= lane and absf(off.dot(side)) <= float(g["width"]):
			arena.report_hit(self, other, 2, facing)
	for item in arena.level.mess_items:
		var off := Iso.to_floor(item.position - position)
		if off.dot(facing) > 0.0 and off.dot(facing) <= lane and absf(off.dot(side)) <= float(g["width"]):
			arena.report_mess_hit(item, g["knock"], facing)


## Satellite Laser: lock onto the nearest enemy we can see, or fire straight ahead.
func _satellite_target(g: Dictionary) -> Vector2:
	var best := position + Iso.to_screen(facing * 90.0)
	var best_d := float(g["reach"])
	for other: Player in arena.players.values():
		if other.team == team or other.is_ko or not arena.is_revealed(other, team):
			continue
		var d := Iso.fdist(other.position, position)
		if d < best_d:
			best = other.position
			best_d = d
	return arena.level.clamp_to_floor(best)


## While swallowed or grabbed, we just go wherever our captor goes.
func _follow_captor() -> void:
	var captor: Player = arena.players.get(captured_by)
	if captor:
		position = captor.position + Vector2(0, 0.5)
		z = captor.z - 14.0 if capture_mode == Capture.GRABBED else 0.0
	velocity = Vector2.ZERO
	knock_vel = Vector2.ZERO
	moving = false
	dashing = false
	tumbling = false
	interacting = false
	stealthed = false
	hiding = false


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
func _hit_arc(w: Dictionary, ability: int, ambush: bool) -> void:
	var reach: float = w["range"]
	# A full circle (Zoomba's spin) must include straight behind, despite rounding.
	var half_arc: float = float(w["arc"]) * 0.5 + 0.01
	var hit_someone := false
	for other: Player in arena.players.values():
		if other.team == team or other.is_ko:
			continue
		var off := Iso.to_floor(other.position - position)
		var d := off.length()
		if d > reach + BODY_RADIUS:
			continue
		if d > 4.0 and absf(rad_to_deg(facing.angle_to(off))) > half_arc:
			continue
		if _walled(position, other.position):
			continue
		hit_someone = true
		arena.report_hit(self, other, ability, off.normalized() if d > 0.1 else facing, ambush)
	# Some close-up moves are made for knocking things over.
	var item_force := float(w["knock"])
	if w.get("effect", "") == "shove_items":
		item_force = maxf(item_force, float(w.get("effect_value", 0.0)))
	for item in arena.level.mess_items:
		var off := Iso.to_floor(item.position - position)
		if off.length() <= reach + 6.0 and (off.length() < 4.0 or absf(rad_to_deg(facing.angle_to(off))) <= half_arc) \
				and not _walled(position, item.position):
			arena.report_mess_hit(item, item_force, off)
	for f in arena.level.furniture:
		if f is WallPanel:
			continue
		var off := Iso.to_floor(f.position - position)
		if f.can_be_damaged() and off.length() <= reach + f.reach() and absf(rad_to_deg(facing.angle_to(off))) <= half_arc \
				and not _walled(position, f.position):
			arena.report_furniture_hit(f, w.get("demolition", 0.0), self, ability)
	# A swing that lands on someone doesn't also dent the wall behind them:
	# walls break when you swing at the wall.
	if not hit_someone:
		_hit_nearest_wall(position, reach, half_arc, float(w.get("demolition", 0.0)), ability)


## Reports every enemy, breakable and piece of furniture within a radius of a point.
func hit_area(center: Vector2, radius: float, ability: int, force: float, demolition: float, ambush: bool) -> void:
	for other: Player in arena.players.values():
		if other.team == team or other.is_ko:
			continue
		var off := Iso.to_floor(other.position - center)
		if off.length() <= radius + BODY_RADIUS and not _walled(center, other.position):
			arena.report_hit(self, other, ability, off.normalized() if off.length() > 0.1 else facing, ambush)
	if force > 0.0:
		for item in arena.level.mess_items:
			var off := Iso.to_floor(item.position - center)
			if off.length() <= radius + 6.0 and not _walled(center, item.position):
				arena.report_mess_hit(item, force, off)
	if demolition > 0.0:
		for f in arena.level.furniture:
			if f is WallPanel:
				continue
			if f.can_be_damaged() and Iso.fdist(center, f.position) <= radius + f.reach() and not _walled(center, f.position):
				arena.report_furniture_hit(f, demolition, self, ability)
		_hit_nearest_wall(center, radius, 180.0, demolition, ability)


## Is there a standing wall between a and b?
func _walled(a: Vector2, b: Vector2) -> bool:
	return not arena.level.wall_between(a, b).is_empty()


## Only the one nearest wall panel (in the swing's cone) takes a hit or a blast,
## so a hole is exactly as big as the panels really broken. Weak hits don't
## bother the host: they'd do nothing to a wall.
func _hit_nearest_wall(center: Vector2, radius: float, half_arc: float, demolition: float, ability: int) -> void:
	if demolition <= 0.0:
		return
	var best: WallPanel = null
	var best_d := INF
	for panel in arena.level.wall_panels:
		if panel.wrecked:
			continue
		var l := panel.line()
		var near := Iso.closest_on_segment(center, l[0], l[1])
		var d := maxf(0.0, Iso.fdist(center, near) - WallPanel.HALF_THICK)
		if d > radius or d >= best_d:
			continue
		var off := Iso.to_floor(near - center)
		if half_arc < 180.0 and off.length() > 4.0 and absf(rad_to_deg(facing.angle_to(off))) > half_arc:
			continue
		best = panel
		best_d = d
	if best and best.can_be_damaged() and demolition >= best.min_hit:
		arena.report_furniture_hit(best, demolition, self, ability)


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
			var w := weapon_spec()
			sound(w.get("swing_sfx", w.get("sfx", "")))
			if _weapon_is_melee():
				_swing = 1.0
				_squash = 0.2
				Fx.swing(fx_parent, position + Vector2(0, -z + 8), dir, float(w["range"]) * 0.8, Color(1, 1, 1, 0.8))
			else:
				_recoil = 1.0
				_squash = 0.1
		Action.MELEE:
			_play_melee(dir)
		Action.DASH:
			_squash = 0.3
			if not stealthed:
				Fx.puff(fx_parent, position, Color(1, 1, 1, 0.8))
				sound("dash", -4.0)
		Action.GAG:
			var g: Dictionary = data["gag"]
			_squash = 0.4
			sound(g.get("sfx", ""))
			match int(g["kind"]):
				Roster.Gag.BONE, Roster.Gag.MEGA_SUCK:
					gag_t = g["duration"]
					if int(g["kind"]) == Roster.Gag.MEGA_SUCK:
						Fx.vortex(fx_parent, position, g["radius"], g["duration"])
				Roster.Gag.FLOCK:
					gag_t = g["duration"]
					Fx.flock(fx_parent, position, dir, g["length"], g["width"])
				Roster.Gag.DANCE:
					Fx.disco(fx_parent, position, g["radius"], g["duration"] + 0.4)
			Fx.text(fx_parent, position + Vector2(0, -sprite_height() - z - 10), String(g["name"]).to_upper() + "!", Color("ffd84d"))
		Action.SPECIAL:
			var sp: Dictionary = data["special"]
			if int(sp["kind"]) == Roster.Special.VANISH:
				Fx.puff(fx_parent, position, Color(0.8, 0.8, 0.9, 0.9))
				sound(sp.get("sfx", ""), -6.0)
				return  # No shout: that would give it away.
			sound(sp.get("sfx", ""))
			match int(sp["kind"]):
				Roster.Special.SLAM:
					_telegraph = sp["windup"]
					Audio.play_later(sp.get("land_sfx", ""), float(sp["windup"]), fx_parent, position)
				Roster.Special.PULL:
					Fx.ring(fx_parent, position, sp["radius"], Color("62f2ff"), true)
				Roster.Special.AURA:
					Fx.ring(fx_parent, position, sp["radius"], Color("62f2ff"), false)
					for k in 5:
						Fx.note(fx_parent, position + Iso.to_screen(Vector2.from_angle(TAU * k / 5.0) * 20.0))
			Fx.text(fx_parent, position + Vector2(0, -sprite_height() - z - 6), String(sp["name"]).to_upper() + "!", Roster.TEAM_COLORS[team].lightened(0.3))


## How each kind of close-up move looks (everyone sees it; the owner already did the hit).
func _play_melee(dir: Vector2) -> void:
	var m: Dictionary = data["melee"]
	var fx_parent := arena.level.entities
	var look := String(m.get("look", "swipe"))
	var at := position + Vector2(0, -z - 6)
	var ahead := at + Iso.to_screen(dir * float(m["range"]) * 0.7)
	var col := Roster.TEAM_COLORS[team].lightened(0.4)
	sound(m.get("sfx", "m_" + look))
	_squash = 0.25
	match look:
		"swipe":  # Willow: the swipe itself lands with the pounce, so show the leap.
			_squash = 0.45
			Fx.slash(fx_parent, at + Iso.to_screen(dir * (float(m["range"]) + float(m.get("effect_value", 0.0)))), dir, Color.WHITE)
		"knead":
			Fx.burst(fx_parent, ahead, Color("ffc2d1"))
			Fx.text(fx_parent, ahead + Vector2(0, -10), "purr", Color("ffc2d1"))
		"chomp":
			Fx.slash(fx_parent, ahead, dir, Color.WHITE)
			Fx.text(fx_parent, ahead + Vector2(0, -8), "CHOMP!", Color.WHITE)
		"peck":
			Fx.burst(fx_parent, ahead, Color("ffd84d"))
		"spin":
			Fx.ring(fx_parent, position, float(m["range"]) + 4.0, Color(1, 1, 1, 0.8), false)
			Fx.ring(fx_parent, position, float(m["range"]) * 0.6, col, false)
		"flip":
			_swing = 1.0
			Fx.swing(fx_parent, at + Vector2(0, 6), dir, float(m["range"]) * 0.9, Color(1, 1, 1, 0.85))
			Fx.text(fx_parent, ahead + Vector2(0, -8), "FLIP!", Color("ffd84d"))
		"yoink":
			Fx.slash(fx_parent, ahead, -dir, Color("ffd84d"))
			Fx.text(fx_parent, ahead + Vector2(0, -8), "YOINK!", Color("ffd84d"))
		"feedback":
			Fx.ring(fx_parent, position + Iso.to_screen(dir * 6.0), float(m["range"]) + 6.0, Color("62f2ff"), false)
			Fx.text(fx_parent, ahead + Vector2(0, -8), "SKREEE!", Color("62f2ff"))
			for k in 3:
				Fx.note(fx_parent, position + Iso.to_screen(dir.rotated(-0.6 + 0.6 * k) * 16.0))
		_:
			Fx.slash(fx_parent, ahead, dir, Color.WHITE)


# ================================================= events from the host

## `hop`: how high a "knockup" close-up move pops you into the air (px).
func on_damaged(new_hp: int, knock: Vector2, stun_time: float, ambushed: bool, hop: float = 0.0) -> void:
	if hop > 0.0:
		_hop_t = HOP_TIME
		_hop_h = hop
	sound("hit_big" if hp - new_hp >= 20 else "hit")
	hp = new_hp
	_flash = 0.15
	_squash = 0.3
	if stun_time > 0.0:
		_stun_vis = stun_time
	if data.get("flips", false) and stun_time >= 1.4:
		_flip_t = stun_time
		Fx.text(arena.level.entities, position + Vector2(0, -18 - z), "FLIPPED!", Color.WHITE)
		sound("flip")
	Fx.burst(arena.level.entities, position + Vector2(0, -8 - z), Color.WHITE)
	if ambushed:
		Fx.text(arena.level.entities, position + Vector2(0, -26 - z), "AMBUSH!", Color("ff5a6e"))
		sound("ambush")
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
		sound("ko_" + String(data.get("voice", "cat")), 0.0, float(data.get("voice_pitch", 1.0)))


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
	sound("respawn", -3.0)


func start_capture(by_pid: int, mode: int) -> void:
	captured_by = by_pid
	capture_mode = mode as Capture
	if is_multiplayer_authority():
		_dash_t = 0.0
		_slam_t = 0.0
		_break_stealth(0.5)
	var what := "GULP!" if mode == Capture.SWALLOWED else "GOTCHA!"
	Fx.text(arena.level.entities, position + Vector2(0, -20 - z), what, Color.WHITE)
	sound("gulp" if mode == Capture.SWALLOWED else "grab")


func end_capture(knock: Vector2) -> void:
	sound("spit" if capture_mode == Capture.SWALLOWED else "thud")
	captured_by = 0
	capture_mode = Capture.NONE
	if is_multiplayer_authority():
		z = hover()
		knock_vel = knock
	Fx.puff(arena.level.entities, position, Color(0.85, 0.82, 0.78))


func start_dance(duration: float) -> void:
	dance_t = duration
	if is_multiplayer_authority():
		stun = maxf(stun, duration)
		_dash_t = 0.0
		_break_stealth(0.5)


## Zoomba's Mega Suck tugging us in (only the owner moves the body).
func apply_pull(pull: Vector2) -> void:
	if is_multiplayer_authority() and captured_by == 0:
		knock_vel = knock_vel * 0.5 + pull


## Healed by the host (a close-up move that drains health).
func heal(new_hp: int) -> void:
	if new_hp > hp:
		Fx.text(arena.level.entities, position + Vector2(0, -sprite_height() - z - 4), "+%d" % (new_hp - hp), Color("8ff0a4"))
	hp = new_hp


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
	captured_by = 0
	capture_mode = Capture.NONE
	dance_t = 0.0
	gag_t = 0.0
	if is_multiplayer_authority():
		knock_vel = Vector2.ZERO
		stun = 0.0
		vanish_t = 0.0
		_slam_t = 0.0
		z = hover()


## A sound from this character, panned to where it is on screen.
func sound(sound_name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if arena and arena.level:
		Audio.play_at(sound_name, arena.level.entities, position, volume_db, pitch)


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
	gag_t = maxf(0.0, gag_t - delta)
	dance_t = maxf(0.0, dance_t - delta)
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
		if dance_t > 0.0:
			# Bass made them do it.
			bob = -absf(sin(_anim_t * 10.0)) * 3.0
			_sprite.rotation = sin(_anim_t * 10.0) * 0.35
			_face_left = sin(_anim_t * 5.0) < 0.0
			_sprite.flip_h = _face_left
		elif flying:
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
	if _hop_t > 0.0:
		_hop_t = maxf(0.0, _hop_t - delta)
		bob -= sin(_hop_t / HOP_TIME * PI) * _hop_h
	_visual.position = Vector2(0, round(-z + bob))
	_update_weapon()

	# How visible are we to whoever is looking at this screen?
	var target_alpha := 1.0
	_revealed = false
	if capture_mode == Capture.SWALLOWED:
		target_alpha = 0.0  # Inside the dust bin.
	elif stealthed and not is_ko:
		var teams := arena.screen_teams()
		if teams.size() > 1:
			# Both teams share this screen, so nothing can be hidden from half the
			# sofa: everyone sees hidden characters the way teammates do (bots and
			# players on other machines still can't see them at all).
			target_alpha = 0.4
			if arena.is_revealed(self, 1 - team):
				target_alpha = 0.85
				_revealed = true
		elif teams[0] == team:
			target_alpha = 0.4
		elif arena.is_revealed(self, teams[0]):
			target_alpha = 0.85
			_revealed = true
		else:
			target_alpha = 0.08 if moving and not hiding else 0.0
	modulate.a = move_toward(modulate.a, target_alpha, delta * 5.0)
	_seen = target_alpha >= 0.3

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
	var w := weapon_spec()
	if has_bone() != _showing_bone:
		_showing_bone = has_bone()
		var tex := Roster.texture(w["sprite"])
		_weapon.texture = tex
		_weapon.centered = not _weapon_is_melee()
		if _showing_bone:
			_weapon.offset = Vector2(-floor(tex.get_width() / 2.0), -tex.get_height() + 2)
		elif _weapon_is_melee():
			_weapon.offset = Vector2(-floor(tex.get_width() / 2.0), 0)
		else:
			_weapon.offset = Vector2.ZERO
	_weapon.visible = not is_ko and _flip_t <= 0.0 and captured_by == 0
	var hold: Vector2 = w["hold"]
	var side := -1.0 if _face_left else 1.0
	_weapon.flip_h = _face_left
	if has_bone():
		# A bat-swing: wound up over the shoulder, then all the way through.
		_weapon.position = Vector2(4.0 * side, hold.y - 4.0)
		_weapon.rotation = side * (-0.5 + sin(_swing * PI) * 2.2)
	elif _weapon_is_melee():
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
	# Team ring (brighter, in the seat's colour, for people on this screen; red when revealed).
	var ring := Iso.ellipse(9.0 if is_local() else 8.0, 20)
	ring.append(ring[0])
	var col: Color = Color("ff5a6e") if _revealed else Roster.TEAM_COLORS[team]
	col.a = 0.95 if is_local() or _revealed else 0.55
	draw_polyline(ring, col, 2.0 if is_local() and arena.shared_screen() else 1.0)
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


## The bobbing arrow over your own character; with several people on one
## screen, in the seat's colour with "P2" etc. next to it.
func _draw_you_marker(tip: Vector2) -> void:
	var shared := arena.shared_screen()
	var col := marker_color() if shared else Color.WHITE
	_overlay.draw_colored_polygon(PackedVector2Array([tip + Vector2(-3, -3), tip + Vector2(3, -3), tip]), col)
	if shared:
		var label := Seats.tag(seat)
		var font := ThemeDB.fallback_font
		var at := tip + Vector2(-font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 7).x / 2.0, -5)
		_overlay.draw_string_outline(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, 3, Color("2b1d2a"))
		_overlay.draw_string(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, col)


func _draw_overlay() -> void:
	if is_ko:
		var zz := Vector2(4, -14 - sin(_anim_t * 3.0) * 2.0)
		_overlay.draw_string(ThemeDB.fallback_font, zz, "z", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color.WHITE)
		_overlay.draw_string(ThemeDB.fallback_font, zz + Vector2(4, -5), "z", HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color.WHITE)
		return
	var head := Vector2(0, round(-z) - sprite_height() - 3)
	if arena.phase != Match.Phase.WAR and arena.phase != Match.Phase.COUNTDOWN:
		if is_local():
			_draw_you_marker(head + Vector2(0, sin(_anim_t * 5.0)))
		return
	# Health pip bar.
	var w := 14.0
	var bar := Rect2(head + Vector2(-w / 2.0, -1), Vector2(w, 2))
	_overlay.draw_rect(bar.grow(1), Color("2b1d2a"))
	var frac := clampf(float(hp) / float(max_hp), 0.0, 1.0)
	var hp_col := Color("8ff0a4") if frac > 0.5 else (Color("ffd84d") if frac > 0.25 else Color("ff5a6e"))
	_overlay.draw_rect(Rect2(bar.position, Vector2(round(w * frac), 2)), hp_col)
	if is_local():
		_draw_you_marker(head + Vector2(0, -4 + sin(_anim_t * 5.0)))
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
