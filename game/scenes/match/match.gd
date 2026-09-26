class_name Match
extends Control
## Runs one afternoon at home.
##
##   COUNTDOWN -> WAR (capture the remote) -> WHISTLE (car in the driveway!)
##   -> CLEANUP (everyone tidies together) -> RESULTS (the parents' verdict)
##
## The host is the referee: it owns the phase clock, the score, health, the
## remote and every knocked-over item, and broadcasts changes with the `_cl_*`
## RPCs. Clients report what they did through the `_srv_*` RPCs; the host
## checks those reports before applying them.

enum Phase { LOADING, COUNTDOWN, WAR, WHISTLE, CLEANUP, RESULTS }
enum Verdict { SPOTLESS, FINE, GROUNDED }

const PLAYER_SCENE := preload("res://scenes/match/player.tscn")
const PICKUP_RADIUS := 14.0
const FIX_RADIUS := 24.0
const DEBRIS_RADIUS := 16.0
const THROW_SPEED := 260.0
const THROW_TIME := 0.45
const TIDY_PASS := 0.6
const TIDY_SPOTLESS := 0.9
## Seconds you must stand on your base, unhurt, to change the channel.
const CHANNEL_TIME := 2.0
## Damage multiplier for a hit landed from stealth.
const AMBUSH_MULT := 2.0
## Knockback above this flips a character with the "flips" weakness.
const FLIP_KNOCK := 220.0
## Most scorch marks, splats and tufts of fur allowed at once.
const MAX_DEBRIS := 90

static var current: Match

@export var war_time := 180.0
@export var cleanup_time := 45.0
@export var capture_limit := 5
@export var respawn_time := 4.0
@export var remote_return_time := 8.0
@export var countdown_time := 3.0
@export var whistle_time := 3.0

@onready var hud: Hud = $HUD

var level: Level
var map_info: Dictionary = {}

var players: Dictionary = {}  # pid -> Player
var phase: Phase = Phase.LOADING
var time_left := 0.0
var scores: Array[int] = [0, 0]
var live := false
var remote: TVRemote
var debris: Dictionary = {}  # id -> Debris
var mess_baseline := 0.0
var stats: Dictionary = {}  # pid -> {"bonks", "caps", "fixes"}
var results: Dictionary = {}
var clouds: Array[LitterCloud] = []
var _scan_until: Dictionary = {}  # team -> time

# Host only.
var _loaded: Dictionary = {}
var _ko_timers: Dictionary = {}
var _next_debris_id := 1
var _sync_t := 0.0
var _remote_sync_t := 0.0
var _progress_sync_t := 0.0
var _load_timeout := 8.0
var _nav_dirty := false
var _nav_t := 0.0
var _next_cloud_id := 1
var _vortices: Dictionary = {}  # Zoomba pid -> seconds left
var _vortex_pulse := 0.0
var _captures: Dictionary = {}  # captured pid -> {"by", "mode", "t"}
var _strikes: Array[Dictionary] = []  # pending satellite strikes


func _ready() -> void:
	current = self
	map_info = Maps.get_map(Net.map_id)
	level = load(map_info["scene"]).instantiate()
	var world: SubViewport = $World/SubViewport
	world.add_child(level)
	level.position = level.centered_position(Vector2(world.size))
	war_time = map_info.get("war_time", war_time)
	cleanup_time = map_info.get("cleanup_time", cleanup_time)
	capture_limit = map_info.get("capture_limit", capture_limit)
	if Net.options.has("war"):
		war_time = float(Net.options["war"])
	if Net.options.has("cleanup"):
		cleanup_time = float(Net.options["cleanup"])
	_spawn_players()
	remote = TVRemote.new()
	remote.name = "Remote"
	remote.arena = self
	remote.home = level.home.position
	remote.position = remote.home
	level.entities.add_child(remote)
	hud.setup(self)
	log_event("map %s" % Net.map_id)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	if multiplayer.is_server():
		_loaded[1] = true
		_check_all_loaded()
	else:
		_srv_loaded.rpc_id(1)


func _exit_tree() -> void:
	if current == self:
		current = null


func _spawn_players() -> void:
	var ids: Array = Net.roster.keys()
	ids.sort()
	var slots := [0, 0]
	var team_sizes := Net.team_counts()
	for id: int in ids:
		var info: Dictionary = Net.roster[id]
		var p: Player = PLAYER_SCENE.instantiate()
		p.setup(id, info, self)
		p.position = level.bases[p.team].spawn_point(slots[p.team], team_sizes[p.team])
		slots[p.team] += 1
		players[id] = p
		stats[id] = {"bonks": 0, "caps": 0, "fixes": 0}
		if p.is_bot and multiplayer.is_server():
			p.brain = BotBrain.new(p, self)
		elif id == Net.my_id() and Net.options.has("autopilot"):
			p.brain = BotBrain.new(p, self)
		level.entities.add_child(p)


func local_player() -> Player:
	return players.get(Net.my_id())


func can_move() -> bool:
	return phase == Phase.WAR or phase == Phase.CLEANUP


func _sender() -> int:
	var s := multiplayer.get_remote_sender_id()
	return s if s != 0 else multiplayer.get_unique_id()


func log_event(msg: String) -> void:
	print("[match:%d %s %5.1f] %s" % [Net.my_id(), Phase.keys()[phase], time_left, msg])


# ================================================================ start-up

@rpc("any_peer", "call_remote", "reliable")
func _srv_loaded() -> void:
	if not multiplayer.is_server():
		return
	_loaded[multiplayer.get_remote_sender_id()] = true
	_check_all_loaded()


