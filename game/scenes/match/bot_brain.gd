class_name BotBrain
extends Controls
## A simple bot that produces the same input a player would.
## During the war it grabs, escorts, or chases the remote. During cleanup it
## helps fix whatever is closest (and not already being handled).

var me: Player
var arena: Match

var _detour := Vector2.ZERO
var _detour_t := 0.0
var _stuck_t := 0.0
var _last_pos := Vector2.ZERO
var _hesitate := 0.0
var _wander := Vector2.ZERO
var _wander_t := 0.0
var _nap_t := randf_range(2.0, 5.0)
var _path := PackedVector2Array()
var _path_goal := Vector2.INF
var _path_t := 0.0


func _init(player: Player, match_node: Match) -> void:
	me = player
	arena = match_node
	_last_pos = player.position


func think() -> Dictionary:
	var inp := {"move": Vector2.ZERO, "attack": false, "special": false, "dash": false,
		"gag": false, "interact": false, "interact_pressed": false}
	if me.is_ko:
		return inp
	var delta := me.get_physics_process_delta_time()
	_hesitate = maxf(0.0, _hesitate - delta)
	match arena.phase:
		Match.Phase.WAR:
			_war(inp, delta)
		Match.Phase.CLEANUP:
			_cleanup(inp, delta)
	return inp


# ==================================================================== war

func _war(inp: Dictionary, delta: float) -> void:
	var r := arena.remote
	var foe := _nearest_enemy(me.position)
	var goal := r.position
	if me.carrying:
		goal = arena.level.bases[me.team].position
		# About to get caught? Pass to a teammate who is closer to home.
		if foe and Iso.fdist(foe.position, me.position) < 30.0:
			var mate := _open_teammate()
			if mate:
				me.facing = Iso.to_floor(mate.position - me.position).normalized()
				inp["interact_pressed"] = true
	elif r.state == TVRemote.State.CARRIED:
		var carrier := r.carrier()
		if carrier and carrier.team != me.team:
			goal = carrier.position
		elif carrier:
			# Escort: body-guard the carrier, peel off to hit anyone close to them.
			var threat := _nearest_enemy(carrier.position)
			if threat and Iso.fdist(threat.position, carrier.position) < 90.0:
				goal = threat.position
			else:
				goal = carrier.position + Iso.to_screen(Vector2(-24, 0).rotated(float(me.pid % 5)))
	elif not _is_runner() and foe:
		goal = foe.position

	inp["move"] = _steer(goal, delta)

	if foe == null or _hesitate > 0.0:
		return
	var dist := Iso.fdist(foe.position, me.position)
	var to_foe := Iso.to_floor(foe.position - me.position).normalized()
	var w: Dictionary = me.data["weapon"]
	var kind := int(w["kind"])
	if not me.carrying and _in_weapon_range(w, dist):
		# Turn to face them, then fire (with a little human-ish delay).
		inp["move"] = to_foe * (0.3 if kind == Roster.Weapon.MELEE else 0.25)
		if absf(rad_to_deg(me.facing.angle_to(to_foe))) < 30.0 and me.attack_cd <= 0.0:
			inp["attack"] = true
			inp["attack_held"] = true
			if float(w["cooldown"]) >= 0.2:
				_hesitate = randf_range(0.05, 0.25)
	# Right up close: use this character's own close-up move.
	var m: Dictionary = me.data["melee"]
	var reach := float(m["range"]) + (float(m["effect_value"]) if m.get("effect", "") == "lunge" else 0.0)
	if not me.carrying and me.melee_cd <= 0.0 and dist <= reach + 4.0 \
			and (float(m["arc"]) >= 360.0 or absf(rad_to_deg(me.facing.angle_to(to_foe))) < float(m["arc"]) * 0.5) \
			and _melee_makes_sense(m, foe):
		inp["interact_pressed"] = true
		_hesitate = randf_range(0.05, 0.2)
	elif not me.carrying and me.special_cd <= 0.0 and _special_makes_sense(foe, dist, to_foe):
		inp["special"] = true
		_hesitate = 0.3
	elif not me.carrying and me.gag_charge >= 1.0 and _gag_makes_sense(foe, dist, to_foe):
		inp["gag"] = true
		_hesitate = 0.4
	if dist > 140.0 and me.dash_cd <= 0.0 and randf() < 0.01:
		inp["dash"] = true


