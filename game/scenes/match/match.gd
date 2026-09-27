class_name Match
extends Control
## Runs one afternoon at home.
##
##   COUNTDOWN -> WAR (capture the remote) -> WHISTLE (car in the driveway!)
##   -> CLEANUP (everyone tidies together) -> RESULTS (the parents' verdict)
##
## Cleanup is by specialty (see Chores): every job belongs to one character,
## who does it properly; anyone else helps at a fifth of the speed.
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
## Most bits of floor mess allowed at once (after that, piles just grow).
const MAX_DEBRIS := 140
## ...plus this many more when every pile of that kind of mess is already as big as it gets.
const MAX_DEBRIS_EXTRA := 40
## Floor pixels in one tile.
const TILE := 22.63
## How a bit of floor mess got cleaned (for the effect everyone sees).
enum How { HELPED, OWNER, VACUUM, SWAT, THUMP }
## Bots knock through at most this many walls per team per war.
const MAX_BREACHES := 2

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
## pid -> {"bonks", "caps", "tidied" (weight of mess cleared), "own" (own-chore jobs done)}
var stats: Dictionary = {}
## Cleanup (see Chores), mirrored from the host: pid -> the chore that player
## owns (their character's, or, if someone else picked the same character
## first, one that nobody playing owns); chore -> the pids who own it and are
## cleaning; chore -> owners who've wandered off (their jobs are anyone's).
var specialty: Dictionary = {}
var chore_owners: Dictionary = {}
var idle_owners: Dictionary = {}
var results: Dictionary = {}
var clouds: Array[LitterCloud] = []
var _scan_until: Dictionary = {}  # team -> time
## Last second the countdown clock ticked (the final ten seconds tick).
var _last_tick := -1

# Host only.
var _loaded: Dictionary = {}
var _ko_timers: Dictionary = {}
var _next_debris_id := 1
var _sync_t := 0.0
var _remote_sync_t := 0.0
var _progress_sync_t := 0.0
var _debris_sync_t := 0.0
var _plaster_t: Dictionary = {}  # wall panel index -> when it last shed plaster
var _pictures: Dictionary = {}  # wall panel index -> Array of MessItems hanging on it
var _last_work: Dictionary = {}  # pid -> when they last made cleanup progress
var _idle_time: Dictionary = {}  # pid -> seconds spent idle this cleanup
var _prev_pos: Dictionary = {}  # pid -> where they were last tick (drive-overs sweep the whole step)
var _swat_cd: Dictionary = {}  # Willow pid -> seconds until the next swat
var _thump_cd: Dictionary = {}  # Bass pid -> seconds until the next THUMP
var _carried: Dictionary = {}  # Pepper pid -> MessItem he's carrying home
var _knocked_at: Dictionary = {}  # pid -> when the host last knocked them flying
var _crash_seen: Dictionary = {}  # Vector2i(pid, furniture index) -> when a crash into it was last counted
var _put_down: Dictionary = {}  # Pepper pid -> [MessItem he just put down, when]
var _was_holding: Dictionary = {}  # pid -> held interact last tick (a fresh press drops what Pepper carries)
var _worked: Dictionary = {}  # jobs someone worked last tick
var _credit: Dictionary = {}  # job -> {pid: work done on it}
var _chore_log: Dictionary = {}  # chore -> {"done", "owner", "other"} weight cleared
## Game seconds, for who's been idle (host; stops while the game is paused).
var work_clock := 0.0
## Host: which bot is heading for which job (see BotBrain._cleanup).
var claims: Dictionary = {}
## How long after a picked-up weapon runs out its last shots still count.
const BORROW_GRACE := 1.5
## Things that popped up on the floor (see Pickups): id -> Pickup.
var pickups: Dictionary = {}
## Off for the scripted tests (--pickups=0), so nothing random turns up.
var pickups_on := true
var _next_pickup_id := 1
var _pickup_t := Pickups.WAR_FIRST
## Walls each team has knocked through this war (host; bots stop at MAX_BREACHES).
var breaches: Array[int] = [0, 0]
var _load_timeout := 8.0
var _nav_dirty := false
## Players a bot is standing in for while their controller is gone (online).
var _stand_ins: Dictionary = {}
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
	if _people_on_this_screen() > 1:
		level.position.y -= 14  # room for everyone's cards along the bottom
	war_time = map_info.get("war_time", war_time)
	cleanup_time = map_info.get("cleanup_time", cleanup_time)
	capture_limit = map_info.get("capture_limit", capture_limit)
	if Net.options.has("war"):
		war_time = float(Net.options["war"])
	if Net.options.has("cleanup"):
		cleanup_time = float(Net.options["cleanup"])
	if Net.options.has("captures"):
		capture_limit = int(Net.options["captures"])
	pickups_on = Net.options.get("pickups", "1") != "0"
	_hang_pictures()
	_spawn_players()
	remote = TVRemote.new()
	remote.name = "Remote"
	remote.arena = self
	remote.home = level.home.position
	remote.position = remote.home
	level.entities.add_child(remote)
	hud.setup(self)
	Seats.changed.connect(_on_seats_changed)
	log_event("map %s" % Net.map_id)
	log_event("players %d (%d on this screen)" % [players.size(), local_players().size()])
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
		stats[id] = {"bonks": 0, "caps": 0, "tidied": 0.0, "own": 0}
		if p.is_bot and multiplayer.is_server():
			p.brain = BotBrain.new(p, self)
		elif not p.is_bot and int(info.get("owner", id)) == Net.my_id():
			# Someone on this screen: you (seat 0) or a guest sharing it.
			p.seat = int(info.get("seat", 0))
			p.brain = BotBrain.new(p, self) if Net.options.has("autopilot") else SeatInput.new(p.seat)
		level.entities.add_child(p)


func _people_on_this_screen() -> int:
	var n := 0
	for id: int in Net.roster:
		var entry: Dictionary = Net.roster[id]
		if not entry["bot"] and (id == Net.my_id() or int(entry.get("owner", 0)) == Net.my_id()):
			n += 1
	return n


func local_player() -> Player:
	return players.get(Net.my_id())


## Everyone playing on this screen (you first, then guests), in seat order.
func local_players() -> Array[Player]:
	var out: Array[Player] = []
	for p: Player in players.values():
		if p.seat >= 0:
			out.append(p)
	out.sort_custom(func(a: Player, b: Player) -> bool: return a.seat < b.seat)
	return out


## Can the whole game stop (for the menu, or a dropped controller)? Only when
## everyone playing is on this screen.
func can_pause() -> bool:
	return multiplayer.get_peers().is_empty()


## A controller dropped out or came back. With everyone on this screen the game
## waits for it (see Hud.show_lost); online the host lets a bot fill in, and
## hands the character back as soon as the controller returns.
func _on_seats_changed() -> void:
	if phase == Phase.LOADING or phase == Phase.RESULTS:
		return
	var lost: Array[Player] = []
	for p in local_players():
		var s = Seats.seat(p.seat)
		var is_lost: bool = s != null and s.lost
		if is_lost:
			lost.append(p)
		if not is_lost and _stand_ins.has(p):
			_stand_ins.erase(p)
			p.brain = SeatInput.new(p.seat)
			_forget_bot_plans(p)
		elif is_lost and not _stand_ins.has(p) and not p.brain is BotBrain and not can_pause() \
				and multiplayer.is_server() and not Net.options.has("autopilot"):
			_stand_ins[p] = true
			p.brain = BotBrain.new(p, self)
	hud.show_lost(lost)


## More than one person is playing on this screen.
func shared_screen() -> bool:
	var n := 0
	for p: Player in players.values():
		if p.seat >= 0:
			n += 1
	return n > 1


## The teams of the people looking at this screen.
func screen_teams() -> Array[int]:
	var out: Array[int] = []
	for p in local_players():
		if not out.has(p.team):
			out.append(p.team)
	if out.is_empty():
		out.append(0)
	return out


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
		var owner := int(Net.roster.get(id, {}).get("owner", id))
		if not players[id].is_bot and not _loaded.has(owner):
			return
	_start()


func _start() -> void:
	if phase != Phase.LOADING:
		return
	log_event("everyone loaded after %.1f s" % (8.0 - _load_timeout))
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
	_last_tick = -1
	match phase:
		Phase.COUNTDOWN:
			hud.banner("The parents just left...", "Grab the TV remote!")
			Audio.music("")
			Audio.play("parents_leave")
			# A controller may already have dropped out in the lobby or on the results screen.
			_on_seats_changed()
		Phase.WAR:
			hud.banner("WAR!", "Carry the remote to your base")
			Audio.play("whistle")
			Audio.music("war")
		Phase.WHISTLE:
			hud.banner("CAR IN THE DRIVEWAY!", "Truce! Everyone to their job!")
			for p: Player in players.values():
				p.reset_for_phase()
			Audio.music("", 0.3)
			Audio.play("car_horn")
			# Everyone on this screen: your face and your job. And which room is which.
			for p in local_players():
				ChoreBubble.show_for(p, my_chore(p), time_left + 1.5)
			for r in level.rooms:
				Fx.text(level.entities, Iso.tile_to_local(r.area.get_center()), r.room_name.to_upper(), Color("fff4e3"))
		Phase.CLEANUP:
			hud.banner("CLEAN UP!", "Fix everything before they walk in")
			Audio.play("whistle")
			Audio.music("cleanup")
	hud.on_phase_changed()


