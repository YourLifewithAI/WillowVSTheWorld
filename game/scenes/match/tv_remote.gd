class_name TVRemote
extends Node2D
## The TV remote: the "flag" everyone is fighting over. The host runs its
## state machine (in Match); every peer draws it from the synced state.

enum State { HOME, CARRIED, DROPPED, FLYING }

var state: State = State.HOME
var carrier_pid := 0
var z := 0.0
var home := Vector2.ZERO

# Host-side bookkeeping.
var vel := Vector2.ZERO
var timer := 0.0
var thrower := 0
var grace := 0.0
var hold := 0.0

## 0..1 progress of the carrier changing the channel (synced for display).
var hold_frac := 0.0
## What this machine last heard about the remote, for sound effects.
var _heard_state: State = State.HOME
var _heard_carrier := 0
var _hold_step := 0

var _net_pos := Vector2.ZERO
var _sprite: Sprite2D
var _t := 0.0
var arena: Match


func _ready() -> void:
	_sprite = Sprite2D.new()
	_sprite.texture = Roster.texture("remote")
	_sprite.centered = false
	var s := _sprite.texture.get_size()
	_sprite.offset = Vector2(-floor(s.x / 2.0), -s.y)
	add_child(_sprite)
	_net_pos = position


func is_free() -> bool:
	return state == State.HOME or state == State.DROPPED


func carrier() -> Player:
	if state != State.CARRIED:
		return null
	return arena.players.get(carrier_pid)


func apply_net(new_state: int, new_carrier: int, pos: Vector2, pz: float) -> void:
	if new_state == State.DROPPED and state != State.DROPPED and arena:
		timer = arena.remote_return_time
	_play_transition(new_state as State, new_carrier, pos)
	state = new_state as State
	carrier_pid = new_carrier
	_net_pos = pos
	z = pz
	if position.distance_to(pos) > 60.0:
		position = pos


## Changing-the-channel progress: a rising blip every quarter.
func apply_hold(frac: float) -> void:
	hold_frac = frac
	var step := int(frac * 4.0)
	if step > _hold_step and arena:
		Audio.play_at("channel_tick", arena.level.entities, position, 0.0, 1.0 + 0.2 * step)
	_hold_step = step


func _play_transition(new_state: State, new_carrier: int, pos: Vector2) -> void:
	var old := _heard_state
	var old_carrier := _heard_carrier
	_heard_state = new_state
	_heard_carrier = new_carrier
	if arena == null or (new_state == old and new_carrier == old_carrier):
		return
	var sfx := ""
	match new_state:
		State.CARRIED:
			sfx = "pickup"
		State.FLYING:
			sfx = "throw"
		State.DROPPED:
			sfx = "drop" if old == State.CARRIED else "thud"
		State.HOME:
			# Scoring has its own fanfare; putting it back during cleanup sparkles.
			if old == State.DROPPED:
				sfx = "remote_home"
			elif arena.phase == Match.Phase.CLEANUP:
				sfx = "tidy"
	Audio.play_at(sfx, arena.level.entities, pos)


func _process(delta: float) -> void:
	_t += delta
	var c := carrier()
	if c:
		# Follow the carrier locally so it never lags behind their head.
		position = c.position + Vector2(0, 0.5)
		_sprite.position = Vector2(0, round(-c.z - c.sprite_height() - 3.0 + sin(_t * 8.0)))
		_sprite.rotation = 0.0
	else:
		if not multiplayer.is_server():
			position = position.lerp(_net_pos, 1.0 - exp(-20.0 * delta))
			if state == State.DROPPED:
				timer = maxf(0.0, timer - delta)
		var bob := 0.0 if state == State.FLYING else sin(_t * 4.0) * 2.0 - 5.0
		_sprite.position = Vector2(0, round(-z + bob))
		_sprite.rotation = sin(_t * 20.0) * 0.8 if state == State.FLYING else 0.0
	queue_redraw()


func _draw() -> void:
	if state == State.CARRIED:
		if hold_frac > 0.0:
			# Channel-changing progress ring above the carrier's head.
			var center := _sprite.position + Vector2(0, -6)
			draw_arc(center, 6.0, -PI / 2.0, -PI / 2.0 + TAU, 16, Color(0, 0, 0, 0.5), 2.0)
			draw_arc(center, 6.0, -PI / 2.0, -PI / 2.0 + TAU * hold_frac, 16, Color("ffd84d"), 2.0)
		return
	draw_colored_polygon(Iso.ellipse(4.0, 12), Color(0, 0, 0, 0.25))
	# A glowing beacon so everybody can find it.
	var pulse := 0.5 + 0.5 * sin(_t * 5.0)
	var ring := Iso.ellipse(8.0 + pulse * 3.0, 20)
	ring.append(ring[0])
	draw_polyline(ring, Color(1.0, 0.85, 0.3, 0.9 - pulse * 0.5), 1.0)
	var tip := Vector2(0, round(-z - 18.0 - pulse * 3.0))
	draw_colored_polygon(PackedVector2Array([tip + Vector2(-3, -4), tip + Vector2(3, -4), tip]), Color("ffd84d"))
	if state == State.DROPPED and arena and arena.phase == Match.Phase.WAR:
		# Countdown pips until it teleports home.
		var frac := clampf(timer / arena.remote_return_time, 0.0, 1.0)
		draw_rect(Rect2(Vector2(-6, 3), Vector2(12.0 * frac, 1)), Color(1, 1, 1, 0.7))