## A teammate nearer our base than us, not too far away, to throw to.
func _open_teammate() -> Player:
	var base := arena.level.bases[me.team].position
	var my_d := Iso.fdist(me.position, base)
	for p: Player in arena.players.values():
		if p == me or p.team != me.team or p.is_ko:
			continue
		var d := Iso.fdist(p.position, me.position)
		if d > 30.0 and d < 110.0 and Iso.fdist(p.position, base) < my_d:
			return p
	return null


## The two teammates nearest the remote go for it; everyone else hunts.
func _is_runner() -> bool:
	var mine := Iso.fdist(me.position, arena.remote.position)
	var closer := 0
	for p: Player in arena.players.values():
		if p != me and p.team == me.team and not p.is_ko and Iso.fdist(p.position, arena.remote.position) < mine:
			closer += 1
	return closer < 2


func _in_weapon_range(w: Dictionary, dist: float) -> bool:
	match int(w["kind"]):
		Roster.Weapon.MELEE:
			return dist <= float(w["range"]) + 6.0
		Roster.Weapon.SHOT:
			return dist <= float(w["range"]) * 0.85
		Roster.Weapon.LOB:
			# Shells land at a fixed distance, so stand about that far away.
			var land := float(w["range"])
			var blast := float(w["explode_radius"])
			var lo := land * 0.55 if land > 30.0 else 0.0
			return dist >= lo and dist <= land + blast * 0.7
	return false


func _special_makes_sense(foe: Player, dist: float, to_foe: Vector2) -> bool:
	var sp: Dictionary = me.data["special"]
	var aimed := absf(rad_to_deg(me.facing.angle_to(to_foe))) < 20.0
	match int(sp["kind"]):
		Roster.Special.VANISH:
			return not me.stealthed and dist < 170.0 and dist > 50.0
		Roster.Special.SLAM:
			return dist < float(sp["radius"]) * 0.7
		Roster.Special.PROJECTILE:
			return aimed and dist < float(sp["range"]) * 0.8
		Roster.Special.PULL:
			return dist < float(sp["radius"]) * 0.8 or (arena.remote.is_free() and Iso.fdist(arena.remote.position, me.position) < float(sp["radius"]))
		Roster.Special.AURA:
			return me.hp < me.max_hp * 0.7 or dist < 60.0
	return false


## Some close-up moves are for special moments rather than every brawl.
func _melee_makes_sense(m: Dictionary, foe: Player) -> bool:
	var foe_has_remote := foe.carrying
	match String(m.get("effect", "")):
		"steal":
			return foe_has_remote
		"lunge":
			return foe_has_remote or me.stealthed or randf() < 0.3
		"shove_items":
			return foe_has_remote or randf() < 0.1
	return true


func _gag_makes_sense(foe: Player, dist: float, to_foe: Vector2) -> bool:
	var g: Dictionary = me.data["gag"]
	var aimed := absf(rad_to_deg(me.facing.angle_to(to_foe))) < 15.0
	match int(g["kind"]):
		Roster.Gag.LITTER:
			return aimed and dist > 60.0 and dist < float(g["range"]) + 20.0
		Roster.Gag.BONE:
			return dist < 70.0
		Roster.Gag.FLOCK:
			return aimed and dist < float(g["length"]) * 0.8
		Roster.Gag.MEGA_SUCK:
			return dist < float(g["radius"]) * 0.6
		Roster.Gag.SATELLITE:
			return dist < float(g["reach"])
		Roster.Gag.CLAW_MACHINE:
			return dist < float(g["radius"]) * 0.6
		Roster.Gag.DANCE:
			return dist < float(g["radius"]) * 0.6
	return false


func _nearest_enemy(from: Vector2) -> Player:
	var best: Player = null
	var best_d := INF
	for p: Player in arena.players.values():
		# Bots can't target what their team can't see.
		if p.team == me.team or p.is_ko or not arena.is_revealed(p, me.team):
			continue
		var d := Iso.fdist(p.position, from)
		if d < best_d:
			best = p
			best_d = d
	return best


# ================================================================ cleanup

