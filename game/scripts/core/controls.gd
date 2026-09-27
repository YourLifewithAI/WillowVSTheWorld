class_name Controls
extends RefCounted
## Something that drives a character: a person on this screen (SeatInput) or
## a bot (BotBrain). think() is called once per physics tick and returns:
##   move (Vector2), attack, attack_held, special, dash, gag,
##   interact (held), interact_pressed (this tick),
##   and optionally aim (Vector2: a second stick) and mouse (the mouse aims).

## People hold attack (or throw) to stand still and aim, and let go to fire,
## with a little aim assist; bots fire the moment they press (see Player).
var hold_to_aim := false


func think() -> Dictionary:
	return {"move": Vector2.ZERO, "attack": false, "attack_held": false, "special": false, "dash": false,
		"gag": false, "interact": false, "interact_pressed": false}
