class_name BotBrain
extends Controls
## A simple bot that produces the same input a player would.
## During the war it grabs, escorts, or chases the remote. During cleanup it
## plays its character's role (see _cleanup).

var me: Player
var arena: Match

var _detour := Vector2.ZERO
var _detour_t := 0.0
var _stuck_t := 0.0
var _last_pos := Vector2.ZERO
var _hesitate := 0.0
var _wander := Vector2.ZERO
var _wander_t := 0.0
var _path := PackedVector2Array()
var _path_goal := Vector2.INF
var _path_t := 0.0
## Knocking through a wall on purpose (heavy hitters only, see _consider_breach).
var _breach: WallPanel = null
var _breach_t := 0.0
var _breach_hp := 0
var _breach_check := 1.0
var _breach_cd := randf_range(8.0, 20.0)


func _init(player: Player, match_node: Match) -> void:
	me = player
	arena = match_node
	if Net.options.has("generic_bots"):
		var n := String(Net.options["generic_bots"])
		_generic = n == "true" or (player.pid < 0 and player.pid >= -int(n))
		if _generic:
			print("[bot] %s ignores its specialty (testing)" % player.char_id)
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

	# Something good on the floor nearby? Grab it on the way (unless someone's on us).
	var grab := _pickup_nearby(90.0)
	if grab and not me.carrying and (foe == null or Iso.fdist(foe.position, me.position) > 50.0):
		goal = grab.position
	inp["move"] = _steer(goal, delta)
	if _breaching(inp, goal, foe, delta):
		return

	if foe == null or _hesitate > 0.0:
		return
	var dist := Iso.fdist(foe.position, me.position)
	var to_foe := Iso.to_floor(foe.position - me.position).normalized()
	var w: Dictionary = me.data["weapon"] if me.has_bone() else me.weapon_spec()
	var kind := int(w["kind"])
	# Behind a wall? Keep moving instead of firing into the drywall.
	var line_clear := arena.level.wall_between(me.position, foe.position).is_empty()
	var weapon_clear: bool = line_clear or w.get("through_walls", false) \
		or (kind == Roster.Weapon.LOB and _lob_clear(foe))
	if not me.carrying and weapon_clear and _in_weapon_range(w, dist):
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
	if not me.carrying and line_clear and me.melee_cd <= 0.0 and dist <= reach + 4.0 \
			and (float(m["arc"]) >= 360.0 or absf(rad_to_deg(me.facing.angle_to(to_foe))) < float(m["arc"]) * 0.5) \
			and _melee_makes_sense(m, foe):
		inp["interact_pressed"] = true
		_hesitate = randf_range(0.05, 0.2)
	elif not me.carrying and me.special_cd <= 0.0 and (line_clear or _special_needs_no_line(me.data["special"])) \
			and _special_makes_sense(foe, dist, to_foe):
		inp["special"] = true
		_hesitate = 0.3
	elif not me.carrying and me.gag_charge >= 1.0 and (line_clear or _gag_needs_no_line(me.data["gag"])) \
			and _gag_makes_sense(foe, dist, to_foe):
		inp["gag"] = true
		_hesitate = 0.4
	if dist > 140.0 and me.dash_cd <= 0.0 and randf() < 0.01:
		inp["dash"] = true


## Specials and gags that don't travel across the floor to reach someone:
## they work through walls (sound, the satellite) or don't aim at anyone.
static func _special_needs_no_line(sp: Dictionary) -> bool:
	return int(sp["kind"]) in [Roster.Special.VANISH, Roster.Special.AURA]


static func _gag_needs_no_line(g: Dictionary) -> bool:
	return int(g["kind"]) in [Roster.Gag.BONE, Roster.Gag.SATELLITE, Roster.Gag.DANCE]


## A lobbed shell crosses walls high up, but not near either end of its flight.
func _lob_clear(foe: Player) -> bool:
	var level := arena.level
	var dir := Iso.to_screen(Iso.to_floor(foe.position - me.position).normalized() * 34.0)
	return level.wall_between(me.position, me.position + dir).is_empty() \
		and level.wall_between(foe.position - dir, foe.position).is_empty()


# ============================================================ breaching