## The clock ticks through the last ten seconds of the war and the cleanup.
func _tick_clock() -> void:
	if phase != Phase.WAR and phase != Phase.CLEANUP:
		return
	var sec := ceili(time_left)
	if sec < 1 or sec > 10 or (_last_tick >= 0 and sec >= _last_tick):
		return
	_last_tick = sec
	Audio.play("tick", 0.0 if sec <= 3 else -4.0, 1.25 if sec <= 3 else 1.0)


# ============================================================== main loop

func _physics_process(delta: float) -> void:
	if phase in [Phase.COUNTDOWN, Phase.WAR, Phase.WHISTLE, Phase.CLEANUP]:
		time_left = maxf(0.0, time_left - delta)
	if phase == Phase.WAR:
		level.room.clock_progress = 1.0 - time_left / maxf(war_time, 1.0)
	elif phase == Phase.CLEANUP:
		level.room.clock_progress = 1.0 - time_left / maxf(cleanup_time, 1.0)
	_tick_clock()
	if not multiplayer.is_server():
		return
	work_clock += delta

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
			_tick_gags(delta)
			_tick_pickups(delta)
			_tick_navigation(delta)
			if time_left <= 0.0 or scores.max() >= capture_limit:
				_end_war()
		Phase.WHISTLE:
			if time_left <= 0.0:
				_begin_cleanup()
		Phase.CLEANUP:
			_tick_remote(delta)
			_tick_jobs(delta)
			_tick_pickups(delta)
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
	_clear_pickups()
	_assign_chores()
	# The first cleanup of the evening gets a little longer to read the jobs.
	_set_phase(Phase.WHISTLE, whistle_time + (2.0 if Net.matches_played == 0 else 0.0))
	_ko_timers.clear()
	_cl_tv.rpc(winner)
	log_event("war over %d-%d" % [scores[0], scores[1]])


func _begin_cleanup() -> void:
	mess_baseline = mess_remaining()
	_cl_baseline.rpc(mess_baseline)
	var knocked := level.mess_items.filter(func(i: MessItem) -> bool: return i.knocked).size()
	log_event("cleanup starts: mess=%.1f (%d items knocked, %d debris)" % [mess_baseline, knocked, debris.size()])
	var kinds := {}
	for d: Debris in debris.values():
		kinds[d.kind] = int(kinds.get(d.kind, 0)) + 1
	log_event("  debris by kind %s" % str(kinds))
	var totals := chore_totals()
	for c: int in totals:
		log_event("  chore %s: %d jobs, weight %.1f, owner %s" % [Chores.Chore.keys()[c], totals[c][0], totals[c][1],
			_owner_names(c)])
	var now := work_clock
	for pid: int in players:
		_last_work[pid] = now
		_prev_pos[pid] = players[pid].position
	_pickup_t = Pickups.CLEANUP_FIRST
	_set_phase(Phase.CLEANUP, cleanup_time)


func _finish() -> void:
	_clear_pickups()
	var left := chore_totals()
	for c: int in Chores.Chore.values():
		var done: Dictionary = _chore_log.get(c, {})
		if done.is_empty() and not left.has(c):
			continue
		log_event("  chore %s: done %d (owner %.1f, others %.1f), left %d (%.1f)" % [Chores.Chore.keys()[c],
			done.get("done", 0), done.get("owner", 0.0), done.get("other", 0.0), left.get(c, [0, 0.0])[0], left.get(c, [0, 0.0])[1]])
	for pid: int in players:
		log_event("  %s (%s): tidied %.1f, %d own jobs, idle %.0f s" % [players[pid].display_name,
			Chores.Chore.keys()[specialty.get(pid, 0)], stats[pid]["tidied"], stats[pid]["own"], _idle_time.get(pid, 0.0)])
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
	Audio.music("", 0.3)
	Audio.play(["spotless", "fine", "grounded"][verdict])
	Audio.music_after("menu", 3.5)
	log_event("results tidy=%.2f verdict=%s winner=%d score=%d-%d" % [tidy, Verdict.keys()[verdict], winner, scores[0], scores[1]])
	hud.show_results(results)
	Net.matches_played += 1
	if Net.is_host() and Net.matches_played <= int(Net.options.get("rematches", "0")):
		get_tree().create_timer(2.0).timeout.connect(Net.start_match)


## Total weight of everything still out of place (0 = spotless).
func mess_remaining() -> float:
	var m := 0.0
	for totals: Array in chore_totals().values():
		m += totals[1]
	return m


## Everything still to do, by chore: {chore: [jobs, weight]}. A repair chain
## counts all its steps still to come, so owners can see work on its way.
func chore_totals() -> Dictionary:
	var out := {}
	var add := func(c: int, w: float) -> void:
		var t: Array = out.get_or_add(c, [0, 0.0])
		t[0] += 1
		t[1] += w
	for d: Debris in debris.values():
		add.call(d.chore, d.weight)
	for item in level.mess_items:
		if item.knocked:
			add.call(item.chore(), item.weight())
	for f in level.furniture:
		var c := f.chain()
		for k in range(f.step, c.size()):
			add.call(c[k], f.step_weight(c[k]))
	if remote.state != TVRemote.State.HOME:
		add.call(Chores.Chore.REMOTE, 1.0)
	return out


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
			var next := level.clamp_to_floor(r.position + r.vel * delta)
			if not level.wall_between(r.position, next).is_empty():
				# Thrown into a wall: it drops on this side.
				r.position = level.clip(r.position, next)
				r.timer = 0.0
			else:
				r.position = next
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
			if p.is_ko or p.captured_by != 0 or (p.pid == r.thrower and r.grace > 0.0) or _carried.has(p.pid):
				continue  # (Pepper can't hold the remote and something else in his mouth.)
			var d := Iso.fdist(p.position, r.position)
			if d < best_d and level.wall_between(p.position, r.position).is_empty():
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
	stats[c.pid]["tidied"] += 1.0
	_last_work[c.pid] = work_clock
	_cl_event.rpc("%s put the remote back!" % c.display_name, Color("8ff0a4"))


@rpc("authority", "call_local", "reliable")
func _cl_scored(pid: int, team: int, new_scores: Array) -> void:
	scores = [int(new_scores[0]), int(new_scores[1])]
	if level.tv:
		level.tv.channel = team
	level.bases[team].pulse = 1.0
	Audio.play("score")
	var who: String = players[pid].display_name if players.has(pid) else "Someone"
	hud.banner("%s SCORE!" % Roster.TEAM_NAMES[team].to_upper(), "%s changed the channel" % who, Roster.TEAM_COLORS[team])
	log_event("score team=%d by=%d -> %d-%d" % [team, pid, scores[0], scores[1]])


