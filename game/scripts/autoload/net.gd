extends Node
## Net (autoload): connections, the lobby roster, and launch options.
##
## One player hosts (and is also the server, peer id 1), everyone else joins by
## IP. "Practice" runs the same code with no network at all: Godot's default
## OfflineMultiplayerPeer makes this machine the server.
##
## The roster maps a player id to their lobby choices:
##   { id: {"name": String, "char": String, "team": int, "bot": bool} }
## Each machine's own player is keyed by its network peer id (1 = host).
## Bots, and guests sharing the host's screen (see Seats), get negative ids
## from one counter; guests also carry "owner" (the peer whose screen they're
## on) and "seat".

signal roster_changed
signal joined_lobby
signal connection_failed(reason: String)
signal disconnected(reason: String)

const DEFAULT_PORT := 7777
const MAX_PLAYERS := 8
const LOBBY_SCENE := "res://scenes/menu/lobby.tscn"
const MENU_SCENE := "res://scenes/menu/main_menu.tscn"
const MATCH_SCENE := "res://scenes/match/match.tscn"

var roster: Dictionary = {}
var local_name := "Player"
var local_char := "willow"
## Which home the host picked (see Maps).
var map_id := Maps.DEFAULT
## Which powerups can turn up (see Pickups.MENU): the host picks, in the lobby.
var powerups: Array = Pickups.MENU.duplicate()
var in_match := false
var online := false
## True once a --practice/--host/--join launch option has been used, so
## returning to the menu doesn't relaunch it.
var autolaunched := false

## Command-line options (after `--`), for quick testing:
##   --practice | --host | --join=IP     skip the menu
##   --bots=N          host adds N bots, alternating teams
##   --char=ID         pick a character
##   --map=ID          host picks a map (living_room, studio, farmhouse, suburbs)
##   --autostart=N     host starts the match once N humans are in the lobby
##   --autopilot       a bot drives your character (for soak tests)
##   --war=SEC --cleanup=SEC   phase lengths
##   --screenshot=PATH@SEC     save a screenshot, then keep running
##   --quit-after=SEC  exit after this long (prints a summary line)
##   --rematches=N     host automatically starts N rematches (soak testing)
##   --mute            no sound this run;  --audio-log  print every sound as it plays
##   --guests=N        host adds N guests on its own screen (tests; drive them with --autopilot)
##   --fake-pads=ID:KIND[:SERIAL],...   pretend controllers are plugged in (tests; see Seats)
var options: Dictionary = {}

var _next_local_id := -1
var matches_played := 0
## Shown by the main menu after we get dropped back to it.
var last_error := ""


func _ready() -> void:
	# The fullscreen shortcut works while the game is paused too. (Net has
	# no per-frame work, and its timers already ignore pausing.)
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		options[parts[0]] = parts[1] if parts.size() > 1 else "true"
	local_name = options.get("name", _default_name())
	local_char = options.get("char", local_char)
	if Maps.exists(options.get("map", "")):
		map_id = options["map"]
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	if options.has("quit-after"):
		get_tree().create_timer(float(options["quit-after"]), true, false, true).timeout.connect(_quit_with_summary)
	if options.has("screenshot"):
		for shot in String(options["screenshot"]).split(","):
			var parts := shot.split("@")
			var at := float(parts[1]) if parts.size() > 1 else 3.0
			get_tree().create_timer(at, true, false, true).timeout.connect(_screenshot.bind(parts[0]))


## F11 (or Alt+Enter) switches fullscreen on and off anywhere in the game.
func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and (key.keycode == KEY_F11 or (key.keycode == KEY_ENTER and key.alt_pressed)):
		var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
		get_viewport().set_input_as_handled()


func _quit_with_summary() -> void:
	if Match.current:
		print("[summary:%d] %s" % [my_id(), Match.current.summary()])
	Audio.quit_game()


func _screenshot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("[screenshot] %s" % path)


# --------------------------------------------------------------- sessions

func practice() -> void:
	leave(false)
	online = false
	_enter_lobby_as_host()


func host(port: int = DEFAULT_PORT) -> Error:
	leave(false)
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS - 1)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	online = true
	_enter_lobby_as_host()
	return OK


func join(address: String, port: int = DEFAULT_PORT) -> Error:
	leave(false)
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	online = true
	return OK


## Disconnect and (optionally) go back to the main menu.
func leave(to_menu: bool = true) -> void:
	get_tree().paused = false
	if multiplayer.multiplayer_peer and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	roster.clear()
	in_match = false
	online = false
	_next_local_id = -1
	Seats.reset()
	if to_menu:
		get_tree().change_scene_to_file(MENU_SCENE)


func my_id() -> int:
	return multiplayer.get_unique_id()