func _check_all_loaded() -> void:
	if phase != Phase.LOADING:
		return
	for id: int in players:
		if not players[id].is_bot and not _loaded.has(id):
			return
	_start()


func _start() -> void:
	if phase != Phase.LOADING:
		return
	_cl_start.rpc()
	_set_phase(Phase.COUNTDOWN, countdown_time)


@rpc("authority", "call_local", "reliable")
func _cl_start() -> void:
	live = true


func _set_phase(p: Phase, t: float) -> void:
	_cl_phase.rpc(p, t, scores)


@rpc("authority", "call_local", "reliable")
func _cl_phase(p: int, t: float, new_scores: Array) -> void:
	var changed := p != phase
	phase = p as Phase
	time_left = t
	scores = [int(new_scores[0]), int(new_scores[1])]
	if changed:
		_on_phase_entered()


func _on_phase_entered() -> void:
	log_event("phase %s" % Phase.keys()[phase])
	match phase:
		Phase.COUNTDOWN:
			hud.banner("The parents just left...", "Grab the TV remote!")
		Phase.WAR:
			hud.banner("WAR!", "Carry the remote to your base")
		Phase.WHISTLE:
			hud.banner("CAR IN THE DRIVEWAY!", "Truce! Hide the evidence!")
			for p: Player in players.values():
				p.reset_for_phase()
		Phase.CLEANUP:
			hud.banner("CLEAN UP!", "Fix everything before they walk in")
	hud.on_phase_changed()


# ============================================================== main loop

func _physics_process(delta: float) -> void:
	if phase in [Phase.COUNTDOWN, Phase.WAR, Phase.WHISTLE, Phase.CLEANUP]:
		time_left = maxf(0.0, time_left - delta)
	if phase == Phase.WAR:
		level.room.clock_progress = 1.0 - time_left / maxf(war_time, 1.0)
	elif phase == Phase.CLEANUP:
		level.room.clock_progress = 1.0 - time_left / maxf(cleanup_time, 1.0)
	if not multiplayer.is_server():
		return

	match phase:
		Phase.LOADING:
			_load_timeout -= delta
			if _load_timeout <= 0.0:
				_start()
		Phase.COUNTDOWN:
			if time_left <= 0.0:
				_set_phase(Phase.WAR, war_time)
		Phase.WAR:
			_tick_remote(delta)
			_tick_ko(delta)
			_tick_knockovers()
			_tick_debris(delta)
			_tick_gags(delta)
			_tick_navigation(delta)
			if time_left <= 0.0 or scores.max() >= capture_limit:
				_end_war()
		Phase.WHISTLE:
			if time_left <= 0.0:
				_begin_cleanup()
		Phase.CLEANUP:
			_tick_remote(delta)
			_tick_cleanup(delta)
			_tick_debris(delta)
			_tick_navigation(delta)
			if time_left <= 0.0 or mess_remaining() <= 0.0:
				_finish()

	if phase == Phase.LOADING or phase == Phase.RESULTS:
		return
	_sync_t += delta
	if _sync_t >= 1.0:
		_sync_t = 0.0
		_cl_phase.rpc(phase, time_left, scores)
	_remote_sync_t += delta
	if _remote_sync_t >= 0.05:
		_remote_sync_t = 0.0
		_cl_remote.rpc(remote.state, remote.carrier_pid, remote.position, remote.z, remote.hold / CHANNEL_TIME)


func _end_war() -> void:
	for tid: int in _captures.keys():
		_release(tid)
	_vortices.clear()
	_strikes.clear()
	var winner := _winning_team()
	_set_phase(Phase.WHISTLE, whistle_time)
	_ko_timers.clear()
	_cl_tv.rpc(winner)
	log_event("war over %d-%d" % [scores[0], scores[1]])


func _begin_cleanup() -> void:
	mess_baseline = mess_remaining()
	_cl_baseline.rpc(mess_baseline)
	var knocked := level.mess_items.filter(func(i: MessItem) -> bool: return i.knocked).size()
	log_event("cleanup starts: mess=%.1f (%d items knocked, %d debris)" % [mess_baseline, knocked, debris.size()])
	_set_phase(Phase.CLEANUP, cleanup_time)


func _finish() -> void:
	var remaining := mess_remaining()
	var tidy := 1.0 if mess_baseline <= 0.0 else clampf(1.0 - remaining / mess_baseline, 0.0, 1.0)
	var verdict := Verdict.GROUNDED
	if tidy >= TIDY_SPOTLESS:
		verdict = Verdict.SPOTLESS
	elif tidy >= TIDY_PASS:
		verdict = Verdict.FINE
	_cl_results.rpc(scores, tidy, verdict, _winning_team(), stats)


func _winning_team() -> int:
	if scores[0] == scores[1]:
		return -1
	return 0 if scores[0] > scores[1] else 1


@rpc("authority", "call_local", "reliable")
func _cl_baseline(total: float) -> void:
	mess_baseline = total


@rpc("authority", "call_local", "reliable")
func _cl_tv(team: int) -> void:
	if level.tv:
		level.tv.channel = team


