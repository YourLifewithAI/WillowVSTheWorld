extends Node
## Net (autoload): connections, the lobby roster, and launch options.
##
## One player hosts (and is also the server, peer id 1), everyone else joins by
## IP. "Practice" runs the same code with no network at all: Godot's default
## OfflineMultiplayerPeer makes this machine the server.
##
## The roster maps a player id to their lobby choices:
##   { id: {"name": String, "char": String, "team": int, "bot": bool} }
## Human ids are network peer ids (1 = host). Bot ids are negative.

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
var options: Dictionary = {}

var _next_bot_id := -1
var matches_played := 0
## Shown by the main menu after we get dropped back to it.
var last_error := ""


func _ready() -> void:
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
	if multiplayer.multiplayer_peer and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	roster.clear()
	in_match = false
	online = false
	_next_bot_id = -1
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
	_goto_lobby()
	_maybe_autostart()


func _my_entry() -> Dictionary:
	return {"name": local_name, "char": local_char,
		"team": Roster.get_char(local_char)["team"], "bot": false}


func _goto_lobby() -> void:
	in_match = false
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
	roster[_next_bot_id] = {"name": bot_name, "char": pick, "team": team, "bot": true}
	_next_bot_id -= 1
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
	_cl_begin_match.rpc(roster, map_id)


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
	roster[sender] = {
		"name": String(info.get("name", "Player")).left(16),
		"char": char_id if Roster.CHARACTERS.has(char_id) else "willow",
		"team": Roster.get_char(char_id)["team"],
		"bot": false,
	}
	_broadcast_roster()
	_maybe_autostart()


## Host only: pick the home to fight in.
func set_map(id: String) -> void:
	if is_host() and Maps.exists(id):
		map_id = id
		_broadcast_roster()


func _broadcast_roster() -> void:
	_cl_roster.rpc(roster, map_id)


@rpc("authority", "call_local", "reliable")
func _cl_roster(new_roster: Dictionary, new_map: String) -> void:
	roster = new_roster
	map_id = new_map
	roster_changed.emit()


@rpc("authority", "call_local", "reliable")
func _cl_begin_match(final_roster: Dictionary, final_map: String) -> void:
	roster = final_roster
	map_id = final_map
	in_match = true
	get_tree().change_scene_to_file(MATCH_SCENE)


@rpc("authority", "call_local", "reliable")
func _cl_return_to_lobby() -> void:
	_goto_lobby()


func _maybe_autostart() -> void:
	if not options.has("autostart") or in_match:
		return
	var humans := 0
	for entry: Dictionary in roster.values():
		if not entry["bot"]:
			humans += 1
	if humans >= int(options["autostart"]) and can_start():
		# Give the newest client a moment to load the lobby scene.
		get_tree().create_timer(0.5).timeout.connect(start_match)


# ------------------------------------------------------ connection events

func _on_peer_connected(id: int) -> void:
	if is_host():
		if in_match or roster.size() >= MAX_PLAYERS:
			# No late joining yet: politely hang up on them.
			(multiplayer.multiplayer_peer as ENetMultiplayerPeer).disconnect_peer(id)
			return
		_cl_roster.rpc_id(id, roster, map_id)


func _on_peer_disconnected(id: int) -> void:
	if is_host() and roster.has(id):
		roster.erase(id)
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