@rpc("authority", "call_local", "unreliable_ordered")
func _cl_remote(state: int, carrier: int, pos: Vector2, pz: float, hold: float) -> void:
	remote.apply_net(state, carrier, pos, pz)
	remote.apply_hold(hold)
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
		var dealt := float(attacker.ability_spec(ability).get("damage", 0))
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
	if ability == 4 and not _borrow_ok(a):
		return
	var spec := a.ability_spec(ability)
	var kind := int(spec.get("kind", -1))
	# Flyers are out of reach of slams and suction.
	if ability == 1 and t.data.get("flying", false) and (kind == Roster.Special.SLAM or kind == Roster.Special.PULL):
		return
	var d := dir.normalized() if dir.length() > 0.01 else Vector2.RIGHT
	var knock_scale := 1.0
	if ability == 1 and kind == Roster.Special.PULL:
		d = Iso.to_floor(a.position - t.position).normalized()
		knock_scale = clampf(Iso.fdist(a.position, t.position) / float(spec["radius"]), 0.35, 1.0)
	elif ability == 3 and spec.get("effect", "") == "pull":
		# Reeled in under the claw: close targets get a gentler tug, so they don't fly past.
		knock_scale = clampf(Iso.fdist(a.position, t.position) / float(spec["range"]), 0.35, 1.0)
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
	var effect := String(spec.get("effect", ""))
	if effect == "pull":
		d = -d  # yanked toward the attacker
	# Bubble wrap soaks it up first.
	if t.shield > 0 and damage > 0.0:
		var soak := mini(t.shield, roundi(damage))
		t.shield -= soak
		damage -= soak
		_cl_shield.rpc(t.pid, t.shield)
	t.hp = maxi(0, t.hp - roundi(damage))
	if effect == "drain" and not a.is_ko:
		var healed := mini(a.max_hp, a.hp + roundi(damage * float(spec.get("effect_value", 0.5))))
		if healed > a.hp:
			a.hp = healed
			_cl_heal.rpc(a.pid, a.hp)
	if effect == "steal" and remote.state == TVRemote.State.CARRIED and remote.carrier_pid == t.pid and not a.is_ko:
		# Snatched right out of their paws (or grabber).
		remote.carrier_pid = a.pid
		remote.hold = 0.0
		_cl_event.rpc("%s snatched the remote from %s!" % [a.display_name, t.display_name], Roster.TEAM_COLORS[a.team])
	elif remote.carrier_pid == t.pid and remote.state == TVRemote.State.CARRIED:
		remote.hold = 0.0
		# A dog never lets go of a bone, though.
		if t.data.get("butterfingers", false) and t.hp > 0 and not t.has_bone():
			_drop_remote(t.position)
			_cl_event.rpc("%s dropped the remote! (butterfingers)" % t.display_name, Roster.TEAM_COLORS[t.team])
	var hop := float(spec.get("effect_value", 0.0)) if effect == "knockup" else 0.0
	if knock >= Player.TUMBLE_SPEED:
		_knocked_at[t.pid] = work_clock  # (so a crash report that follows is believable)
	_cl_damaged.rpc(t.pid, t.hp, d * knock, stun, ambushed, hop)
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
func _cl_damaged(tid: int, new_hp: int, knock: Vector2, stun: float, ambushed: bool, hop: float) -> void:
	if players.has(tid):
		players[tid].on_damaged(new_hp, knock, stun, ambushed, hop)


@rpc("authority", "call_local", "reliable")
func _cl_heal(pid: int, new_hp: int) -> void:
	if players.has(pid):
		players[pid].heal(new_hp)


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
					_cl_buff.rpc(ally.pid, float(sp["speed_mult"]), float(sp["duration"]), ally.hp, "+HYPE")


@rpc("authority", "call_local", "reliable")
func _cl_buff(pid: int, mult: float, duration: float, new_hp: int, label: String) -> void:
	if players.has(pid):
		players[pid].apply_buff(mult, duration, new_hp, label)


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
	force = minf(force, 400.0)
	if item.can_be_knocked_by(force):
		_knock(item, dir, force)


## Players who get knocked flying (or dash) into things knock them over.
func _tick_knockovers() -> void:
	for p: Player in players.values():
		var clumsy: bool = p.data.get("clumsy", false) and p.moving
		if p.is_ko or p.data.get("flying", false) or not (p.tumbling or p.dashing or clumsy):
			continue
		var force := 260.0 if p.tumbling else 120.0
		for item in level.mess_items:
			if not item.knocked and Iso.fdist(p.position, item.position) <= 12.0 and item.can_be_knocked_by(force) \
					and level.wall_between(p.position, item.position).is_empty():
				_knock(item, Iso.to_floor(item.position - p.position), force)


## Knocks a thing over. A hard hit flings a light thing 2-4 tiles (a stray,
## for Pepper to carry home); whatever was in it spills out on the floor.
func _knock(item: MessItem, dir: Vector2, force: float = 0.0) -> void:
	var d := dir.normalized() if dir.length() > 0.01 else Vector2.RIGHT
	var fling := 16.0
	if item.high:
		fling = 6.0  # it just drops off the wall (or the counter)
	elif force >= MessItem.HEAVY_FORCE and not item.heavy:
		fling = randf_range(2.0, 4.0) * TILE
	var target := level.clip(item.home, level.clamp_to_floor(item.home + Iso.to_screen(d * fling), 0.6))
	if not item.high:
		# Where someone can get at it (not on top of the couch).
		var reach := level.walkable(target)
		if level.wall_between(target, reach).is_empty():
			target = reach
	_cl_mess_state.rpc(item.index, true, target - item.home, 0)
	var spills: Array = Chores.SPILLS.get(item.spill_sprite, Chores.SPILLS.get(item.sprite_name, []))
	spills = spills + Chores.SCATTERS.get(item.sprite_name, [])
	for kind: String in spills:
		var at := item.home + Iso.to_screen(d.rotated(randf_range(-0.9, 0.9)) * randf_range(8.0, 18.0))
		_spawn_debris(kind, level.clip(item.home, at))


@rpc("authority", "call_local", "reliable")
func _cl_mess_state(idx: int, knocked: bool, offset: Vector2, carrier: int) -> void:
	var item := level.mess_items[idx]
	var was_knocked := item.knocked
	var was_carried := item.carrier != 0
	item.apply_state(knocked, offset, 0.0, 0, carrier)
	if knocked and not was_knocked:
		log_event("knocked %s" % item.name)
	if carrier != 0 and not was_carried:
		Audio.play_at("c_fetch", level.entities, item.position)
	elif knocked != was_knocked:
		Audio.play_at("knock" if knocked else "tidy", level.entities, item.position)


@rpc("authority", "call_local", "unreliable_ordered")
func _cl_mess_progress(idx: int, progress: float, helpers: int, owner_on: bool) -> void:
	var item := level.mess_items[idx]
	if item.knocked:
		item.owner_working = owner_on
		item.apply_state(true, item.offset, progress, helpers, item.carrier)


## Pictures hang on the nearest wall panel: any hit to that panel knocks them down.
func _hang_pictures() -> void:
	for item in level.mess_items:
		if item.hang <= 0.0:
			continue
		var best: WallPanel = null
		var best_d := 14.0
		for panel in level.wall_panels:
			var dist := panel.distance_to(item.home)
			if dist < best_d:
				best = panel
				best_d = dist
		if best:
			_pictures.get_or_add(best.index, []).append(item)
			item.wall_dir = Vector2(1, -0.5) if best.run.plane == WallRun.Axis.I else Vector2(1, 0.5)
			item.queue_redraw()


func _drop_pictures(panel: WallPanel, dir: Vector2) -> void:
	for item: MessItem in _pictures.get(panel.index, []):
		if not item.knocked:
			_knock(item, dir)


# ================================================================= cleanup

## Who owns what this cleanup (host, at the whistle). Everyone owns their
## character's chore. Someone whose character was already picked takes the
## biggest chore nobody playing owns instead (or shares their own, if there's none).
func _assign_chores() -> void:
	specialty.clear()
	var totals := chore_totals()
	# People first (in seat order), then bots: if a bot picked the same
	# character as a person, the bot is the one who takes another chore.
	var ids: Array = players.keys()
	ids.sort_custom(func(a: int, b: int) -> bool:
		var pa: Player = players[a]
		var pb: Player = players[b]
		if pa.is_bot != pb.is_bot:
			return not pa.is_bot
		return a < b)
	var taken := {}
	var spare: Array[int] = []
	for pid: int in ids:
		var c := Chores.owned_by(players[pid].char_id)
		if c == Chores.Chore.NONE:
			continue
		if taken.has(c):
			spare.append(pid)
		else:
			specialty[pid] = c
			taken[c] = true
	for pid in spare:
		var best := Chores.owned_by(players[pid].char_id)
		var best_w := 0.0
		for c: int in Chores.OWNER:
			var w: float = totals.get(c, [0, 0.0])[1]
			if not taken.has(c) and w > best_w:
				best = c
				best_w = w
		specialty[pid] = best
		taken[best] = true
	var now := work_clock
	for pid: int in players:
		_last_work[pid] = now
	_update_owners(true)


## Owners who haven't got anything done for a while stop counting: their
## chore becomes everyone's until they get back to it.
func _update_owners(force: bool = false) -> void:
	var now := work_clock
	var owners := {}
	var idle := {}
	for pid: int in specialty:
		if not players.has(pid):
			continue
		var busy := now - float(_last_work.get(pid, now)) < Chores.IDLE_TIME
		(owners if busy else idle).get_or_add(specialty[pid], []).append(pid)
	if force or owners != chore_owners or idle != idle_owners:
		_cl_chores.rpc(owners, idle, specialty)


@rpc("authority", "call_local", "reliable")
func _cl_chores(owners: Dictionary, idle: Dictionary, spec: Dictionary) -> void:
	chore_owners = owners
	idle_owners = idle
	specialty = spec
	if phase == Phase.CLEANUP:
		log_event("chores %s idle %s" % [str(owners), str(idle)])
	hud.on_chores_changed()


## The owner(s) of a chore, for the logs.
func _owner_names(c: int) -> String:
	var names: Array[String] = []
	for pid: int in specialty:
		if specialty[pid] == c and players.has(pid):
			names.append(players[pid].display_name)
	return ", ".join(names) if not names.is_empty() else "nobody"