## Which input knocks through a wall for this bot (demolition 50 and up), or "".
## Flyers go over the walls anyway; Biscuit uses her Belly Flop rather than
## lining up a bazooka shell.
func _breach_input() -> String:
	if me.data.get("flying", false):
		return ""
	var w := me.weapon_spec()
	if int(w["kind"]) == Roster.Weapon.MELEE and float(w.get("demolition", 0.0)) >= WallPanel.MIN_HIT:
		return "attack"
	if float(me.data["special"].get("demolition", 0.0)) >= WallPanel.MIN_HIT:
		return "special"
	return ""


## Once a second: is the way round much longer than straight through a wall?
## Then knock through it (at most twice per team per war, never late in the
## war, never in a fight, and not too often per bot).
func _consider_breach(goal: Vector2, foe: Player) -> void:
	var tool := _breach_input()
	if tool == "" or me.carrying or arena.time_left < 30.0 or _breach_cd > 0.0:
		return
	if arena.breaches[me.team] >= Match.MAX_BREACHES:
		return
	if foe and Iso.fdist(foe.position, me.position) < 60.0:
		return
	var straight := Iso.fdist(me.position, goal)
	if straight < 60.0:
		return
	var path := arena.level.find_path(me.position, goal)
	var walked := 0.0
	var at := me.position
	for p in path:
		walked += Iso.fdist(at, p)
		at = p
	if walked < straight * 1.4:
		return
	var ahead := me.position + Iso.to_screen(Iso.to_floor(goal - me.position).normalized() * 90.0)
	var hit := arena.level.wall_between(me.position, ahead)
	if hit.is_empty() or not (hit["panel"] as WallPanel).can_be_damaged():
		return
	_breach = hit["panel"]
	_breach_t = 6.0
	_breach_hp = me.hp
	_breach_cd = 25.0


## Carrying out a breach: walk up to the wall, face it, and hit it until it
## gives (or give up after 6 s, or if we're getting hurt, or the remote needs us).
func _breaching(inp: Dictionary, goal: Vector2, foe: Player, delta: float) -> bool:
	_breach_cd -= delta
	if _breach == null:
		_breach_check -= delta
		if _breach_check <= 0.0:
			_breach_check = 1.0
			_consider_breach(goal, foe)
		if _breach == null:
			return false
	_breach_t -= delta
	var r := arena.remote
	var needed := r.state == TVRemote.State.CARRIED and r.carrier() and r.carrier().team == me.team
	if _breach.wrecked or _breach_t <= 0.0 or me.hp < _breach_hp - 20 or me.carrying or needed:
		_breach = null
		return false
	var l := _breach.line()
	var near := Iso.closest_on_segment(me.position, l[0], l[1])
	var to_wall := Iso.to_floor(near - me.position)
	var tool := _breach_input()
	var reach := 20.0 if tool == "attack" or int(me.data["special"]["kind"]) == Roster.Special.SLAM else 60.0
	if to_wall.length() > reach:
		inp["move"] = _steer(near, delta)
		return true
	inp["move"] = to_wall.normalized() * 0.2
	if absf(rad_to_deg(me.facing.angle_to(to_wall))) < 25.0:
		if tool == "attack" and me.attack_cd <= 0.0:
			inp["attack"] = true
		elif tool == "special" and me.special_cd <= 0.0:
			inp["special"] = true
	return true


## A teammate nearer our base than us, not too far away, to throw to.
func _open_teammate() -> Player:
	var base := arena.level.bases[me.team].position
	var my_d := Iso.fdist(me.position, base)
	for p: Player in arena.players.values():
		if p == me or p.team != me.team or p.is_ko:
			continue
		var d := Iso.fdist(p.position, me.position)
		if d > 30.0 and d < 110.0 and Iso.fdist(p.position, base) < my_d \
				and arena.level.wall_between(me.position, p.position).is_empty():
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
		# Someone behind a wall is effectively further away.
		if not arena.level.wall_between(from, p.position).is_empty():
			d += 60.0
		if d < best_d:
			best = p
			best_d = d
	return best


# ================================================================ cleanup

