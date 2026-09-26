extends Node
## Audio (autoload): sound effects, music, and the volume settings.
##
## Sounds are looked up by name: `Audio.play("pickup")` plays
## res://assets/sounds/pickup.wav (or .ogg). The placeholders come from
## tools/make_sounds.py; drop in a real file with the same name to replace one.
##
## Anything that happens in the world should use `play_at`, so it pans with
## where it happened. Every peer plays its own sounds from the same events
## that draw the effects, so nothing about audio goes over the network.

const SOUND_DIR := "res://assets/sounds/"
const MUSIC_DIR := "res://assets/music/"
const SETTINGS_PATH := "user://settings.cfg"
const BUSES: Array[String] = ["Master", "Music", "SFX"]
const DEFAULT_VOLUMES := {"Master": 0.8, "Music": 0.6, "SFX": 0.9}
## Once this many sounds are playing, the small stuff (gunfire, little hits)
## gets skipped so announcements, KOs and big moves are always heard...
const BUSY_VOICES := 20
## ...and nothing at all starts beyond this.
const MAX_VOICES := 48
const SKIPPABLE: Array[String] = ["ball", "laser", "dust", "sub", "toaster", "bazooka", "egg_drop",
	"whoosh", "feathers", "hit", "thud", "crack", "scrub", "knock", "dash", "splat", "boom", "channel_tick"]
## The same sound won't start again sooner than this (the gatling fires 9 times a second)...
const MIN_GAP := 0.04
## ...or than this, for sounds that can pile up.
const GAPS := {"crack": 0.12, "thud": 0.08, "hit": 0.05, "scrub": 0.08, "knock": 0.06, "channel_tick": 0.1}
const MUSIC_FADE := 0.8

## Linear 0..1 per bus.
var volumes: Dictionary = DEFAULT_VOLUMES.duplicate()

var _streams: Dictionary = {}  # name -> AudioStream (or null when missing)
var _last_played: Dictionary = {}  # name -> seconds
var _playing: Array[Node] = []
var _quitting := false
## --audio-log prints every sound as it plays (the tests use it).
var _log := false
var _music: AudioStreamPlayer
var _music_old: AudioStreamPlayer
var _music_name := ""
var _music_tween: Tween
var _pending_music: SceneTreeTimer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for bus in BUSES:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
			AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	_log = Net.options.has("audio-log")
	_load_settings()
	_music = _make_music_player()
	_music_old = _make_music_player()
	get_tree().node_added.connect(_on_node_added)
	get_tree().auto_accept_quit = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		quit_game()


## Quits, after the mixer has let go of every sound that's still playing
## (otherwise Godot reports them as leaked when it shuts down).
func quit_game() -> void:
	if _quitting:
		return
	_quitting = true
	for p in _playing:
		if is_instance_valid(p):
			p.call("stop")
	_music.stop()
	_music_old.stop()
	# The mixer lets go of stopped sounds on its own thread, and the engine only
	# frees them between frames, so give it a few of each.
	for i in 6:
		OS.delay_msec(20)
		await get_tree().process_frame
	get_tree().quit()


func _make_music_player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = "Music"
	add_child(p)
	return p


# ================================================================ effects

## A sound that isn't anywhere in particular (menus, announcements).
func play(sound: String, volume_db: float = 0.0, pitch: float = 1.0, jitter: float = 0.0) -> void:
	var stream := _ready_to_play(sound)
	if stream == null:
		return
	var p := AudioStreamPlayer.new()
	_start(p, stream, volume_db, pitch, jitter)
	add_child(p)
	p.play()


## A sound that happens somewhere in the world: pans toward where it happened.
## `parent` is any node in the world (usually the level's entities).
func play_at(sound: String, parent: Node, pos: Vector2, volume_db: float = 0.0, pitch: float = 1.0, jitter: float = 0.06) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var stream := _ready_to_play(sound)
	if stream == null:
		return
	var p := AudioStreamPlayer2D.new()
	p.position = pos
	p.attenuation = 0.4
	p.max_distance = 1400.0
	_start(p, stream, volume_db, pitch, jitter)
	parent.add_child(p)
	p.play()


## Plays `sound` at `pos` after `delay` seconds (for things that land later).
func play_later(sound: String, delay: float, parent: Node, pos: Vector2, volume_db: float = 0.0) -> void:
	get_tree().create_timer(delay, false).timeout.connect(func() -> void:
		if is_instance_valid(parent):
			play_at(sound, parent, pos, volume_db))