## How many jobs are left in each room (for the parents' verdict), most first.
func leftovers_by_room() -> Dictionary:
	var counts := {}
	var add := func(pos: Vector2) -> void:
		var r := level.room_at(pos)
		var n := r.room_name if r else "Hallway"
		counts[n] = int(counts.get(n, 0)) + 1
	for d: Debris in debris.values():
		add.call(d.position)
	for item in level.mess_items:
		if item.knocked:
			add.call(item.position)
	for f in level.furniture:
		if f.current_chore() != Chores.Chore.NONE:
			add.call(f.position)
	var names := counts.keys()
	names.sort_custom(func(a: String, b: String) -> bool: return counts[a] > counts[b])
	var out := {}
	for n: String in names:
		out[n] = counts[n]
	return out


## The face on a chore's jobs: whoever owns it now, or the grey hand.
func chore_face(c: int) -> String:
	var owners: Array = chore_owners.get(c, [])
	if owners.is_empty() or not players.has(owners[0]):
		return "face_anyone"
	return "face_" + String(players[owners[0]].char_id)


## The seat colours of the people on this screen who own a chore (for job badges).
func local_owner_colors(c: int) -> Array[Color]:
	var out: Array[Color] = []
	for pid: int in chore_owners.get(c, []):
		var p: Player = players.get(pid)
		if p and p.seat >= 0:
			out.append(Seats.color(p.seat) if shared_screen() else Color("8ff0a4"))
	return out


## The chore `p` owns (Chores.Chore.NONE for none).
func my_chore(p: Player) -> int:
	return specialty.get(p.pid, Chores.Chore.NONE)


func _tick_jobs(delta: float) -> void:
	_progress_sync_t += delta
	var send := _progress_sync_t >= 0.1
	if send:
		_progress_sync_t = 0.0
	_tick_owner_moves(delta)
	# Everyone holding interact works the one job nearest them (their own chore first).
	var crews := {}
	for p: Player in players.values():
		if p.interacting and not p.is_ko and p.captured_by == 0:
			var job := _job_for(p)
			if job:
				crews.get_or_add(job, []).append(p)
	for job in _worked:  # (floor mess cleaned last tick is freed by now)
		if is_instance_valid(job) and not crews.has(job):
			_set_progress(job, progress_of(job), 0, false, true)
	_worked = {}
	for job: Object in crews:
		_worked[job] = true
		_work(job, crews[job], delta, send)
	for pid: int in specialty:
		if pid in idle_owners.get(specialty[pid], []):
			_idle_time[pid] = float(_idle_time.get(pid, 0.0)) + delta
	_update_owners()


## Can `p` reach something at `at` from where they stand (no wall in between,
## except `own`: the wall panel being worked on)?
func _reachable(p: Player, at: Vector2, own: Furniture = null) -> bool:
	var hit := level.wall_between(p.position, at)
	return hit.is_empty() or hit["panel"] == own


## The job `p` works on while holding interact, or null: the one their bot
## brain picked, or else the nearest (their own chore first).
func _job_for(p: Player) -> Object:
	var focus = p.focus_job
	if is_open(focus) and in_reach(p, focus) and _reachable(p, (focus as Node2D).position, focus as Furniture):
		return focus
	var mine := my_chore(p)
	var best: Object = null
	var best_score := INF
	for d: Debris in debris.values():
		var dist := Iso.fdist(p.position, d.position)
		var score := dist + (0.0 if d.chore == mine else 100.0)
		if dist <= DEBRIS_RADIUS and score < best_score and _reachable(p, d.position):
			best = d
			best_score = score
	for item in level.mess_items:
		if not item.knocked or item.carrier != 0:
			continue
		var dist := Iso.fdist(p.position, item.position)
		var score := dist + (0.0 if item.chore() == mine else 100.0)
		if dist <= FIX_RADIUS and score < best_score and _reachable(p, item.position):
			best = item
			best_score = score
	for f in level.furniture:
		var c := f.current_chore()
		if c == Chores.Chore.NONE:
			continue
		var dist := f.distance_to(p.position)
		var score := maxf(dist, 0.0) + (0.0 if c == mine else 100.0)
		if dist <= FIX_RADIUS and score < best_score and _reachable(p, f.position, f):
			best = f
			best_score = score
	return best


## Every job still to do right now (floor mess, knocked-over things, furniture
## and walls on their current repair step).
func open_jobs() -> Array[Object]:
	var out: Array[Object] = []
	out.append_array(debris.values())
	for item in level.mess_items:
		if item.knocked and item.carrier == 0:
			out.append(item)
	for f in level.furniture:
		if f.current_chore() != Chores.Chore.NONE:
			out.append(f)
	return out


## Is this job still waiting to be done? (Floor mess may have been freed already.)
func is_open(job) -> bool:
	if not is_instance_valid(job):
		return false
	if job is Debris:
		return debris.has(job.debris_id)
	if job is MessItem:
		return job.knocked and job.carrier == 0
	return (job as Furniture).current_chore() != Chores.Chore.NONE


## Where the little arrow on a local player's ring points in cleanup: their
## nearest job, or once those are all done, the nearest job anyone can do (or
## a two-hand job with one helper already waiting). {"at", "own"}, or {} for none.
func pointer_for(p: Player) -> Dictionary:
	var mine := my_chore(p)
	var best := {}
	var best_d := INF
	var other := {}
	var other_d := INF
	for job in open_jobs():
		var c := chore_of(job)
		var at: Vector2 = (job as Node2D).position
		var d := Iso.fdist(p.position, at)
		if c == mine:
			if d < best_d:
				best = {"at": at, "own": true}
				best_d = d
		elif d < other_d and (chore_owners.get(c, []).is_empty()
				or (Chores.needs_two(c, chore_owners) and int(job.get("helpers")) == 1)):
			other = {"at": at, "own": false}
			other_d = d
	return best if not best.is_empty() else other


## Is `p` close enough to work on `job` (holding interact)?
func in_reach(p: Player, job: Object) -> bool:
	if job is Debris:
		return Iso.fdist(p.position, job.position) <= DEBRIS_RADIUS
	if job is MessItem:
		return Iso.fdist(p.position, job.position) <= FIX_RADIUS
	return (job as Furniture).distance_to(p.position) <= FIX_RADIUS


## Does this owner clean their chore their own way (driving over it, running
## into it, THUMPing), rather than holding interact at each job?
func has_owner_move(p: Player) -> bool:
	var c := my_chore(p)
	return c == Chores.owned_by(p.char_id) and c in [Chores.Chore.FLOOR, Chores.Chore.CLUTTER, Chores.Chore.FETCH, Chores.Chore.STAIN]


## What Pepper is carrying home in his mouth (host), or null.
func carried_by(p: Player) -> MessItem:
	return _carried.get(p.pid)


func chore_of(job: Object) -> int:
	if job is Debris:
		return job.chore
	if job is MessItem:
		return job.chore()
	return (job as Furniture).current_chore()


func progress_of(job: Object) -> float:
	if job is Debris:
		return job.progress
	if job is MessItem:
		return job.progress
	return (job as Furniture).rebuild


## Seconds of work (at rate 1) and tidiness weight of a job.
func time_of(job: Object) -> float:
	if job is Debris:
		return job.clean_time
	if job is MessItem:
		return job.job_time()
	var f := job as Furniture
	return f.step_time(f.current_chore())


func weight_of(job: Object) -> float:
	if job is Debris:
		return job.weight
	if job is MessItem:
		return job.weight()
	var f := job as Furniture
	return f.step_weight(f.current_chore())


## A turbo tool (see Pickups): faster at that one chore for a while.
func _turbo(p: Player, c: int) -> float:
	return Pickups.TURBO_RATE if p.turbo_t > 0.0 and p.turbo_chore == c else 1.0


## ...and an owner's own move reaches further.
func _reach(p: Player) -> float:
	return Pickups.TURBO_REACH if _turbo(p, my_chore(p)) > 1.0 else 1.0


## Bass's Cleaning Playlist: everyone near him works a little faster.
func _playlist(p: Player) -> float:
	for q: Player in players.values():
		if q.data.get("playlist", false) and not q.is_ko and Iso.fdist(q.position, p.position) <= Chores.PLAYLIST_RADIUS:
			return Chores.PLAYLIST_RATE
	return 1.0