@rpc("authority", "call_local", "reliable")
func _cl_results(final_scores: Array, tidy: float, verdict: int, winner: int, final_stats: Dictionary) -> void:
	phase = Phase.RESULTS
	scores = [int(final_scores[0]), int(final_scores[1])]
	stats = final_stats
	results = {"tidy": tidy, "verdict": verdict, "winner": winner}
	level.room.door_open = true
	log_event("results tidy=%.2f verdict=%s winner=%d score=%d-%d" % [tidy, Verdict.keys()[verdict], winner, scores[0], scores[1]])
	hud.show_results(results)
	Net.matches_played += 1
	if Net.is_host() and Net.matches_played <= int(Net.options.get("rematches", "0")):
		get_tree().create_timer(2.0).timeout.connect(Net.start_match)


## Total weight of everything still out of place (0 = spotless).
func mess_remaining() -> float:
	var m := 0.0
	for item in level.mess_items:
		if item.knocked:
			m += item.weight()
	for f in level.furniture:
		if f.wrecked:
			m += f.weight()
	m += debris.size() * 0.5
	if remote.state != TVRemote.State.HOME:
		m += 1.0
	return m


func tidiness() -> float:
	if mess_baseline <= 0.0:
		return 1.0
	return clampf(1.0 - mess_remaining() / mess_baseline, 0.0, 1.0)


# ================================================================== remote

func _tick_remote(delta: float) -> void:
	var r := remote
	r.grace = maxf(0.0, r.grace - delta)
	match r.state:
		TVRemote.State.CARRIED:
			var c := r.carrier()
			if c == null or c.is_ko:
				_drop_remote(r.position)
				return
			r.position = c.position
			if phase == Phase.WAR and level.bases[c.team].contains(c.position):
				r.hold += delta
				if r.hold >= CHANNEL_TIME:
					_score(c)
					return
			else:
				r.hold = 0.0
			if phase == Phase.CLEANUP and level.home.contains(c.position):
				_return_remote(c)
				return
		TVRemote.State.FLYING:
			r.timer -= delta
			r.position = level.clamp_to_floor(r.position + r.vel * delta)
			r.z = sin(clampf(r.timer / THROW_TIME, 0.0, 1.0) * PI) * 14.0
			if r.timer <= 0.0:
				r.z = 0.0
				_drop_remote(r.position)
		TVRemote.State.DROPPED:
			if phase == Phase.WAR:
				r.timer -= delta
				if r.timer <= 0.0:
					_reset_remote()
					_cl_event.rpc("The remote scooted back to the rug.", Color.WHITE)
					return
	if phase == Phase.CLEANUP and r.state == TVRemote.State.HOME:
		return  # Already where it belongs.
	if r.is_free() or (r.state == TVRemote.State.FLYING and r.grace <= 0.0):
		var best: Player = null
		var best_d := PICKUP_RADIUS
		for p: Player in players.values():
			if p.is_ko or p.captured_by != 0 or (p.pid == r.thrower and r.grace > 0.0):
				continue
			var d := Iso.fdist(p.position, r.position)
			if d < best_d:
				best = p
				best_d = d
		if best:
			r.state = TVRemote.State.CARRIED
			r.carrier_pid = best.pid
			r.z = 0.0
			_cl_event.rpc("%s grabbed the remote!" % best.display_name, Roster.TEAM_COLORS[best.team])


func _drop_remote(pos: Vector2) -> void:
	remote.hold = 0.0
	remote.state = TVRemote.State.DROPPED
	remote.carrier_pid = 0
	remote.position = level.clamp_to_floor(pos)
	remote.timer = remote_return_time


func _reset_remote() -> void:
	remote.hold = 0.0
	remote.state = TVRemote.State.HOME
	remote.carrier_pid = 0
	remote.z = 0.0
	remote.position = remote.home


func _score(c: Player) -> void:
	scores[c.team] += 1
	stats[c.pid]["caps"] += 1
	_reset_remote()
	_cl_scored.rpc(c.pid, c.team, scores)


func _return_remote(c: Player) -> void:
	_reset_remote()
	stats[c.pid]["fixes"] += 1
	_cl_event.rpc("%s put the remote back!" % c.display_name, Color("8ff0a4"))


@rpc("authority", "call_local", "reliable")
func _cl_scored(pid: int, team: int, new_scores: Array) -> void:
	scores = [int(new_scores[0]), int(new_scores[1])]
	if level.tv:
		level.tv.channel = team
	level.bases[team].pulse = 1.0
	var who: String = players[pid].display_name if players.has(pid) else "Someone"
	hud.banner("%s SCORE!" % Roster.TEAM_NAMES[team].to_upper(), "%s changed the channel" % who, Roster.TEAM_COLORS[team])
	log_event("score team=%d by=%d -> %d-%d" % [team, pid, scores[0], scores[1]])


@rpc("authority", "call_local", "unreliable_ordered")
func _cl_remote(state: int, carrier: int, pos: Vector2, pz: float, hold: float) -> void:
	remote.apply_net(state, carrier, pos, pz)
	remote.hold_frac = hold
	for p: Player in players.values():
		p.carrying = state == TVRemote.State.CARRIED and p.pid == carrier


func request_throw(p: Player, dir: Vector2) -> void:
	if multiplayer.is_server():
		_srv_throw(p.pid, dir)
	else:
		_srv_throw.rpc_id(1, p.pid, dir)


@rpc("any_peer", "call_remote", "reliable")
func _srv_throw(pid: int, dir: Vector2) -> void:
	var p: Player = players.get(pid)
	if p == null or p.get_multiplayer_authority() != _sender():
		return
	if remote.state != TVRemote.State.CARRIED or remote.carrier_pid != pid:
		return
	remote.state = TVRemote.State.FLYING
	remote.carrier_pid = 0
	remote.thrower = pid
	remote.grace = 0.35
	remote.timer = THROW_TIME
	remote.position = p.position
	remote.vel = Iso.to_screen((dir if dir.length() > 0.1 else p.facing).normalized() * THROW_SPEED)