## Cleanup: each bot plays its own role (see Chores). It picks the job worth
## the most tidiness per second of its time: its own chore counts four times
## over, a heavy or high job with one helper already waiting is worth joining,
## and a job another bot is already on is worth less. Zoomba and Willow drive
## through their piles, Pepper runs into knocked-over things (and carries the
## strays home), Bass THUMPs where the stains are thickest, and everyone else
## holds interact at the job.
const LOOK_AROUND := Vector2(1.2, 2.0)
const CLAIM_PATIENCE := 3.0
const BOT_PACE := 0.95

var _job = null  # (untyped: floor mess may be freed under it)
var _job_progress := -1.0
var _job_stalled := 0.0
var _job_closest := INF
var _carry_t := 0.0
var _replan_t := 0.0
var _look_t := 0.0
var _skip: Dictionary = {}  # jobs this bot gave up on -> seconds before it tries again
## Testing: bots that ignore what they're good at and just tidy whatever's best
## for anyone (to measure how much playing to your strengths matters).
var _generic := false


func _cleanup(inp: Dictionary, delta: float) -> void:
	var r := arena.remote
	if me.carrying:
		inp["move"] = _steer(arena.level.home.position, delta) * BOT_PACE
		return
	var held := arena.carried_by(me)
	if held:
		# Home (or as close as anyone gets); he drops it in place once he's there.
		# Stuck for too long? Put it down and leave it for someone else.
		_carry_t += delta
		if _carry_t > 8.0:
			inp["interact"] = true
			_skip[held] = 10.0
			_carry_t = 0.0
			return
		inp["move"] = _steer(arena.level.walkable(held.home), delta) * BOT_PACE
		return
	_carry_t = 0.0
	# A turbo tool for my chore (or skates) nearby: worth the detour.
	var grab := _pickup_nearby(140.0)
	if grab:
		inp["move"] = _steer(grab.position, delta) * BOT_PACE
		return
	for job in _skip.keys():  # (some may be freed by now)
		_skip[job] -= delta
		if _skip[job] <= 0.0:
			_skip.erase(job)
	if _look_t > 0.0:
		_look_t -= delta
		return
	if r.is_free() and r.state != TVRemote.State.HOME and _closest_to(r.position):
		_set_job(null)
		inp["move"] = _steer(r.position, delta) * BOT_PACE
		return
	# Done with the last job (or it's done without us)? Look around, then pick another.
	if typeof(_job) == TYPE_OBJECT and not arena.is_open(_job):
		_set_job(null)
		_look_t = randf_range(0.2, 0.4) if arena.has_owner_move(me) else randf_range(LOOK_AROUND.x, LOOK_AROUND.y)
		if randf() < 0.05:
			_look_t += 1.0  # a good stretch
		return
	_replan_t -= delta
	if _job == null or _replan_t <= 0.0:
		_replan_t = 0.5
		var pick := _pick_job()
		if pick != _job:
			_set_job(pick)
	if _job == null:
		# Nothing left: mill about the rug looking innocent.
		_wander_t -= delta
		if _wander_t <= 0.0:
			_wander_t = randf_range(1.0, 2.5)
			_wander = arena.level.home.position + Iso.to_screen(Vector2.from_angle(randf() * TAU) * randf_range(20, 60))
		inp["move"] = _steer(_wander, delta) * 0.5
		return
	_work_on(inp, delta)


func _set_job(job) -> void:
	if typeof(_job) == TYPE_OBJECT and arena.claims.get(_job) == me.pid:
		arena.claims.erase(_job)
	_job = job
	_job_progress = -1.0
	_job_stalled = 0.0
	_job_closest = INF
	me.focus_job = job
	if job:
		arena.claims[job] = me.pid