func _work(job: Object, crew: Array, delta: float, send: bool) -> void:
	var c := chore_of(job)
	var owner_on := false
	var helpers := 0
	var rates := {}
	var rate := 0.0
	for p: Player in crew:
		var own := my_chore(p) == c
		owner_on = owner_on or own
		helpers += 0 if own else 1
		rates[p.pid] = Chores.rate(own, c, chore_owners) * _playlist(p) * _turbo(p, c)
		rate += rates[p.pid]
	# Heavy and high jobs need two pairs of helping hands while their owner's about.
	if not owner_on and helpers < 2 and Chores.needs_two(c, chore_owners):
		rate = 0.0
	var progress := progress_of(job)
	if rate > 0.0:
		progress += delta * rate / time_of(job)
		var credit: Dictionary = _credit.get_or_add(job, {})
		for pid: int in rates:
			credit[pid] = float(credit.get(pid, 0.0)) + rates[pid] * delta
			_last_work[pid] = work_clock  # making progress, so not idle
	if progress >= 1.0:
		_finish_job(job, owner_on, helpers, send)
	else:
		_set_progress(job, progress, helpers, owner_on, send)


func _set_progress(job: Object, progress: float, helpers: int, owner_on: bool, send: bool) -> void:
	if job is Debris:
		job.progress = progress
		if send:
			_cl_debris_progress.rpc(job.debris_id, progress, owner_on)
	elif job is MessItem:
		job.progress = progress
		job.helpers = helpers
		if send:
			_cl_mess_progress.rpc(job.index, progress, helpers, owner_on)
	else:
		var f := job as Furniture
		f.rebuild = progress
		f.helpers = helpers
		if send:
			_cl_furniture_progress.rpc(f.index, progress, helpers, owner_on)


func _finish_job(job: Object, owner_on: bool, helpers: int, send: bool) -> void:
	# A mended wall only turns solid again once nobody is standing in the gap.
	if job is WallPanel and job.wrecked and _body_in(job):
		_set_progress(job, 1.0, helpers, owner_on, send)
		return
	var c := chore_of(job)
	_give_credit(c, weight_of(job), _credit.get(job, {}))
	_credit.erase(job)
	if job is Debris:
		_cl_debris_remove.rpc(job.debris_id, How.OWNER if owner_on else How.HELPED)
	elif job is MessItem:
		_cl_mess_state.rpc(job.index, false, Vector2.ZERO, 0)
	else:
		_next_step(job as Furniture)


## Moves a piece of furniture on to the next step of its repair (see
## Furniture.chain): a wreck stood back up, a new wall panel in, or good as new.
func _next_step(f: Furniture) -> void:
	var chain := f.chain()
	if f is WallPanel and f.wrecked:
		_cl_furniture_state.rpc(f.index, 1.0, false, 0.0, 0, 1)
	elif f.step + 1 < chain.size():
		_cl_furniture_state.rpc(f.index, f.hp / f.max_hp, f.wrecked, 0.0, 0, f.step + 1)
	else:
		_cl_furniture_state.rpc(f.index, 1.0, false, 0.0, 0, 0)
		if chain.size() > 1:
			_cl_event.rpc("The %s is good as new!" % _furniture_name(f), Color("8ff0a4"))


## Shares out the credit for a finished job by how much each person did.
func _give_credit(c: int, weight: float, shares: Dictionary) -> void:
	var total := 0.0
	for pid: int in shares:
		total += shares[pid]
	var entry: Dictionary = _chore_log.get_or_add(c, {"done": 0, "owner": 0.0, "other": 0.0})
	entry["done"] += 1
	var now := work_clock
	for pid: int in shares:
		var part: float = weight * shares[pid] / total if total > 0.0 else weight
		var own: bool = specialty.get(pid, Chores.Chore.NONE) == c
		entry["owner" if own else "other"] += part
		if stats.has(pid):
			stats[pid]["tidied"] += part
			if own and part >= weight * 0.5:
				stats[pid]["own"] += 1
		_last_work[pid] = now


# ============================================================ owner moves

## The things only the owner can do, without pressing anything (Zoomba,
## Willow, Pepper) or with one button for a whole area (Bass). Moves are
## checked along the whole step since last tick, so nothing gets skipped.
func _tick_owner_moves(delta: float) -> void:
	for pid: int in _carried.keys():
		if not players.has(pid):
			_drop_carried(pid, _carried[pid].position)
	for p: Player in players.values():
		var from: Vector2 = _prev_pos.get(p.pid, p.position)
		_prev_pos[p.pid] = p.position
		var pressed: bool = p.interacting and not _was_holding.get(p.pid, false)
		_was_holding[p.pid] = p.interacting
		# Pressing the button with something in your mouth puts it down.
		if pressed and _carried.has(p.pid):
			_drop_carried(p.pid, p.position)
			continue
		if p.is_ko or p.captured_by != 0:
			continue
		var c := my_chore(p)
		if c == Chores.Chore.NONE or c != Chores.owned_by(p.char_id):
			continue  # spare hands hold interact, like everyone else
		match c:
			Chores.Chore.FLOOR:
				_vacuum(p, from)
			Chores.Chore.CLUTTER:
				_swat(p, from, delta)
			Chores.Chore.FETCH:
				_fetch(p, from)
			Chores.Chore.STAIN:
				_thump(p, delta)


## Zoomba hoovers up floor mess just by driving over it.
func _vacuum(p: Player, from: Vector2) -> void:
	for d: Debris in debris.values():
		if d.chore == Chores.Chore.FLOOR and Iso.segment_fdist(d.position, from, p.position) <= Chores.VACUUM_RADIUS * _reach(p) \
				and _reachable(p, d.position):
			_clear_debris(d, How.VACUUM, p)


## Willow runs over clutter and bats it under the nearest couch.
func _swat(p: Player, from: Vector2, delta: float) -> void:
	_swat_cd[p.pid] = maxf(0.0, float(_swat_cd.get(p.pid, 0.0)) - delta)
	if _swat_cd[p.pid] > 0.0:
		return
	var best: Debris = null
	var best_d := Chores.SWAT_RADIUS * _reach(p)
	for d: Debris in debris.values():
		var dist := Iso.segment_fdist(d.position, from, p.position)
		if d.chore == Chores.Chore.CLUTTER and dist <= best_d and _reachable(p, d.position):
			best = d
			best_d = dist
	if best:
		_swat_cd[p.pid] = Chores.SWAT_TIME / _reach(p)
		_clear_debris(best, How.SWAT, p)


## Pepper runs into knocked-over things: close to home, they pop straight back
## up; further away, he carries them home in his mouth (and drops them in place).
func _fetch(p: Player, from: Vector2) -> void:
	if _carried.has(p.pid):
		var held: MessItem = _carried[p.pid]
		_last_work[p.pid] = work_clock  # carrying it home is work too
		# Its place, or as close to it as anyone can get (it may live on top of something).
		if Iso.fdist(p.position, held.home) <= Chores.DELIVER_RADIUS \
				or Iso.fdist(p.position, level.walkable(held.home)) <= 6.0:
			_carried.erase(p.pid)
			_give_credit(Chores.Chore.FETCH, held.weight(), {p.pid: 1.0})
			_cl_mess_state.rpc(held.index, false, Vector2.ZERO, 0)
		return
	if remote.state == TVRemote.State.CARRIED and remote.carrier_pid == p.pid:
		return
	var dropped: Array = _put_down.get(p.pid, [null, -99.0])
	for item in level.mess_items:
		if not item.knocked or item.carrier != 0 or item.chore() != Chores.Chore.FETCH:
			continue
		if item == dropped[0] and work_clock - float(dropped[1]) < 1.5:
			continue  # he's only just put it down
		if Iso.segment_fdist(item.position, from, p.position) > Chores.FETCH_RADIUS * _reach(p) or not _reachable(p, item.position):
			continue
		if item.stray():
			_carried[p.pid] = item
			_last_work[p.pid] = work_clock
			_cl_mess_state.rpc(item.index, true, item.offset, p.pid)
		else:
			_give_credit(Chores.Chore.FETCH, item.weight(), {p.pid: 1.0})
			_cl_mess_state.rpc(item.index, false, Vector2.ZERO, 0)
		return


## Pepper went home with something in his mouth: it stays where he was.
func _drop_carried(pid: int, at: Vector2) -> void:
	var item: MessItem = _carried[pid]
	_carried.erase(pid)
	_put_down[pid] = [item, work_clock]
	_cl_mess_state.rpc(item.index, true, level.clamp_to_floor(at) - item.home, 0)


## Bass holds interact to THUMP: every stain nearby shakes loose, through walls.
func _thump(p: Player, delta: float) -> void:
	_thump_cd[p.pid] = maxf(0.0, float(_thump_cd.get(p.pid, 0.0)) - delta)
	if not p.interacting or _thump_cd[p.pid] > 0.0:
		return
	var hit: Array[Debris] = []
	for d: Debris in debris.values():
		if d.chore == Chores.Chore.STAIN and Iso.fdist(d.position, p.position) <= Chores.THUMP_RADIUS * _reach(p):
			hit.append(d)
	if hit.is_empty():
		return
	_thump_cd[p.pid] = Chores.THUMP_TIME / _reach(p)
	_cl_pulse.rpc(p.pid, Chores.THUMP_RADIUS * _reach(p))
	for d in hit:
		_clear_debris(d, How.THUMP, p)