# ================================================================== combat

func report_hit(attacker: Player, target: Player, ability: int, dir: Vector2, ambush: bool = false) -> void:
	if ability != 2:
		var dealt := float(Roster.ability(attacker.data, ability).get("damage", 0))
		attacker.gag_charge = minf(1.0, attacker.gag_charge + dealt * Player.GAG_PER_DAMAGE)
	if multiplayer.is_server():
		_srv_hit(attacker.pid, target.pid, ability, dir, ambush)
	else:
		_srv_hit.rpc_id(1, attacker.pid, target.pid, ability, dir, ambush)


@rpc("any_peer", "call_remote", "reliable")
func _srv_hit(aid: int, tid: int, ability: int, dir: Vector2, ambush: bool) -> void:
	if not multiplayer.is_server() or phase != Phase.WAR:
		return
	var a: Player = players.get(aid)
	var t: Player = players.get(tid)
	if a == null or t == null or a.get_multiplayer_authority() != _sender():
		return
	if a.team == t.team or t.is_ko or t.invuln > 0.0:
		return
	if Iso.fdist(a.position, t.position) > 400.0:
		return
	var spec := Roster.ability(a.data, ability)
	var kind := int(spec.get("kind", -1))
	# Flyers are out of reach of slams and suction.
	if ability == 1 and t.data.get("flying", false) and (kind == Roster.Special.SLAM or kind == Roster.Special.PULL):
		return
	var d := dir.normalized() if dir.length() > 0.01 else Vector2.RIGHT
	var knock_scale := 1.0
	if ability == 1 and kind == Roster.Special.PULL:
		d = Iso.to_floor(a.position - t.position).normalized()
		knock_scale = clampf(Iso.fdist(a.position, t.position) / float(spec["radius"]), 0.35, 1.0)
	# Hits from hiding hurt twice as much (if the attacker really was hidden).
	var ambushed := ambush and Time.get_ticks_msec() / 1000.0 - a.last_stealth_time < 0.6
	if ambushed:
		log_event("ambush %d on %d" % [aid, tid])
	_apply_hit(a, t, spec, d, knock_scale, ambushed)


## Lands a hit on the host: damage, knockback, stuns, traits and KOs.
func _apply_hit(a: Player, t: Player, spec: Dictionary, d: Vector2, knock_scale: float = 1.0, ambushed: bool = false) -> void:
	if t.captured_by != 0 or t.is_ko:
		return  # Safe inside a dust bin (or a claw).
	var damage := float(spec.get("damage", 0))
	var knock := float(spec.get("knock", 0.0)) * knock_scale
	var stun := float(spec.get("stun", 0.0))
	if ambushed:
		damage *= AMBUSH_MULT
		stun = maxf(stun, 0.5)
	knock *= float(t.data.get("knock_mult", 1.0))
	if t.data.get("flips", false) and knock >= FLIP_KNOCK:
		stun = maxf(stun, 1.5)
	t.hp = maxi(0, t.hp - roundi(damage))
	if remote.carrier_pid == t.pid and remote.state == TVRemote.State.CARRIED:
		remote.hold = 0.0
		# A dog never lets go of a bone, though.
		if t.data.get("butterfingers", false) and t.hp > 0 and not t.has_bone():
			_drop_remote(t.position)
			_cl_event.rpc("%s dropped the remote! (butterfingers)" % t.display_name, Roster.TEAM_COLORS[t.team])
	_cl_damaged.rpc(t.pid, t.hp, d * knock, stun, ambushed)
	if t.hp <= 0:
		_ko(t, a)


func _ko(t: Player, by: Player) -> void:
	_ko_timers[t.pid] = respawn_time + float(t.data.get("reboot", 0.0))
	stats[by.pid]["bonks"] += 1
	if remote.state == TVRemote.State.CARRIED and remote.carrier_pid == t.pid:
		_drop_remote(t.position)
	_spawn_debris("fur" if t.team == Roster.Team.PETS else "bolts", t.position)
	_cl_ko.rpc(t.pid, by.pid)


const KO_VERBS: Array[String] = ["bonked", "booped", "flattened", "yeeted", "sat on", "unplugged"]


@rpc("authority", "call_local", "reliable")
func _cl_damaged(tid: int, new_hp: int, knock: Vector2, stun: float, ambushed: bool) -> void:
	if players.has(tid):
		players[tid].on_damaged(new_hp, knock, stun, ambushed)


## Can players on `viewer_team` see `p` right now? Hidden characters show up
## when someone on the viewing team with a nose or x-ray vision is close.
func is_revealed(p: Player, viewer_team: int) -> bool:
	if not p.stealthed or p.team == viewer_team:
		return true
	if _scan_until.get(viewer_team, 0.0) > _now():
		return true  # Unit-7's satellite is scanning the house.
	for q: Player in players.values():
		if q.team != viewer_team or q.is_ko:
			continue
		var r := float(q.data.get("reveal", 0.0))
		if r > 0.0 and Iso.fdist(q.position, p.position) <= r:
			return true
	return false


@rpc("authority", "call_local", "reliable")
func _cl_ko(tid: int, by_pid: int) -> void:
	if not players.has(tid):
		return
	var t: Player = players[tid]
	t.set_ko(true)
	var by_name: String = players[by_pid].display_name if players.has(by_pid) else "Someone"
	var verb: String = KO_VERBS[posmod(tid * 7 + by_pid * 13 + int(time_left), KO_VERBS.size())]
	hud.feed("%s %s %s!" % [by_name, verb, t.display_name], Roster.TEAM_COLORS[1 - t.team])
	log_event("ko %d by %d" % [tid, by_pid])


