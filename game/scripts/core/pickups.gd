class_name Pickups
extends RefCounted
## Things that pop up around the house (see Pickup, Match._tick_pickups).
##
## In the war: power-ups and other characters' weapons, for whoever gets there
## first. In the cleanup: turbo tools, each marked with one chore's face, that
## only that chore's owner can pick up (so they make the specialists better at
## their job rather than doing it for them), and roller skates for anyone.

enum Kind { ZOOMIES, BUBBLE_WRAP, SNACK, TREAT, WEAPON, TOOL, SKATES }

const NAMES := {
	Kind.ZOOMIES: "the Zoomies", Kind.BUBBLE_WRAP: "Bubble Wrap", Kind.SNACK: "a Snack",
	Kind.TREAT: "a Treat", Kind.SKATES: "Roller Skates",
}
## What the card says while it lasts.
const SHORT := {
	Kind.ZOOMIES: "ZOOMIES!", Kind.BUBBLE_WRAP: "BUBBLE WRAP", Kind.SKATES: "SKATES!",
}
const ICONS := {
	Kind.ZOOMIES: "pu_zoomies", Kind.BUBBLE_WRAP: "pu_bubble", Kind.SNACK: "pu_snack", Kind.TREAT: "pu_treat",
	Kind.SKATES: "pu_skates",
}
## The ring round the bubble.
const COLORS := {
	Kind.ZOOMIES: Color("ffd84d"), Kind.BUBBLE_WRAP: Color("9fd8ff"), Kind.SNACK: Color("8ff0a4"),
	Kind.TREAT: Color("e0b8ff"), Kind.WEAPON: Color("ff8f6b"), Kind.TOOL: Color("ffd84d"), Kind.SKATES: Color("ff9fd0"),
}
## Each cleanup tool's name (by the chore it's for).
const TOOLS := {
	Chores.Chore.FLOOR: "the Turbo Bag", Chores.Chore.CLUTTER: "the Catnip", Chores.Chore.STAIN: "the Bass Booster",
	Chores.Chore.FETCH: "the Squeaky Ball", Chores.Chore.SOFT: "the Warm Blanket", Chores.Chore.REPAIR: "the Duct Tape",
	Chores.Chore.LIFT: "the Winch", Chores.Chore.HIGH: "the Step Ladder",
}

## How likely each kind is to turn up.
const WAR_ODDS := {Kind.ZOOMIES: 2, Kind.BUBBLE_WRAP: 2, Kind.SNACK: 2, Kind.TREAT: 1, Kind.WEAPON: 3}
const CLEANUP_ODDS := {Kind.TOOL: 3, Kind.SKATES: 1}

## When they turn up (seconds): the first one, then every so often, at most so
## many at once, and how long each one waits to be picked up.
const WAR_FIRST := 15.0
const WAR_EVERY := Vector2(14.0, 20.0)
const WAR_MAX := 3
const CLEANUP_FIRST := 4.0
const CLEANUP_EVERY := Vector2(8.0, 11.0)
const CLEANUP_MAX := 2
const LIFETIME := 20.0
const CLEANUP_LIFETIME := 14.0
## How close you have to get to pick one up (floor px).
const RADIUS := 13.0

## Effects.
const ZOOMIES_SPEED := 1.4
const ZOOMIES_TIME := 8.0
const SKATES_SPEED := 1.3
const SKATES_TIME := 10.0
const SNACK_HEAL := 50
const SHIELD := 40
const SHIELD_TIME := 12.0
const WEAPON_TIME := 12.0
## A turbo tool: its owner works their own chore this much faster, and their
## own move (vacuum, swat, fetch, THUMP) reaches this much further, for a while.
const TURBO_RATE := 1.75
const TURBO_REACH := 1.5
const TURBO_TIME := 12.0


## Picks a kind from a table of odds.
static func roll(odds: Dictionary) -> int:
	var total := 0
	for k: int in odds:
		total += odds[k]
	var r := randi() % total
	for k: int in odds:
		r -= odds[k]
		if r < 0:
			return k
	return odds.keys()[0]