func _clear_debris(d: Debris, how: How, by: Player) -> void:
	_credit.erase(d)
	_give_credit(d.chore, d.weight, {by.pid: 1.0})
	_cl_debris_remove.rpc(d.debris_id, how)


@rpc("authority", "call_local", "unreliable")
func _cl_pulse(pid: int, radius: float) -> void:
	var p: Player = players.get(pid)
	if p == null:
		return
	Fx.ring(level.entities, p.position, radius, Color("7fe6ff"), false)
	Audio.play_at("c_thump", level.entities, p.position)


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
			for k in 2:
				_spawn_debris("litter", at + Iso.to_screen(Vector2.from_angle(PI * k + randf()) * 16.0))
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
				if d < best_d and level.wall_between(p.position, t.position).is_empty():
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
					_cl_heal.rpc(t.pid, t.hp)
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
			if d > float(g["radius"]) or not level.wall_between(z.position, t.position).is_empty():
				continue
			if d <= 12.0:
				_capture(t, z, Player.Capture.SWALLOWED, float(g["swallow_time"]))
			elif d <= float(g["radius"]) and pulse:
				var toward := Iso.to_floor(z.position - t.position).normalized()
				_knocked_at[t.pid] = work_clock
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
				_knock(item, Iso.to_floor(item.position - at), 300.0)
		for f in level.furniture:
			if not f is WallPanel and f.can_be_damaged() and Iso.fdist(f.position, at) <= r + f.reach():
				_damage_furniture(f, float(g["demolition"]), p)
		# One strike breaks one wall panel at most (it comes through the roof).
		var wall := _nearest_wall(at, r)
		if wall:
			_damage_furniture(wall, float(g["demolition"]), p)
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
	Audio.play_at("poof_big", level.entities, pos)
	var alive: Array[LitterCloud] = [c]
	for old in clouds:
		if is_instance_valid(old):
			alive.append(old)
	clouds = alive


@rpc("authority", "call_local", "reliable")
func _cl_satellite(pos: Vector2, delay: float, radius: float) -> void:
	Fx.satellite(level.entities, pos, radius, delay)
	Audio.play_at("sat_lock", level.entities, pos)
	Audio.play_later("sat_beam", delay, level.entities, pos)


@rpc("authority", "call_local", "reliable")
func _cl_scan(team: int, duration: float) -> void:
	_scan_until[team] = _now() + duration
	var teams := screen_teams()
	if teams.has(team):
		var title := "SATELLITE SCAN" if teams.size() == 1 else "ROBOTS' SATELLITE SCAN" if team == 1 else "PETS' SATELLITE SCAN"
		hud.banner(title, "Every hidden enemy is on screen", Roster.TEAM_COLORS[team])


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

## `by` hit `f` with ability `ability` (see Roster.ability), or -1: they were
## knocked flying into it. Walls hear about every hit, even ones too weak to
## hurt them (they still knock the pictures down).
func report_furniture_hit(f: Furniture, amount: float, by: Player, ability: int) -> void:
	if phase != Phase.WAR or (ability >= 0 and not f is WallPanel and (amount <= 0.0 or not f.can_be_damaged())):
		return
	if multiplayer.is_server():
		_srv_furniture_hit(f.index, amount, by.pid, ability)
	else:
		_srv_furniture_hit.rpc_id(1, f.index, amount, by.pid, ability)


## The host checks the hit could really have happened: the sender plays that
## character, it's close enough, and it's no harder than that ability can hit.
@rpc("any_peer", "call_remote", "reliable")
func _srv_furniture_hit(idx: int, amount: float, pid: int, ability: int) -> void:
	if not multiplayer.is_server() or phase != Phase.WAR or idx < 0 or idx >= level.furniture.size():
		return
	var by: Player = players.get(pid)
	if by == null or by.get_multiplayer_authority() != _sender():
		return
	var f := level.furniture[idx]
	if Iso.fdist(by.position, f.position) > 420.0:
		return
	if ability < 0:
		# A crash: only right after the host knocked them flying, right up
		# against it, and once per piece per moment.
		var key := Vector2i(pid, idx)
		if work_clock - float(_knocked_at.get(pid, -99.0)) > 2.0 or f.distance_to(by.position) > Player.BODY_RADIUS + 16.0 \
				or work_clock - float(_crash_seen.get(key, -99.0)) < 0.3:
			return
		_crash_seen[key] = work_clock
		_scuff(by.position)  # a crash leaves a mark on the floor
	if f is WallPanel:
		_drop_pictures(f, Iso.to_floor(f.position - by.position))
	if ability == 4 and not _borrow_ok(by):
		return
	var most := Player.CRASH_DAMAGE if ability < 0 else float(by.ability_spec(ability).get("demolition", 0.0))
	_damage_furniture(f, clampf(amount, 0.0, most), by)


func _damage_furniture(f: Furniture, amount: float, by: Player = null) -> void:
	# Walls shrug off anything but the heavy hitters.
	if not f.can_be_damaged() or amount <= 0.0 or amount < f.min_hit:
		return
	f.hp = maxf(0.0, f.hp - amount)
	var now_wrecked := f.hp <= 0.0
	_cl_furniture_state.rpc(f.index, f.hp / f.max_hp, now_wrecked, 0.0, 0, 0)
	if f is WallPanel:
		_wall_damaged(f, now_wrecked, by)
		return
	_shed(f, amount, by, now_wrecked)
	if now_wrecked:
		_spawn_debris("scorch", f.position)
		_spawn_debris("crumbs", f.position + Iso.to_screen(Vector2(randf_range(-6, 6), 8)))
		_cl_event.rpc("The %s is destroyed!" % _furniture_name(f), Color("ffb347"))


## Knocking furniture about shakes things loose: books, toys and magazines off
## hard pieces (Willow's to hide), pillows off soft ones (Biscuit's). One per
## Chores.SHED_EVERY damage while its budget lasts; a wreck sheds the rest.
## They land on the side the hit came from.
func _shed(f: Furniture, amount: float, by: Player, broke: bool) -> void:
	if f.shed_left < 0:
		f.shed_left = f.shed_budget()
	f.shed_damage += amount
	var n := 0
	while f.shed_left > 0 and (f.shed_damage >= Chores.SHED_EVERY or broke):
		f.shed_damage = maxf(0.0, f.shed_damage - Chores.SHED_EVERY)
		f.shed_left -= 1
		n += 1
	var toward := Iso.to_floor(by.position - f.position).normalized() if by else Vector2.from_angle(randf() * TAU)
	if toward.length() < 0.5:
		toward = Vector2.from_angle(randf() * TAU)
	for k in n:
		var kind: String = "pillow" if f.is_soft() else Chores.CLUTTER_KINDS.pick_random()
		var dist := f.reach() + randf_range(0.6, 1.2) * TILE
		var at := f.position + Iso.to_screen(toward.rotated(randf_range(-0.7, 0.7)) * dist)
		_spawn_debris(kind, level.clip(f.position, level.clamp_to_floor(at)))


## Plaster dust from every heavy hit (at most one pile a second per panel),
## and a hole with a feed line when it breaks. A hole shakes the pictures off
## the panels either side too.
func _wall_damaged(panel: WallPanel, broke: bool, by: Player) -> void:
	var side := Iso.to_screen(Vector2(1, 1) * 9.0)  # the dust lands on the visible side
	var now := _now()
	if broke:
		for k in 2:
			_spawn_debris("plaster", panel.position + side + Iso.to_screen(Vector2(randf_range(-8, 8), randf_range(-8, 8))))
		var who := by.display_name if by else "Something"
		var col := Roster.TEAM_COLORS[by.team] if by else Color("ffb347")
		_cl_event.rpc("%s smashed through the %s!" % [who, panel.label()], col)
		log_event("breach %s by %d" % [panel.name, by.pid if by else 0])
		if by:
			breaches[by.team] += 1
		for other in level.wall_panels:
			if Iso.fdist(other.position, panel.position) <= TILE * 1.5:
				_drop_pictures(other, Vector2(1, 1))
	elif now - float(_plaster_t.get(panel.index, -10.0)) >= 1.0:
		_plaster_t[panel.index] = now
		_spawn_debris("plaster", panel.position + side)


## The standing wall panel nearest `at`, within `radius` floor px (or null).
func _nearest_wall(at: Vector2, radius: float) -> WallPanel:
	var best: WallPanel = null
	var best_d := radius
	for panel in level.wall_panels:
		if not panel.wrecked and panel.distance_to(at) <= best_d:
			best = panel
			best_d = panel.distance_to(at)
	return best