func _tick_ko(delta: float) -> void:
	for pid: int in _ko_timers.keys():
		_ko_timers[pid] -= delta
		if _ko_timers[pid] <= 0.0:
			_ko_timers.erase(pid)
			var p: Player = players.get(pid)
			if p:
				var base := level.bases[p.team]
				_cl_respawn.rpc(pid, base.spawn_point(randi() % 6, 6))


@rpc("authority", "call_local", "reliable")
func _cl_respawn(pid: int, at: Vector2) -> void:
	if players.has(pid):
		players[pid].respawn(at)


func report_special_effect(p: Player) -> void:
	if multiplayer.is_server():
		_srv_special(p.pid)
	else:
		_srv_special.rpc_id(1, p.pid)


@rpc("any_peer", "call_remote", "reliable")
func _srv_special(pid: int) -> void:
	if not multiplayer.is_server() or phase != Phase.WAR:
		return
	var p: Player = players.get(pid)
	if p == null or p.get_multiplayer_authority() != _sender() or p.is_ko:
		return
	var sp: Dictionary = p.data["special"]
	match int(sp["kind"]):
		Roster.Special.PULL:
			if remote.is_free() and Iso.fdist(remote.position, p.position) <= float(sp["radius"]):
				var pos := remote.position.lerp(p.position, 0.75)
				_drop_remote(pos)
		Roster.Special.AURA:
			for ally: Player in players.values():
				if ally.team != p.team or ally.is_ko:
					continue
				if Iso.fdist(ally.position, p.position) <= float(sp["radius"]):
					ally.hp = mini(ally.max_hp, ally.hp + int(sp["heal"]))
					_cl_buff.rpc(ally.pid, float(sp["speed_mult"]), float(sp["duration"]), ally.hp)


@rpc("authority", "call_local", "reliable")
func _cl_buff(pid: int, mult: float, duration: float, new_hp: int) -> void:
	if players.has(pid):
		players[pid].apply_buff(mult, duration, new_hp)


# ============================================================ mess & tidying

func report_mess_hit(item: MessItem, force: float, dir: Vector2) -> void:
	if item.knocked or phase != Phase.WAR:
		return
	if multiplayer.is_server():
		_srv_mess_hit(item.index, force, dir)
	else:
		_srv_mess_hit.rpc_id(1, item.index, force, dir)


@rpc("any_peer", "call_remote", "reliable")
func _srv_mess_hit(idx: int, force: float, dir: Vector2) -> void:
	if not multiplayer.is_server() or phase != Phase.WAR:
		return
	if idx < 0 or idx >= level.mess_items.size():
		return
	var item := level.mess_items[idx]
	if item.can_be_knocked_by(minf(force, 400.0)):
		_knock(item, dir)


## Players who get knocked flying (or dash) into things knock them over.
func _tick_knockovers() -> void:
	for p: Player in players.values():
		var clumsy: bool = p.data.get("clumsy", false) and p.moving
		if p.is_ko or p.data.get("flying", false) or not (p.tumbling or p.dashing or clumsy):
			continue
		var force := 260.0 if p.tumbling else 120.0
		for item in level.mess_items:
			if not item.knocked and Iso.fdist(p.position, item.position) <= 12.0 and item.can_be_knocked_by(force):
				_knock(item, Iso.to_floor(item.position - p.position))


func _knock(item: MessItem, dir: Vector2) -> void:
	var d := dir.normalized() if dir.length() > 0.01 else Vector2.RIGHT
	var target := level.clamp_to_floor(item.home + Iso.to_screen(d * 16.0), 0.6)
	_cl_mess_state.rpc(item.index, true, target - item.home)


@rpc("authority", "call_local", "reliable")
func _cl_mess_state(idx: int, knocked: bool, offset: Vector2) -> void:
	var item := level.mess_items[idx]
	item.apply_state(knocked, offset, 0.0, 0)
	if knocked:
		log_event("knocked %s" % item.name)


@rpc("authority", "call_local", "unreliable_ordered")
func _cl_mess_progress(idx: int, progress: float, helpers: int) -> void:
	var item := level.mess_items[idx]
	if item.knocked:
		item.apply_state(true, item.offset, progress, helpers)


## How fast this character tidies right now (Bass's playlist speeds up everyone near it).
func _tidy_power(p: Player) -> float:
	var power := float(p.data["tidy"])
	for q: Player in players.values():
		if q.data.get("playlist", false) and Iso.fdist(q.position, p.position) <= 80.0:
			return power * 1.3
	return power


## Handy and strong characters count as two pairs of hands.
func _lift(p: Player) -> int:
	return 2 if p.data.get("strong", false) or p.data.get("handy", false) else 1


func _tick_cleanup(delta: float) -> void:
	_progress_sync_t += delta
	var send := _progress_sync_t >= 0.1
	if send:
		_progress_sync_t = 0.0
	for f in level.furniture:
		if f.wrecked:
			_tick_rebuild(f, delta, send)
	for item in level.mess_items:
		if not item.knocked:
			continue
		var lift := 0
		var power := 0.0
		var fixers: Array[Player] = []
		for p: Player in players.values():
			if p.interacting and Iso.fdist(p.position, item.position) <= FIX_RADIUS:
				lift += _lift(p)
				power += _tidy_power(p)
				fixers.append(p)
		if lift >= item.required_lift():
			item.progress += delta * power / item.fix_time()
		item.helpers = lift
		if item.progress >= 1.0:
			for f in fixers:
				stats[f.pid]["fixes"] += 1
			_cl_mess_state.rpc(item.index, false, Vector2.ZERO)
			_cl_event.rpc("%s fixed the %s!" % [fixers[0].display_name, item.sprite_name.replace("_teal", "")], Color("8ff0a4"))
		elif send:
			_cl_mess_progress.rpc(item.index, item.progress, lift)