func _work_on(inp: Dictionary, delta: float) -> void:
	var c := arena.chore_of(_job)
	var pos: Vector2 = (_job as Node2D).position
	var own_move := arena.has_owner_move(me) and c == arena.my_chore(me) and not _generic
	if own_move:
		# Not getting any closer (it's somewhere awkward)? Leave it for someone else.
		var dist := Iso.fdist(pos, me.position)
		if dist < _job_closest - 1.0:
			_job_closest = dist
			_job_stalled = 0.0
		else:
			_job_stalled += delta
			if _job_stalled >= 2.0:
				_skip[_job] = 6.0
				_set_job(null)
				return
	if own_move and c != Chores.Chore.STAIN:
		# Zoomba, Willow, Pepper: just run through it.
		inp["move"] = _steer(pos, delta) * BOT_PACE
		return
	if own_move:
		# Bass: THUMP once there are stains in range.
		if Iso.fdist(pos, me.position) <= Chores.THUMP_RADIUS * 0.6:
			inp["interact"] = true
		else:
			inp["move"] = _steer(pos, delta) * BOT_PACE
		return
	var wall: Object = arena.level.wall_between(me.position, pos).get("panel")
	if not arena.in_reach(me, _job) or (wall != null and wall != _job):
		inp["move"] = _steer(pos, delta) * BOT_PACE
		_job_stalled = 0.0
		return
	inp["interact"] = true
	# Waiting on a second pair of hands (or stuck) for too long? Try something else.
	var progress := arena.progress_of(_job)
	if progress > _job_progress + 0.001:
		_job_progress = progress
		_job_stalled = 0.0
	else:
		_job_stalled += delta
		if _job_stalled >= CLAIM_PATIENCE:
			_skip[_job] = 4.0
			_set_job(null)


## The job worth the most tidiness per second of this bot's time.
func _pick_job() -> Object:
	var scored: Array = []
	var speed := maxf(float(me.data["speed"]), 20.0)
	var mine := arena.my_chore(me) if not _generic else Chores.Chore.NONE
	var own_move := arena.has_owner_move(me) and not _generic
	var here := arena.level.room_at(me.position)
	var jobs := arena.open_jobs()
	for job in jobs:
		if _skip.has(job):
			continue
		var c := arena.chore_of(job)
		var pos: Vector2 = (job as Node2D).position
		var travel := Iso.fdist(pos, me.position) / speed
		if arena.level.room_at(pos) != here:
			travel += 3.0 * Match.TILE / speed
		var own := c == mine
		var work := arena.time_of(job) * (1.0 - arena.progress_of(job)) / Chores.rate(own, c, arena.chore_owners)
		var value := arena.weight_of(job)
		if own and own_move:
			work = 0.1
			if c == Chores.Chore.FLOOR or c == Chores.Chore.CLUTTER or c == Chores.Chore.STAIN:
				# Worth more where they're thick on the ground.
				var reach := Chores.THUMP_RADIUS if c == Chores.Chore.STAIN else 30.0
				for other: Debris in arena.debris.values():
					if other != job and other.chore == c and Iso.fdist(other.position, pos) <= reach:
						value += other.weight
				work = 0.4 if c == Chores.Chore.STAIN else 0.1
			elif job is MessItem and job.stray():
				work = Iso.fdist(job.position, job.home) / speed
		var score := value / (travel + work + 0.6)
		if own:
			score *= 4.0
		var claimant: int = arena.claims.get(job, 0)
		var helpers: int = job.helpers if "helpers" in job else 0
		if Chores.needs_two(c, arena.chore_owners) and not own:
			# Only worth it with a partner there (or on the way).
			score *= 1.5 if helpers >= 1 or (claimant != 0 and claimant != me.pid) else 0.05
		elif claimant != 0 and claimant != me.pid:
			score *= 0.3
		scored.append([score, job])
	if scored.is_empty():
		return null
	scored.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	# Now and then a bot goes for the second or third best, like people do.
	var k := 0
	if randf() < 0.15 and _job == null:
		k = mini(randi_range(1, 2), scored.size() - 1)
	# Keep going with the current job unless something is clearly better.
	if arena.is_open(_job):
		for e: Array in scored:
			if e[1] == _job and e[0] * 1.5 >= scored[0][0]:
				return _job
	return scored[k][1]


## The nearest pickup this bot could take, within `radius`, or null.
func _pickup_nearby(radius: float) -> Pickup:
	var best: Pickup = null
	var best_d := radius
	for pu: Pickup in arena.pickups.values():
		var d := Iso.fdist(pu.position, me.position)
		if d < best_d and pu.takeable_by(me, arena) and arena._wants(me, pu):
			best = pu
			best_d = d
	return best


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
	# Flyers go straight over furniture and walls, unless the remote weighs them down.
	if not me.data.get("flying", false) or me.carrying:
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