@rpc("authority", "call_local", "reliable")
func _cl_furniture_state(idx: int, hp_frac: float, wrecked: bool, progress: float, helpers: int, step: int) -> void:
	var f := level.furniture[idx]
	var was_wrecked := f.wrecked
	var was_chore := f.current_chore()
	f.apply_state(hp_frac, wrecked, progress, helpers, step)
	if phase == Phase.CLEANUP:
		# A step of its repair done: the sound of that chore, or good as new.
		var done := f.current_chore() == Chores.Chore.NONE
		Audio.play_at("rebuilt" if done else Chores.SOUND.get(was_chore, "tidy"), level.entities, f.position)
	elif wrecked != was_wrecked:
		Audio.play_at("crash" if wrecked else "rebuilt", level.entities, f.position)
	elif not wrecked and hp_frac < 1.0:
		Audio.play_at("crack", level.entities, f.position, -3.0)
	if wrecked != was_wrecked:
		Fx.boom(level.entities, f.position, f.reach(), false)
		_nav_dirty = true
		if wrecked:
			log_event("wrecked %s" % f.name)


@rpc("authority", "call_local", "unreliable_ordered")
func _cl_furniture_progress(idx: int, progress: float, helpers: int, owner_on: bool) -> void:
	var f := level.furniture[idx]
	f.owner_working = owner_on
	f.apply_state(f.hp / f.max_hp if f.max_hp > 0.0 else 1.0, f.wrecked, progress, helpers, f.step)


## Is anyone standing where this wall panel would be?
func _body_in(panel: WallPanel) -> bool:
	var shape := ConvexPolygonShape2D.new()
	shape.points = panel.solid_polygon(Vector2.ZERO)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = panel.global_transform
	query.collision_mask = 4
	return not level.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


## Bots re-plan around wrecked (or rebuilt) furniture, at most a few times a second.
func _tick_navigation(delta: float) -> void:
	_nav_t -= delta
	if _nav_dirty and _nav_t <= 0.0:
		_nav_dirty = false
		_nav_t = 0.5
		level.rebuild_navigation()


static func _furniture_name(f: Furniture) -> String:
	if f is WallPanel:
		return f.label()
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
		if d.kind == decal and Iso.fdist(d.position, pos) < 20.0:
			return
	_spawn_debris(decal, pos)


# ================================================================== debris

func _spawn_debris(kind: String, pos: Vector2) -> void:
	var spec: Array = Chores.DEBRIS.get(kind, [Chores.Chore.FLOOR, 0.5, 0.4])
	# A fresh KO pile on top of an old one just makes that one bigger.
	if kind in ["fur", "bolts"]:
		var pile := _nearest_debris(pos, Chores.MERGE_RADIUS, kind, -1, true)
		if pile and _grow(pile):
			return
	# The house can only hold so much: after that, the nearest pile of the same
	# kind of mess with room to grow gets bigger instead, so it still counts
	# (and if there's none, a few more fit in after all).
	if debris.size() >= MAX_DEBRIS:
		var pile := _nearest_debris(pos, INF, "", spec[0], true)
		if pile:
			_grow(pile)
			return
		if debris.size() >= MAX_DEBRIS + MAX_DEBRIS_EXTRA:
			return
	var id := _next_debris_id
	_next_debris_id += 1
	var jitter := Iso.to_screen(Vector2(randf_range(-6, 6), randf_range(-6, 6)))
	_cl_debris_add.rpc(id, kind, _free_floor_spot(pos + jitter))


## The nearest pile of a kind (or of a chore) within `radius` (that can
## still grow, if `room`), or null.
func _nearest_debris(pos: Vector2, radius: float, kind: String, chore: int, room: bool = false) -> Debris:
	var best: Debris = null
	var best_d := radius
	for d: Debris in debris.values():
		if (kind != "" and d.kind != kind) or (chore >= 0 and d.chore != chore):
			continue
		if room and d.growth >= Chores.MAX_GROWTH - 0.001:
			continue
		var dist := Iso.fdist(d.position, pos)
		if dist < best_d:
			best = d
			best_d = dist
	return best


func _grow(pile: Debris) -> bool:
	if pile.growth >= Chores.MAX_GROWTH - 0.001:
		return false
	_cl_debris_grow.rpc(pile.debris_id)
	return true


## A scuff mark where someone crashed (one per spot).
func _scuff(pos: Vector2) -> void:
	if _nearest_debris(pos, 14.0, "scuff", -1) == null:
		_spawn_debris("scuff", pos)


## Nudges a point off any furniture (flyers get KO'd above armchairs).
func _free_floor_spot(pos: Vector2) -> Vector2:
	var space := level.get_world_2d().direct_space_state
	var query := PhysicsPointQueryParameters2D.new()
	query.collision_mask = 2 | WallPanel.LAYER
	var p := level.clamp_to_floor(pos)
	# Nudge toward the middle of its own room, so nothing hops a wall.
	var room := level.room_at(p)
	var middle := Iso.tile_to_local(room.area.get_center()) if room else level.home.position
	var toward_center := (middle - p).normalized()
	for step in 12:
		query.position = level.to_global(p)
		if space.intersect_point(query, 1).is_empty():
			break
		p += toward_center * 4.0
	# Somewhere everyone can reach (not tucked against the outside wall).
	var reach := level.walkable(p)
	return reach if reach.distance_to(p) > 2.0 and level.wall_between(pos, reach).is_empty() else p


@rpc("authority", "call_local", "reliable")
func _cl_debris_add(id: int, kind: String, pos: Vector2) -> void:
	var d := Debris.new()
	d.setup(id, kind, pos)
	level.entities.add_child(d)
	debris[id] = d


@rpc("authority", "call_local", "reliable")
func _cl_debris_grow(id: int) -> void:
	if debris.has(id):
		debris[id].grow()


@rpc("authority", "call_local", "reliable")
func _cl_debris_remove(id: int, how: int) -> void:
	if not debris.has(id):
		return
	var d: Debris = debris[id]
	debris.erase(id)
	match how:
		How.VACUUM:
			Audio.play_at("c_vacuum", level.entities, d.position, -4.0)
			d.vanish(d.position + Vector2(0, -4))
		How.SWAT:
			# Batted under the nearest couch (or bed, or table).
			Audio.play_at("c_swat", level.entities, d.position)
			d.vanish(_hiding_place(d.position))
		How.THUMP:
			d.vanish(d.position, true)
		How.OWNER:
			Audio.play_at(Chores.SOUND.get(d.chore, "scrub"), level.entities, d.position, -2.0)
			d.vanish(d.position)
		_:
			Audio.play_at("c_help", level.entities, d.position, -4.0)
			Fx.text(level.entities, d.position + Vector2(0, -8), "+help", Color("d8d8d8"))
			d.vanish(d.position)


## Where Willow bats things: under the nearest standing soft furniture or table.
func _hiding_place(from: Vector2) -> Vector2:
	var best := from + Iso.to_screen(Vector2(20, 0))
	var best_d := 140.0
	for f in level.furniture:
		if f.wrecked or f is WallPanel or not (f.is_soft() or f.style == Furniture.Style.TABLE):
			continue
		var dist := Iso.fdist(f.position, from)
		if dist < best_d and level.wall_between(from, f.position).is_empty():
			best = f.position
			best_d = dist
	return best


@rpc("authority", "call_local", "unreliable_ordered")
func _cl_debris_progress(id: int, progress: float, owner_on: bool) -> void:
	if debris.has(id):
		debris[id].owner_working = owner_on
		debris[id].set_progress(progress)


# ================================================================= pickups

## Host: now and then something pops up on the floor (see Pickups), and
## whoever it's for picks it up by walking over it.
func _tick_pickups(delta: float) -> void:
	for pu: Pickup in pickups.values():
		if pu.life <= 0.0:
			_cl_pickup_remove.rpc(pu.pickup_id)
			continue
		for p: Player in players.values():
			if Iso.fdist(p.position, pu.position) <= Pickups.RADIUS and pu.takeable_by(p, self) \
					and level.wall_between(p.position, pu.position).is_empty() and _wants(p, pu):
				_take_pickup(pu, p)
				break
	if not pickups_on:
		return
	var war := phase == Phase.WAR
	_pickup_t -= delta
	if _pickup_t > 0.0:
		return
	var every: Vector2 = Pickups.WAR_EVERY if war else Pickups.CLEANUP_EVERY
	_pickup_t = randf_range(every.x, every.y)
	if pickups.size() >= (Pickups.WAR_MAX if war else Pickups.CLEANUP_MAX):
		return
	var kind := Pickups.roll(Pickups.WAR_ODDS if war else Pickups.CLEANUP_ODDS)
	var arg := ""
	var at := Vector2.INF
	match kind:
		Pickups.Kind.WEAPON:
			var armed: Array = Roster.CHARACTERS.keys().filter(func(id: String) -> bool: return Roster.get_char(id)["weapon"].has("sprite"))
			arg = armed.pick_random()
		Pickups.Kind.TOOL:
			# For the chore with the most left to do, near one of its jobs.
			var job = _tool_job()
			if job == null:
				kind = Pickups.Kind.SKATES
			else:
				arg = str(chore_of(job))
				at = _pickup_spot((job as Node2D).position, 1.5)
	if at == Vector2.INF:
		at = _pickup_spot(Vector2.INF, 0.0)
	if at == Vector2.INF:
		return
	_cl_pickup_add.rpc(_next_pickup_id, kind, arg, at,
		Pickups.LIFETIME if war else Pickups.CLEANUP_LIFETIME)
	_next_pickup_id += 1