func is_host() -> bool:
	return multiplayer.is_server()


func _enter_lobby_as_host() -> void:
	roster.clear()
	roster[1] = _my_entry()
	var bots := int(options.get("bots", "0"))
	# Alternate teams, starting with the side the host isn't on.
	var host_team: int = roster[1]["team"]
	for i in bots:
		add_bot((host_team + 1 + i) % 2)
	for i in int(options.get("guests", "0")):
		var seat := Seats.Seat.new()
		seat.index = i + 1
		seat.roster_id = add_guest(seat.index)
		Seats.seats.append(seat)
	name_my_player()
	_goto_lobby()
	_maybe_autostart()


func _my_entry() -> Dictionary:
	var shown := Seats.tag(0) if Seats.seats.size() > 1 else local_name
	return {"name": shown, "char": local_char,
		"team": Roster.get_char(local_char)["team"], "bot": false}


func _goto_lobby() -> void:
	in_match = false
	Seats.unmute_all()
	get_tree().change_scene_to_file(LOBBY_SCENE)
	joined_lobby.emit()
	roster_changed.emit()


# ----------------------------------------------------------- lobby edits

## Pick a character for yourself (team follows the character).
func choose_character(char_id: String) -> void:
	local_char = char_id
	var info := _my_entry()
	if is_host():
		_srv_register(info)
	else:
		_srv_register.rpc_id(1, info)


func add_bot(team: int) -> void:
	if not is_host() or roster.size() >= MAX_PLAYERS:
		return
	var ids := Roster.ids_for_team(team)
	# Prefer a character nobody on that team is using yet.
	var used := []
	for entry: Dictionary in roster.values():
		used.append(entry["char"])
	var pool: Array = ids.filter(func(c: String) -> bool: return not used.has(c))
	if pool.is_empty():
		pool = ids
	var pick: String = pool.pick_random()
	var bot_name: String = Roster.get_char(pick)["name"] + " (bot)"
	roster[_next_local_id] = {"name": bot_name, "char": pick, "team": team, "bot": true}
	_next_local_id -= 1
	_broadcast_roster()


## Is there space for one more person on the host's screen? (Bots make way.)
func has_room_for_guest() -> bool:
	if roster.size() < MAX_PLAYERS:
		return true
	return roster.values().any(func(e: Dictionary) -> bool: return e["bot"])


## Host only: someone else on this screen joins (see Seats). Returns their id.
## When the house is full, a bot goes home to make room.
func add_guest(seat: int) -> int:
	if not is_host() or not has_room_for_guest():
		return 0
	# Start them on the side with fewer people, as someone nobody is playing yet.
	var used := []
	var humans := [0, 0]
	for entry: Dictionary in roster.values():
		if not entry["bot"]:
			used.append(entry["char"])
			humans[entry["team"]] += 1
	var team := 0 if humans[0] < humans[1] else 1
	var pick := ""
	for c: String in Roster.ids_for_team(team) + Roster.ids_for_team(1 - team):
		if not used.has(c):
			pick = c
			break
	if pick.is_empty():
		pick = Roster.ids_for_team(team)[0]
	if roster.size() >= MAX_PLAYERS:
		_evict_bot(Roster.get_char(pick)["team"])
	var id := _next_local_id
	_next_local_id -= 1
	roster[id] = {"name": "P%d" % (seat + 1), "char": pick, "team": Roster.get_char(pick)["team"],
		"bot": false, "owner": my_id(), "seat": seat}
	_broadcast_roster()
	return id


## Sends a bot home, preferring one from `team`.
func _evict_bot(team: int) -> void:
	var victim := 0
	for id: int in roster:
		if roster[id]["bot"] and (victim == 0 or roster[id]["team"] == team):
			victim = id
	if victim != 0:
		roster.erase(victim)


## With several people on the host's screen, its own player is "P1" (so the
## feed and awards don't credit the laptop owner for someone else's plays).
func name_my_player() -> void:
	if not roster.has(my_id()):
		return
	var shared := Seats.seats.size() > 1
	var want := Seats.tag(0) if shared else local_name
	if roster[my_id()]["name"] != want:
		roster[my_id()]["name"] = want
		_broadcast_roster()


func remove_guest(id: int) -> void:
	if is_host() and roster.has(id) and not roster[id]["bot"] and roster[id].has("owner"):
		roster.erase(id)
		_broadcast_roster()


func set_guest_character(id: int, char_id: String) -> void:
	if is_host() and roster.has(id) and Roster.CHARACTERS.has(char_id):
		roster[id]["char"] = char_id
		roster[id]["team"] = Roster.get_char(char_id)["team"]
		_broadcast_roster()