# ==================================================================== gags

static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


## The litter cloud at a point, if any (only matters during the war).
func cloud_at(p: Vector2) -> LitterCloud:
	if phase != Phase.WAR:
		return null
	for c in clouds:
		if is_instance_valid(c) and c.contains(p):
			return c
	return null


func report_gag(p: Player, point: Vector2) -> void:
	if multiplayer.is_server():
		_srv_gag(p.pid, point)
	else:
		_srv_gag.rpc_id(1, p.pid, point)


@rpc("any_peer", "call_remote", "reliable")
func _srv_gag(pid: int, point: Vector2) -> void:
	if not multiplayer.is_server() or phase != Phase.WAR:
		return
	var p: Player = players.get(pid)
	if p == null or p.get_multiplayer_authority() != _sender() or p.is_ko:
		return
	var g: Dictionary = p.data["gag"]
	log_event("gag %s by %d" % [g["name"], pid])
	match int(g["kind"]):
		Roster.Gag.LITTER:
			var at := level.clamp_to_floor(point)
			_cl_cloud.rpc(_next_cloud_id, at, float(g["cloud_radius"]), float(g["cloud_time"]), p.team)
			_next_cloud_id += 1
			for k in 3:
				_spawn_debris("litter", at + Iso.to_screen(Vector2.from_angle(TAU * k / 3.0 + randf()) * 16.0))
		Roster.Gag.MEGA_SUCK:
			_vortices[pid] = float(g["duration"])
		Roster.Gag.SATELLITE:
			_strikes.append({"pid": pid, "pos": point, "t": float(g["delay"])})
			_cl_satellite.rpc(point, float(g["delay"]), float(g["radius"]))
			_cl_scan.rpc(p.team, float(g["scan"]))
		Roster.Gag.CLAW_MACHINE:
			var best: Player = null
			var best_d := float(g["radius"])
			for t: Player in players.values():
				if t.team == p.team or t.is_ko or t.captured_by != 0 or t.invuln > 0.0:
					continue
				var d := Iso.fdist(t.position, p.position)
				if d < best_d:
					best = t
					best_d = d
			if best:
				_capture(best, p, Player.Capture.GRABBED, float(g["hold"]))
			else:
				_cl_event.rpc("The Claw grabbed... nothing. Like a real claw machine.", Roster.TEAM_COLORS[p.team])
		Roster.Gag.DANCE:
			for t: Player in players.values():
				if t.is_ko or Iso.fdist(t.position, p.position) > float(g["radius"]):
					continue
				if t.team == p.team:
					t.hp = mini(t.max_hp, t.hp + int(g["heal"]))
					_cl_buff.rpc(t.pid, 1.0, 0.1, t.hp)
				elif t.captured_by == 0:
					_cl_dance.rpc(t.pid, float(g["duration"]))


func _tick_gags(delta: float) -> void:
	# Mega Suck: drag enemies in, swallow anyone who gets close.
	_vortex_pulse -= delta
	var pulse := _vortex_pulse <= 0.0
	if pulse:
		_vortex_pulse = 0.15
	for pid: int in _vortices.keys():
		_vortices[pid] -= delta
		var z: Player = players.get(pid)
		if z == null or z.is_ko or _vortices[pid] <= 0.0:
			_vortices.erase(pid)
			continue
		var g: Dictionary = z.data["gag"]
		for t: Player in players.values():
			if t.team == z.team or t.is_ko or t.captured_by != 0 or t.invuln > 0.0 or t.data.get("flying", false):
				continue
			var d := Iso.fdist(t.position, z.position)
			if d <= 12.0:
				_capture(t, z, Player.Capture.SWALLOWED, float(g["swallow_time"]))
			elif d <= float(g["radius"]) and pulse:
				var toward := Iso.to_floor(z.position - t.position).normalized()
				_cl_pull.rpc(t.pid, toward * float(g["pull"]))
	# Captures run out: spit them out / drop them.
	for tid: int in _captures.keys():
		var c: Dictionary = _captures[tid]
		c["t"] -= delta
		var by: Player = players.get(c["by"])
		if c["t"] <= 0.0 or by == null or by.is_ko:
			_release(tid)
	# Satellite strikes land.
	for strike in _strikes.duplicate():
		strike["t"] -= delta
		if strike["t"] > 0.0:
			continue
		_strikes.erase(strike)
		var p: Player = players.get(strike["pid"])
		if p == null:
			continue
		var g: Dictionary = p.data["gag"]
		var at: Vector2 = strike["pos"]
		var r := float(g["radius"])
		for t: Player in players.values():
			if t.team != p.team and Iso.fdist(t.position, at) <= r + Player.BODY_RADIUS:
				_apply_hit(p, t, g, Iso.to_floor(t.position - at).normalized())
		for item in level.mess_items:
			if not item.knocked and Iso.fdist(item.position, at) <= r + 6.0:
				_knock(item, Iso.to_floor(item.position - at))
		for f in level.furniture:
			if f.can_be_damaged() and Iso.fdist(f.position, at) <= r + f.reach():
				_damage_furniture(f, float(g["demolition"]))
		_spawn_debris("scorch", at)


