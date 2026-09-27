class_name Chores
extends RefCounted
## Cleanup by specialty: every job belongs to one kind of chore, and every chore
## to one character, who does it properly. Anyone else can help, much more
## slowly; heavy and high jobs need two helpers unless their owner does them.
## If nobody in the house owns a chore (that character isn't playing, or their
## player wandered off), its jobs become everyone's ("anyone", the grey hand).
##
##   FLOOR   Zoomba   fur, bolts, litter, plaster, crumbs, dirt: drives over them
##   CLUTTER Willow   books, toys, socks, magazines: runs over them and bats them under the couch
##   STAIN   Bass     scorch, yolk, scuffs, spills: holds interact to THUMP every stain nearby, through walls
##   FETCH   Pepper   knocked-over things: runs into them (strays get carried home in his mouth)
##   SOFT    Biscuit  pillows, saggy or shredded soft furniture: holds interact and kneads
##   REPAIR  Unit-7   cracked and wrecked hard furniture, taping a mended wall: holds interact
##   LIFT    Claw     heavy things, standing every wreck back up, a new wall panel: holds interact
##   HIGH    Kiwi     pictures and things that live up high, painting a mended wall: holds interact
##   REMOTE  anyone   carry it back to its rug

enum Chore { NONE, FLOOR, CLUTTER, STAIN, FETCH, SOFT, REPAIR, LIFT, HIGH, REMOTE }

## Who owns what.
const OWNER := {
	Chore.FLOOR: "zoomba", Chore.CLUTTER: "willow", Chore.STAIN: "bass", Chore.FETCH: "pepper",
	Chore.SOFT: "biscuit", Chore.REPAIR: "butler", Chore.LIFT: "claw", Chore.HIGH: "kiwi",
}
## The word each owner shouts at the whistle.
const VERB := {
	Chore.FLOOR: "VACUUM!", Chore.CLUTTER: "HIDE IT!", Chore.STAIN: "THUMP!", Chore.FETCH: "FETCH!",
	Chore.SOFT: "KNEAD!", Chore.REPAIR: "FIX IT!", Chore.LIFT: "LIFT!", Chore.HIGH: "UP HIGH!",
}
## How to do each chore, for the card at the bottom of the screen: holding
## interact at each job, or (for owners with a move of their own) their way.
const HOW := {
	Chore.FLOOR: "Hold {interact} by fur, dust and crumbs", Chore.CLUTTER: "Hold {interact} by books, toys and socks",
	Chore.STAIN: "Hold {interact} by stains", Chore.FETCH: "Hold {interact} by knocked-over things",
	Chore.SOFT: "Hold {interact} by cushions and saggy couches", Chore.REPAIR: "Hold {interact} by cracked and broken things",
	Chore.LIFT: "Hold {interact} by heavy things and wrecks", Chore.HIGH: "Hold {interact} by pictures and high things",
}
const MOVE_HOW := {
	Chore.FLOOR: "Drive over fur, dust and crumbs", Chore.CLUTTER: "Run over books and toys to hide them",
	Chore.STAIN: "Hold {interact} to THUMP the stains away", Chore.FETCH: "Run into knocked-over things ({interact}: drop)",
}
## The sound of doing it properly.
const SOUND := {
	Chore.FLOOR: "c_vacuum", Chore.CLUTTER: "c_swat", Chore.STAIN: "c_thump", Chore.FETCH: "c_fetch",
	Chore.SOFT: "c_knead", Chore.REPAIR: "c_hammer", Chore.LIFT: "c_whirr", Chore.HIGH: "c_flutter",
}

## Work rates: the owner, anyone else, and everyone when nobody owns the chore.
const OWNER_RATE := 1.0
const HELPER_RATE := 0.2
const ANYONE_RATE := 0.5
## Bass's Cleaning Playlist: anyone this close works this much faster.
const PLAYLIST_RATE := 1.2
const PLAYLIST_RADIUS := 80.0
## An owner who hasn't made progress on anything for this long stops counting.
const IDLE_TIME := 8.0