func remove_bots() -> void:
	if not is_host():
		return
	for id: int in roster.keys():
		if roster[id]["bot"]:
			roster.erase(id)
	_broadcast_roster()


func team_counts() -> Array[int]:
	var counts: Array[int] = [0, 0]
	for entry: Dictionary in roster.values():
		counts[entry["team"]] += 1
	return counts


func can_start() -> bool:
	var counts := team_counts()
	return is_host() and counts[0] > 0 and counts[1] > 0


func start_match() -> void:
	if not can_start():
		return
	_cl_begin_match.rpc(roster, map_id, powerups)


func return_to_lobby() -> void:
	if is_host():
		_cl_return_to_lobby.rpc()


@rpc("any_peer", "call_remote", "reliable")
func _srv_register(info: Dictionary) -> void:
	if not is_host():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = 1
	var char_id: String = info.get("char", "willow")
	if not roster.has(sender) and roster.size() >= MAX_PLAYERS:
		(multiplayer.multiplayer_peer as ENetMultiplayerPeer).disconnect_peer(sender)
		return
	roster[sender] = {
		"name": String(info.get("name", "Player")).left(16),
		"char": char_id if Roster.CHARACTERS.has(char_id) else "willow",
		"team": Roster.get_char(char_id)["team"],
		"bot": false,
	}
	_broadcast_roster()
	_maybe_autostart()


## Host only: let a kind of powerup turn up, or not.
func set_powerup(kind: int, on: bool) -> void:
	if not is_host() or not kind in Pickups.MENU or (kind in powerups) == on:
		return
	if on:
		powerups.append(kind)
	else:
		powerups.erase(kind)
	_broadcast_roster()


## Host only: pick the home to fight in.
func set_map(id: String) -> void:
	if is_host() and Maps.exists(id):
		map_id = id
		_broadcast_roster()


func _broadcast_roster() -> void:
	_cl_roster.rpc(roster, map_id, powerups)


@rpc("authority", "call_local", "reliable")
func _cl_roster(new_roster: Dictionary, new_map: String, new_powerups: Array) -> void:
	roster = new_roster
	map_id = new_map
	powerups = new_powerups
	roster_changed.emit()


@rpc("authority", "call_local", "reliable")
func _cl_begin_match(final_roster: Dictionary, final_map: String, final_powerups: Array) -> void:
	get_tree().paused = false
	Seats.unmute_all()
	roster = final_roster
	map_id = final_map
	powerups = final_powerups
	in_match = true
	get_tree().change_scene_to_file(MATCH_SCENE)


@rpc("authority", "call_local", "reliable")
func _cl_return_to_lobby() -> void:
	get_tree().paused = false
	_goto_lobby()


func _maybe_autostart() -> void:
	if not options.has("autostart") or in_match:
		return
	# Count machines, not people: guests on the host's screen don't mean a friend has joined.
	var machines := {}
	for id: int in roster:
		if not roster[id]["bot"]:
			machines[int(roster[id].get("owner", id))] = true
	if machines.size() >= int(options["autostart"]) and can_start():
		# Give the newest client a moment to load the lobby scene.
		get_tree().create_timer(0.5).timeout.connect(start_match)


# ------------------------------------------------------ connection events

func _on_peer_connected(id: int) -> void:
	if is_host():
		if in_match or roster.size() >= MAX_PLAYERS:
			# No late joining yet: politely hang up on them.
			(multiplayer.multiplayer_peer as ENetMultiplayerPeer).disconnect_peer(id)
			return
		_cl_roster.rpc_id(id, roster, map_id, powerups)


func _on_peer_disconnected(id: int) -> void:
	if not is_host():
		return
	var gone := false
	for key: int in roster.keys():
		if key == id or int(roster[key].get("owner", 0)) == id:
			roster.erase(key)
			gone = true
	if gone:
		_broadcast_roster()


func _on_connected_to_server() -> void:
	_goto_lobby()
	_srv_register.rpc_id(1, _my_entry())


func _on_connection_failed() -> void:
	leave(false)
	connection_failed.emit("Couldn't reach the host.")


func _on_server_disconnected() -> void:
	last_error = "The host left the game."
	leave(true)
	disconnected.emit(last_error)


func _default_name() -> String:
	var n := OS.get_environment("USER")
	if n.is_empty():
		n = OS.get_environment("USERNAME")
	return n.capitalize().left(16) if not n.is_empty() else "Player"


## LAN addresses the host can share with friends.
func local_addresses() -> Array[String]:
	var out: Array[String] = []
	for a in IP.get_local_addresses():
		if a.begins_with("192.168.") or a.begins_with("10.") or a.begins_with("172."):
			out.append(a)
	return out