## Nobody picks up their own weapon (nothing would change), or a second one
## while the first (or its last shots) is still going: its hits must still count
## as the weapon that fired them.
func _wants(p: Player, pu: Pickup) -> bool:
	if pu.kind != Pickups.Kind.WEAPON:
		return true
	return p.data["weapon"]["name"] != Roster.get_char(pu.arg)["weapon"]["name"] and not _borrow_ok(p)


## A job of the chore with the most left to do (weighted by what's left), or null.
func _tool_job():
	var totals := chore_totals()
	var total := 0.0
	for c: int in Chores.OWNER:
		total += float(totals.get(c, [0, 0.0])[1])
	if total <= 0.0:
		return null
	var r := randf() * total
	var chosen := Chores.Chore.NONE
	for c: int in Chores.OWNER:
		r -= float(totals.get(c, [0, 0.0])[1])
		if r <= 0.0:
			chosen = c
			break
	var mine := open_jobs().filter(func(j: Object) -> bool: return chore_of(j) == chosen)
	return mine.pick_random() if not mine.is_empty() else null


## Somewhere open for a pickup to turn up: near `near` (within `spread` tiles)
## or anywhere, away from people, the bases, the rug and other pickups.
func _pickup_spot(near: Vector2, spread: float) -> Vector2:
	var size := Vector2(level.room.size_tiles)
	for attempt in 16:
		var t := Iso.local_to_tile(near) + Vector2(randf_range(-spread, spread), randf_range(-spread, spread)) \
			if near != Vector2.INF else Vector2(randf_range(1.0, size.x - 1.0), randf_range(1.0, size.y - 1.0))
		if t.x + t.y < 4.0:
			continue  # (under the scoreboard)
		var at := level.walkable(Iso.tile_to_local(t))
		if near != Vector2.INF and not level.wall_between(near, at).is_empty():
			continue
		if level.home.contains(at) or level.bases[0].contains(at) or level.bases[1].contains(at):
			continue
		# Not in a hole in a wall (it could be mended round it), nor hard up against one.
		var by_wall := false
		for panel in level.wall_panels:
			by_wall = by_wall or panel.distance_to(at) < Pickups.RADIUS + 2.0
		if by_wall:
			continue
		var crowded := false
		for p: Player in players.values():
			crowded = crowded or Iso.fdist(p.position, at) < (40.0 if near == Vector2.INF else 20.0)
		for pu: Pickup in pickups.values():
			crowded = crowded or Iso.fdist(pu.position, at) < 40.0
		if not crowded:
			return at
	return Vector2.INF


func _take_pickup(pu: Pickup, p: Player) -> void:
	match pu.kind:
		Pickups.Kind.ZOOMIES:
			_cl_buff.rpc(p.pid, Pickups.ZOOMIES_SPEED, Pickups.ZOOMIES_TIME, p.hp, "ZOOMIES!")
		Pickups.Kind.SKATES:
			_cl_buff.rpc(p.pid, Pickups.SKATES_SPEED, Pickups.SKATES_TIME, p.hp, "SKATES!")
		Pickups.Kind.SNACK:
			p.hp = mini(p.max_hp, p.hp + Pickups.SNACK_HEAL)
			_cl_heal.rpc(p.pid, p.hp)
	log_event("pickup %s (%s) by %d" % [Pickups.Kind.keys()[pu.kind], pu.arg, p.pid])
	_cl_pickup_taken.rpc(pu.pickup_id, p.pid)


## Is `p` still holding a weapon they picked up? (Slack for the last shots,
## which are still flying, or reach the host a moment after the timer runs out.)
func _borrow_ok(p: Player) -> bool:
	return p.borrowed != "" and p.borrow_t > -BORROW_GRACE


func _clear_pickups() -> void:
	for id: int in pickups.keys():
		_cl_pickup_remove.rpc(id)


@rpc("authority", "call_local", "reliable")
func _cl_pickup_add(id: int, kind: int, arg: String, pos: Vector2, lifetime: float) -> void:
	var pu := Pickup.new()
	pu.setup(id, kind, arg, pos, lifetime)
	level.entities.add_child(pu)
	pickups[id] = pu
	Audio.play_at("poof", level.entities, pos, -6.0)


@rpc("authority", "call_local", "reliable")
func _cl_pickup_taken(id: int, pid: int) -> void:
	var pu: Pickup = pickups.get(id)
	if pu == null:
		return
	pickups.erase(id)
	var p: Player = players.get(pid)
	if p:
		match pu.kind:
			Pickups.Kind.TREAT:
				if p.is_multiplayer_authority():
					p.gag_charge = 1.0
			Pickups.Kind.BUBBLE_WRAP:
				p.shield = Pickups.SHIELD
				p.shield_t = Pickups.SHIELD_TIME
			Pickups.Kind.WEAPON:
				p.borrowed = pu.arg
				p.borrow_t = Pickups.WEAPON_TIME
			Pickups.Kind.TOOL:
				p.turbo_chore = int(pu.arg)
				p.turbo_t = Pickups.TURBO_TIME
		var col := Roster.TEAM_COLORS[p.team] if phase == Phase.WAR else Color("8ff0a4")
		hud.feed("%s grabbed %s!" % [p.display_name, pu.label()], col)
		var shout: String = Pickups.SHORT.get(pu.kind, "")
		if pu.kind == Pickups.Kind.TOOL:
			shout = "TURBO!"
		if shout != "" and pu.kind != Pickups.Kind.ZOOMIES and pu.kind != Pickups.Kind.SKATES:
			Fx.text(level.entities, p.position + Vector2(0, -p.sprite_height() - 8), shout, Pickups.COLORS[pu.kind])
	Audio.play_at("pickup", level.entities, pu.position)
	Fx.burst(level.entities, pu.position + Vector2(0, -12), Pickups.COLORS.get(pu.kind, Color.WHITE))
	pu.queue_free()


@rpc("authority", "call_local", "reliable")
func _cl_pickup_remove(id: int) -> void:
	var pu: Pickup = pickups.get(id)
	if pu == null:
		return
	pickups.erase(id)
	Fx.puff(level.entities, pu.position + Vector2(0, -12), Color(1, 1, 1, 0.7))
	pu.queue_free()


@rpc("authority", "call_local", "reliable")
func _cl_shield(pid: int, amount: int) -> void:
	if players.has(pid):
		players[pid].shield = amount
		if amount <= 0:
			players[pid].shield_t = 0.0


# =================================================================== misc

@rpc("authority", "call_local", "reliable")
func _cl_event(text: String, color: Color) -> void:
	hud.feed(text, color)
	log_event(text)


func _on_peer_disconnected(peer: int) -> void:
	# That machine's player, and anyone who was sharing its screen.
	for id: int in players.keys():
		if id != peer and int(Net.roster.get(id, {}).get("owner", 0)) != peer:
			continue
		if multiplayer.is_server():
			if remote.carrier_pid == id:
				_drop_remote(players[id].position)
			_ko_timers.erase(id)
			_cl_remove_player.rpc(id)
		else:
			_cl_remove_player(id)
	if multiplayer.is_server():
		_check_all_loaded()
	# If that was the last friend online, everyone left is on this screen:
	# waiting for a dropped controller works like any couch game again.
	_on_seats_changed.call_deferred()


@rpc("authority", "call_local", "reliable")
func _cl_remove_player(id: int) -> void:
	if players.has(id):
		hud.feed("%s went home." % players[id].display_name, Color.WHITE)
		_forget_bot_plans(players[id])
		players[id].queue_free()
		players.erase(id)


## A bot stops driving this character (its person is back, or they left):
## let go of the job it was heading for.
func _forget_bot_plans(p: Player) -> void:
	p.focus_job = null
	for job in claims.keys():
		if claims[job] == p.pid:
			claims.erase(job)


func summary() -> String:
	return "phase=%s score=%d-%d mess=%.1f debris=%d results=%s" % [
		Phase.keys()[phase], scores[0], scores[1], mess_remaining(), debris.size(), str(results)]