## Floor mess (Debris kinds): chore, seconds to clean at rate 1, tidiness weight.
## The weights are set so that after a big war every chore is roughly an equal
## share of the house: leave any one of them undone and it isn't spotless.
const DEBRIS := {
	"fur": [Chore.FLOOR, 0.5, 0.3], "bolts": [Chore.FLOOR, 0.5, 0.3], "litter": [Chore.FLOOR, 0.5, 0.3],
	"plaster": [Chore.FLOOR, 0.5, 0.3], "crumbs": [Chore.FLOOR, 0.5, 0.3], "dirt": [Chore.FLOOR, 0.5, 0.3],
	"garbage": [Chore.FLOOR, 0.5, 0.3],
	"book": [Chore.CLUTTER, 0.8, 1.3], "toy": [Chore.CLUTTER, 0.8, 1.3], "sock": [Chore.CLUTTER, 0.8, 1.3],
	"mag": [Chore.CLUTTER, 0.8, 1.3],
	"scorch": [Chore.STAIN, 1.0, 0.45], "yolk": [Chore.STAIN, 1.0, 0.45], "scuff": [Chore.STAIN, 1.0, 0.45],
	"spill": [Chore.STAIN, 1.0, 0.45],
	"pillow": [Chore.SOFT, 0.8, 1.4],
}

## Knocked-over things.
const TIPPED := [Chore.FETCH, 1.2, 2.5]
const STRAY := [Chore.FETCH, 1.2, 3.5]
const HEAVY := [Chore.LIFT, 1.5, 1.5]
const HIGH_ITEM := [Chore.HIGH, 1.2, 1.8]
## How far a knocked thing can be from home and still just be "tipped over" (floor px).
const STRAY_DISTANCE := 34.0

## What falls out of things when they're knocked over (by MessItem.spill_sprite
## or sprite_name): potting dirt and rubbish for Zoomba, books and toys for
## Willow, milk and pie for Bass.
const SPILLS := {
	"dirt": ["dirt"], "garbage": ["garbage"], "toys": ["toy", "sock"], "books": ["book", "mag"],
	"milk": ["spill"], "pie": ["spill"],
}
## Things that scatter a bit of themselves when knocked (by sprite_name).
const SCATTERS := {"books": ["book"], "toys": ["toy"], "basket": ["sock"]}
const CLUTTER_KINDS: Array[String] = ["book", "toy", "sock", "mag"]
## Furniture sheds one bit of clutter (or a pillow) per this much damage.
const SHED_EVERY := 25.0
## A fresh KO pile this close to one of the same kind makes that one bigger instead.
const MERGE_RADIUS := 12.0
## A pile grows by this much weight (and hold time) at a time, up to MAX_GROWTH.
const GROW_WEIGHT := 0.2
const GROW_TIME := 0.25
const MAX_GROWTH := 0.6

## Owner mechanics.
const VACUUM_RADIUS := 10.0
const SWAT_RADIUS := 12.0
const SWAT_TIME := 0.4
const FETCH_RADIUS := 12.0
const DELIVER_RADIUS := 16.0
const THUMP_RADIUS := 48.0
const THUMP_TIME := 0.7


## The chore a character owns (Chore.NONE for none).
static func owned_by(char_id: String) -> int:
	for c: int in OWNER:
		if OWNER[c] == char_id:
			return c
	return Chore.NONE


## How to do `chore`; `own_move` if this is the owner's own character.
static func how(chore: int, own_move: bool) -> String:
	if own_move and MOVE_HOW.has(chore):
		return MOVE_HOW[chore]
	return HOW.get(chore, "Hold {interact} by anything to help")


static func face(chore: int) -> String:
	return "face_" + String(OWNER[chore]) if OWNER.has(chore) else "face_anyone"


## How fast someone works on `chore`: its owner at full speed, anyone else at
## a fifth, or everyone at half when nobody owns it. `owners` maps each chore to
## the pids who own it and are actively cleaning (see Match.chore_owners).
static func rate(is_owner: bool, chore: int, owners: Dictionary) -> float:
	if chore == Chore.REMOTE or chore == Chore.NONE or is_owner:
		return OWNER_RATE
	return ANYONE_RATE if owners.get(chore, []).is_empty() else HELPER_RATE


## Do non-owners need a second pair of hands for this? (Only while its owner is around.)
static func needs_two(chore: int, owners: Dictionary) -> bool:
	return (chore == Chore.LIFT or chore == Chore.HIGH) and not owners.get(chore, []).is_empty()