func _capture(t: Player, by: Player, mode: int, duration: float) -> void:
	_captures[t.pid] = {"by": by.pid, "mode": mode, "t": duration}
	_cl_capture.rpc(t.pid, by.pid, mode)
	var what := "swallowed" if mode == Player.Capture.SWALLOWED else "grabbed"
	# Whoever was holding the remote loses it to their captor.
	if remote.state == TVRemote.State.CARRIED and remote.carrier_pid == t.pid:
		remote.carrier_pid = by.pid
		remote.hold = 0.0
		_cl_event.rpc("%s %s %s AND the remote!" % [by.display_name, what, t.display_name], Roster.TEAM_COLORS[by.team])
	else:
		_cl_event.rpc("%s %s %s!" % [by.display_name, what, t.display_name], Roster.TEAM_COLORS[by.team])


func _release(tid: int) -> void:
	var c: Dictionary = _captures.get(tid, {})
	_captures.erase(tid)
	var t: Player = players.get(tid)
	if t == null:
		return
	var by: Player = players.get(c.get("by", 0))
	var dir := by.facing if by else Vector2.RIGHT
	_cl_release.rpc(tid)
	if by:
		# Spat out (or dropped) with a thump.
		_apply_hit(by, t, by.data["gag"], dir)


@rpc("authority", "call_local", "reliable")
func _cl_cloud(id: int, pos: Vector2, radius: float, duration: float, team: int) -> void:
	var c := LitterCloud.new()
	c.setup(id, pos, radius, duration, team)
	level.entities.add_child(c)
	var alive: Array[LitterCloud] = [c]
	for old in clouds:
		if is_instance_valid(old):
			alive.append(old)
	clouds = alive


@rpc("authority", "call_local", "reliable")
func _cl_satellite(pos: Vector2, delay: float, radius: float) -> void:
	Fx.satellite(level.entities, pos, radius, delay)


@rpc("authority", "call_local", "reliable")
func _cl_scan(team: int, duration: float) -> void:
	_scan_until[team] = _now() + duration
	if local_player() and local_player().team == team:
		hud.banner("SATELLITE SCAN", "Every hidden enemy is on screen", Roster.TEAM_COLORS[team])


@rpc("authority", "call_local", "reliable")
func _cl_capture(tid: int, by_pid: int, mode: int) -> void:
	if players.has(tid):
		players[tid].start_capture(by_pid, mode)


@rpc("authority", "call_local", "reliable")
func _cl_release(tid: int) -> void:
	if players.has(tid):
		players[tid].end_capture(Vector2.ZERO)


@rpc("authority", "call_local", "reliable")
func _cl_dance(tid: int, duration: float) -> void:
	if players.has(tid):
		players[tid].start_dance(duration)


@rpc("authority", "call_local", "unreliable_ordered")
func _cl_pull(tid: int, pull: Vector2) -> void:
	if players.has(tid):
		players[tid].apply_pull(pull)


# =============================================================== furniture

func report_furniture_hit(f: Furniture, amount: float) -> void:
	if amount <= 0.0 or not f.can_be_damaged() or phase != Phase.WAR:
		return
	if multiplayer.is_server():
		_srv_furniture_hit(f.index, amount)
	else:
		_srv_furniture_hit.rpc_id(1, f.index, amount)


@rpc("any_peer", "call_remote", "reliable")
func _srv_furniture_hit(idx: int, amount: float) -> void:
	if not multiplayer.is_server() or phase != Phase.WAR or idx < 0 or idx >= level.furniture.size():
		return
	_damage_furniture(level.furniture[idx], clampf(amount, 0.0, 120.0))


func _damage_furniture(f: Furniture, amount: float) -> void:
	if not f.can_be_damaged():
		return
	f.hp = maxf(0.0, f.hp - amount)
	var now_wrecked := f.hp <= 0.0
	_cl_furniture_state.rpc(f.index, f.hp / f.max_hp, now_wrecked, 0.0, 0)
	if now_wrecked:
		_spawn_debris("scorch", f.position)
		_cl_event.rpc("The %s is destroyed!" % _furniture_name(f), Color("ffb347"))


@rpc("authority", "call_local", "reliable")
func _cl_furniture_state(idx: int, hp_frac: float, wrecked: bool, progress: float, helpers: int) -> void:
	var f := level.furniture[idx]
	var was_wrecked := f.wrecked
	f.apply_state(hp_frac, wrecked, progress, helpers)
	if wrecked != was_wrecked:
		Fx.boom(level.entities, f.position, f.reach(), false)
		_nav_dirty = true
		if wrecked:
			log_event("wrecked %s" % f.name)


@rpc("authority", "call_local", "unreliable_ordered")
func _cl_furniture_progress(idx: int, progress: float, helpers: int) -> void:
	var f := level.furniture[idx]
	if f.wrecked:
		f.apply_state(0.0, true, progress, helpers)