func _cleanup(inp: Dictionary, delta: float) -> void:
	# Cats "supervise": every few seconds they stop helping for a nap.
	if me.data.get("clumsy", false):
		_nap_t -= delta
		if _nap_t < 0.0:
			if _nap_t < -2.5:
				_nap_t = randf_range(3.0, 6.0)
			return
	var r := arena.remote
	if me.carrying:
		inp["move"] = _steer(arena.level.home.position, delta)
		return
	var goal_pos := Vector2.INF
	var goal_radius := 12.0
	if r.is_free() and r.state != TVRemote.State.HOME and _closest_to(r.position):
		goal_pos = r.position
		goal_radius = 0.0
	else:
		var best_score := INF
		for f in arena.level.furniture:
			if not f.wrecked:
				continue
			var fd := Iso.fdist(f.position, me.position)
			var f_busy: bool = f.helpers >= f.required_lift() and fd > Match.FIX_RADIUS + f.reach()
			var f_score := fd - 60.0 + (120.0 if f_busy else 0.0)
			if f_score < best_score:
				best_score = f_score
				goal_pos = f.position
				goal_radius = Match.FIX_RADIUS * 0.6 + f.reach()
		for item in arena.level.mess_items:
			if not item.knocked:
				continue
			var d := Iso.fdist(item.position, me.position)
			var busy: bool = item.helpers >= item.required_lift() and Iso.fdist(item.position, me.position) > Match.FIX_RADIUS
			var score := d + (120.0 if busy else 0.0) - (40.0 if item.heavy else 0.0)
			if score < best_score:
				best_score = score
				goal_pos = item.position
				goal_radius = Match.FIX_RADIUS * 0.6
		for d: Debris in arena.debris.values():
			var dd := Iso.fdist(d.position, me.position) + 30.0
			if dd < best_score:
				best_score = dd
				goal_pos = d.position
				goal_radius = Match.DEBRIS_RADIUS - 3.0
	if goal_pos == Vector2.INF:
		# Nothing left: mill about the rug looking innocent.
		_wander_t -= delta
		if _wander_t <= 0.0:
			_wander_t = randf_range(1.0, 2.5)
			_wander = arena.level.home.position + Iso.to_screen(Vector2.from_angle(randf() * TAU) * randf_range(20, 60))
		inp["move"] = _steer(_wander, delta) * 0.5
		return
	if Iso.fdist(goal_pos, me.position) <= goal_radius:
		inp["interact"] = true
		inp["move"] = Vector2.ZERO
	else:
		inp["move"] = _steer(goal_pos, delta)


func _closest_to(pos: Vector2) -> bool:
	var mine := Iso.fdist(me.position, pos)
	for p: Player in arena.players.values():
		if p != me and not p.is_ko and Iso.fdist(p.position, pos) < mine:
			return false
	return true


# =============================================================== movement

## Heads for `goal` along the navigation mesh (flyers go straight), feeling
## around anything in the way. Returns a floor-space direction.
func _steer(goal: Vector2, delta: float) -> Vector2:
	if Iso.fdist(goal, me.position) < 3.0:
		return Vector2.ZERO
	var waypoint := goal
	if not me.data.get("flying", false):
		_path_t -= delta
		if _path_t <= 0.0 or Iso.fdist(goal, _path_goal) > 12.0:
			_path_t = 0.3
			_path_goal = goal
			_path = arena.level.find_path(me.position, goal)
		while _path.size() > 1 and Iso.fdist(_path[0], me.position) < 6.0:
			_path.remove_at(0)
		if not _path.is_empty():
			waypoint = _path[0]
	var to := Iso.to_floor(waypoint - me.position)
	if to.length() < 0.5:
		to = Iso.to_floor(goal - me.position)
	var dir := to.normalized()

	# Stuck on something? Pick a sideways detour for a moment.
	if me.position.distance_to(_last_pos) < 0.4:
		_stuck_t += delta
	else:
		_stuck_t = 0.0
	_last_pos = me.position
	if _stuck_t > 0.25 and _detour_t <= 0.0:
		_detour = dir.rotated(PI * 0.5 * (1.0 if randf() < 0.5 else -1.0))
		_detour_t = 0.45
		_stuck_t = 0.0
	if _detour_t > 0.0:
		_detour_t -= delta
		return _detour

	for angle in [0.0, 0.6, -0.6, 1.2, -1.2, 1.8, -1.8]:
		var try_dir := dir.rotated(angle)
		if not me.test_move(me.global_transform, Iso.to_screen(try_dir * 12.0)):
			return try_dir
	return dir