func _ready_to_play(sound: String) -> AudioStream:
	if sound.is_empty() or _quitting or _playing.size() >= MAX_VOICES:
		return null
	if _playing.size() >= BUSY_VOICES and SKIPPABLE.has(sound):
		return null
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last_played.get(sound, -100.0)) < float(GAPS.get(sound, MIN_GAP)):
		return null
	var stream := _stream(sound)
	if stream:
		_last_played[sound] = now
		if _log:
			print("[audio] %s" % sound)
	return stream


func _start(p: Node, stream: AudioStream, volume_db: float, pitch: float, jitter: float) -> void:
	p.set("stream", stream)
	p.set("volume_db", volume_db)
	p.set("pitch_scale", pitch * (1.0 + randf_range(-jitter, jitter)))
	p.set("bus", "SFX")
	_playing.append(p)
	p.tree_exited.connect(func() -> void: _playing.erase(p))
	p.connect("finished", p.queue_free)


func _stream(sound: String) -> AudioStream:
	if _streams.has(sound):
		return _streams[sound]
	var stream: AudioStream = null
	for ext in ["wav", "ogg"]:
		var path := "%s%s.%s" % [SOUND_DIR, sound, ext]
		if ResourceLoader.exists(path):
			stream = load(path)
			break
	if stream == null:
		push_warning("Audio: no sound called '%s'" % sound)
	_streams[sound] = stream
	return stream


# ================================================================== music

## Cross-fades to a looping track ("" fades the music out). Asking for the
## track that's already playing does nothing.
func music(track: String, fade: float = MUSIC_FADE) -> void:
	_pending_music = null
	if track == _music_name:
		return
	_music_name = track
	if _log:
		print("[audio] music %s" % (track if not track.is_empty() else "(off)"))
	if _music_tween:
		_music_tween.kill()
	# The old track fades out on the spare player.
	var old := _music
	_music = _music_old
	_music_old = old
	_music_tween = create_tween().set_parallel(true)
	_music_tween.tween_property(_music_old, "volume_db", -40.0, fade)
	var stream := _music_stream(track)
	if stream:
		_music.stream = stream
		_music.volume_db = -30.0
		_music.play()
		_music_tween.tween_property(_music, "volume_db", 0.0, fade)
	else:
		_music.stop()
	_music_tween.chain().tween_callback(_music_old.stop)


## Starts a track after a pause (e.g. once a jingle has finished).
func music_after(track: String, delay: float) -> void:
	var timer := get_tree().create_timer(delay)
	_pending_music = timer
	timer.timeout.connect(func() -> void:
		if _pending_music == timer:
			music(track))


func _music_stream(track: String) -> AudioStream:
	if track.is_empty():
		return null
	for ext in ["ogg", "mp3", "wav"]:
		var path := "%s%s.%s" % [MUSIC_DIR, track, ext]
		if ResourceLoader.exists(path):
			var stream: AudioStream = load(path)
			if stream is AudioStreamOggVorbis or stream is AudioStreamMP3:
				stream.set("loop", true)
			elif stream is AudioStreamWAV and stream.loop_mode == AudioStreamWAV.LOOP_DISABLED:
				stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
				stream.loop_end = int(stream.get_length() * stream.mix_rate)
			return stream
	push_warning("Audio: no music called '%s'" % track)
	return null


# =============================================================== settings

func set_volume(bus: String, linear: float) -> void:
	volumes[bus] = clampf(linear, 0.0, 1.0)
	_apply_volume(bus)
	_save_settings()


func _apply_volume(bus: String) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx == -1:
		return
	var v: float = volumes[bus]
	AudioServer.set_bus_volume_db(idx, linear_to_db(v * v))  # squared: sliders feel more even
	AudioServer.set_bus_mute(idx, v <= 0.001)


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		for bus in BUSES:
			volumes[bus] = clampf(float(cfg.get_value("volume", bus, volumes[bus])), 0.0, 1.0)
	if Net.options.has("mute"):
		volumes["Master"] = 0.0
	for bus in BUSES:
		_apply_volume(bus)


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)  # keep anything else that's in there
	for bus in BUSES:
		if bus == "Master" and Net.options.has("mute"):
			continue  # muted just for this run
		cfg.set_value("volume", bus, volumes[bus])
	cfg.save(SETTINGS_PATH)


# ===================================================================== UI

## Every button in the game clicks, unless it asks not to (meta "silent").
func _on_node_added(node: Node) -> void:
	if node is BaseButton and not node.has_meta("silent"):
		(node as BaseButton).pressed.connect(func() -> void: play("click", -4.0))