func _tick_rebuild(f: Furniture, delta: float, send: bool) -> void:
	var lift := 0
	var power := 0.0
	var fixers: Array[Player] = []
	for p: Player in players.values():
		if p.interacting and Iso.fdist(p.position, f.position) <= FIX_RADIUS + f.reach():
			lift += _lift(p)
			power += _tidy_power(p)
			fixers.append(p)
	if lift >= f.required_lift():
		f.rebuild += delta * power / f.rebuild_time()
	f.helpers = lift
	if f.rebuild >= 1.0:
		for p in fixers:
			stats[p.pid]["fixes"] += 2
		_cl_furniture_state.rpc(f.index, 1.0, false, 0.0, 0)
		_cl_event.rpc("%s rebuilt the %s!" % [fixers[0].display_name, _furniture_name(f)], Color("8ff0a4"))
	elif send:
		_cl_furniture_progress.rpc(f.index, f.rebuild, lift)


## Bots re-plan around wrecked (or rebuilt) furniture, at most a few times a second.
func _tick_navigation(delta: float) -> void:
	_nav_t -= delta
	if _nav_dirty and _nav_t <= 0.0:
		_nav_dirty = false
		_nav_t = 0.5
		level.rebuild_navigation()


static func _furniture_name(f: Furniture) -> String:
	if f.style != Furniture.Style.BOX:
		return String(Furniture.Style.keys()[f.style]).to_lower().replace("_", " ")
	var n := String(f.name).rstrip("0123456789")
	for suffix in ["Pets", "Robots", "Left", "Right", "Back", "Front"]:
		n = n.trim_suffix(suffix)
	return n.capitalize().to_lower()


## Explosions leave scorch marks and egg splats behind.
func report_decal(pos: Vector2, decal: String) -> void:
	if decal == "" or phase != Phase.WAR:
		return
	if multiplayer.is_server():
		_srv_decal(pos, decal)
	else:
		_srv_decal.rpc_id(1, pos, decal)


@rpc("any_peer", "call_remote", "reliable")
func _srv_decal(pos: Vector2, decal: String) -> void:
	if not multiplayer.is_server() or phase != Phase.WAR or not decal in ["scorch", "yolk"]:
		return
	# One mark per spot; repeated blasts in the same place don't stack up.
	for d: Debris in debris.values():
		if d.kind == decal and Iso.fdist(d.position, pos) < 14.0:
			return
	_spawn_debris(decal, pos)


# ================================================================== debris

func _spawn_debris(kind: String, pos: Vector2) -> void:
	if debris.size() >= MAX_DEBRIS:
		return
	var id := _next_debris_id
	_next_debris_id += 1
	var jitter := Iso.to_screen(Vector2(randf_range(-6, 6), randf_range(-6, 6)))
	_cl_debris_add.rpc(id, kind, _free_floor_spot(pos + jitter))


## Nudges a point off any furniture (flyers get KO'd above armchairs).
func _free_floor_spot(pos: Vector2) -> Vector2:
	var space := level.get_world_2d().direct_space_state
	var query := PhysicsPointQueryParameters2D.new()
	query.collision_mask = 2
	var p := level.clamp_to_floor(pos)
	var toward_center := (level.home.position - p).normalized()
	for step in 12:
		query.position = level.to_global(p)
		if space.intersect_point(query, 1).is_empty():
			return p
		p += toward_center * 4.0
	return p


@rpc("authority", "call_local", "reliable")
func _cl_debris_add(id: int, kind: String, pos: Vector2) -> void:
	var d := Debris.new()
	d.setup(id, kind, pos)
	level.entities.add_child(d)
	debris[id] = d


@rpc("authority", "call_local", "reliable")
func _cl_debris_remove(id: int) -> void:
	if debris.has(id):
		debris[id].queue_free()
		debris.erase(id)


@rpc("authority", "call_local", "unreliable_ordered")
func _cl_debris_progress(id: int, progress: float) -> void:
	if debris.has(id):
		debris[id].set_progress(progress)


func _tick_debris(delta: float) -> void:
	for id: int in debris.keys():
		var d: Debris = debris[id]
		var power := 0.0
		var cleaner: Player = null
		for p: Player in players.values():
			if p.is_ko:
				continue
			var dist := Iso.fdist(p.position, d.position)
			if phase == Phase.CLEANUP and p.data.get("vacuum", false) and dist <= 10.0 and d.kind in ["fur", "bolts", "litter"]:
				power = 100.0  # Zoomba just hoovers it up.
				cleaner = p
				break
			if phase == Phase.CLEANUP and p.interacting and dist <= DEBRIS_RADIUS:
				power += _tidy_power(p)
				cleaner = p
		if power <= 0.0:
			continue
		d.progress += delta * power / d.clean_time
		if d.progress >= 1.0:
			if phase == Phase.CLEANUP and cleaner:
				stats[cleaner.pid]["fixes"] += 1
			_cl_debris_remove.rpc(id)
		else:
			_cl_debris_progress.rpc(id, d.progress)


# =================================================================== misc

@rpc("authority", "call_local", "reliable")
func _cl_event(text: String, color: Color) -> void:
	hud.feed(text, color)
	log_event(text)


func _on_peer_disconnected(id: int) -> void:
	if not players.has(id):
		return
	if multiplayer.is_server():
		if remote.carrier_pid == id:
			_drop_remote(players[id].position)
		_ko_timers.erase(id)
		_cl_remove_player.rpc(id)
		_check_all_loaded()
	else:
		_cl_remove_player(id)


@rpc("authority", "call_local", "reliable")
func _cl_remove_player(id: int) -> void:
	if players.has(id):
		hud.feed("%s went home." % players[id].display_name, Color.WHITE)
		players[id].queue_free()
		players.erase(id)


func summary() -> String:
	return "phase=%s score=%d-%d mess=%.1f debris=%d results=%s" % [
		Phase.keys()[phase], scores[0], scores[1], mess_remaining(), debris.size(), str(results)]
