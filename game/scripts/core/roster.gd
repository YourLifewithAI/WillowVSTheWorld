class_name Roster
extends RefCounted
## Every playable character: their ridiculous weapon, their special move,
## what they're great at and what gets them KO'd. This is the balance sheet.
##
## Distances are in floor pixels (see Iso), times in seconds, speeds in floor
## pixels per second. "demolition" is damage dealt to furniture.
##
## "spread" is the whole cone in degrees: several pellets fan across it, a
## single shot wobbles randomly within it.
##
## Weapon kinds:
##   MELEE  swing in a cone in front of you (range, arc)
##   SHOT   straight projectiles (speed, range, count, spread, hit_radius, pierce)
##   LOB    arcing shells that explode where they land (speed, range, arc, explode_radius)
##
## Trait keys (all optional):
##   sneaky        invisible to enemies after standing still for a moment
##   low_profile   can drive under furniture, hidden while underneath
##   reveal        radius within which hidden enemies show up for your whole team
##   knock_mult    how far you get knocked (0.5 = half, 1.6 = 60% further)
##   flips         a big hit leaves you upside down and stunned
##   butterfingers any hit makes you drop the remote
##   reboot        extra seconds before respawning after a KO
##   dash_mult     shorter (or longer) dash
##   handy         counts as two helpers when fixing, and tidies fast
##   strong        counts as two helpers when fixing
##   playlist      nearby allies tidy faster during cleanup
##   vacuum        cleans debris just by driving over it (cleanup)
##   clumsy        knocks light things over just by walking into them

enum Team { PETS, ROBOTS }
enum Weapon { MELEE, SHOT, LOB }
enum Special { SLAM, PROJECTILE, PULL, AURA, VANISH }

const TEAM_NAMES: Array[String] = ["Pets", "Robots"]
const TEAM_COLORS: Array[Color] = [Color("ff9f68"), Color("62d6ff")]
const TEAM_SHOWS: Array[String] = ["Birds of the Rainforest", "Robot Rumble Reruns"]

const CHARACTERS := {
	# ------------------------------------------------------------------ PETS
	"willow": {
		"name": "Willow", "team": Team.PETS, "species": "Tabby Cat", "role": "Assassin",
		"blurb": "Fast, fragile, and absolutely going to knock that off the table.",
		"hp": 65, "speed": 150.0, "flying": false, "hover": 0.0,
		"weapon": {"name": "Laser Pointer Blaster", "kind": Weapon.SHOT, "damage": 10, "knock": 70.0,
			"cooldown": 0.26, "speed": 440.0, "range": 180.0, "count": 1, "spread": 0.0,
			"hit_radius": 5.0, "look": "laser", "demolition": 8.0,
			"sprite": "w_laser", "hold": Vector2(8, -5)},
		"special": {"name": "Vanish", "kind": Special.VANISH, "cooldown": 9.0, "duration": 4.0},
		"sneaky": true, "clumsy": true,
		"strength": "Sneaky: invisible to enemies whenever she sits still. Vanish keeps her invisible on the move, and her first hit from hiding does double damage.",
		"weakness": "Fragile: the lowest health in the house.",
		"tidy": 0.75, "carry_speed": 0.8,
		"tidy_note": "Cats are terrible at chores.",
	},
	"biscuit": {
		"name": "Biscuit", "team": Team.PETS, "species": "Chonky Cat", "role": "Demolisher",
		"blurb": "A loaf with a lot of momentum and a bazooka full of catnip.",
		"hp": 150, "speed": 105.0, "flying": false, "hover": 0.0, "knock_mult": 0.5,
		"weapon": {"name": "Catnip Bazooka", "kind": Weapon.LOB, "damage": 20, "knock": 240.0,
			"cooldown": 1.1, "speed": 230.0, "range": 120.0, "arc": 26.0, "explode_radius": 30.0,
			"look": "rocket", "demolition": 60.0, "decal": "scorch",
			"sprite": "w_bazooka", "hold": Vector2(1, -12)},
		"special": {"name": "Belly Flop", "kind": Special.SLAM, "cooldown": 6.0, "damage": 24,
			"radius": 46.0, "knock": 320.0, "stun": 0.4, "windup": 0.35, "rise": 16.0, "demolition": 80.0},
		"sneaky": true, "clumsy": true,
		"strength": "Heavy: shrugs off half of all knockback. Also a cat, so she vanishes whenever she sits still (which is always).",
		"weakness": "Slow: the slowest thing in the house, and the bazooka takes a while to reload.",
		"tidy": 0.6, "carry_speed": 0.75,
		"tidy_note": "Mostly supervises.",
	},
	"pepper": {
		"name": "Pepper", "team": Team.PETS, "species": "Pup", "role": "Tracker",
		"blurb": "Loyal, loud, and carrying a tennis ball gatling gun.",
		"hp": 110, "speed": 140.0, "flying": false, "hover": 0.0, "reveal": 70.0, "butterfingers": true,
		"weapon": {"name": "Tennis Ball Gatling", "kind": Weapon.SHOT, "damage": 5, "knock": 45.0,
			"cooldown": 0.11, "speed": 330.0, "range": 150.0, "count": 1, "spread": 14.0,
			"hit_radius": 4.0, "look": "ball", "demolition": 4.0,
			"sprite": "w_gatling", "hold": Vector2(9, -6)},
		"special": {"name": "Big Bark", "kind": Special.PROJECTILE, "cooldown": 5.0, "damage": 8,
			"knock": 260.0, "stun": 0.8, "count": 1, "spread": 0.0, "speed": 240.0,
			"range": 150.0, "hit_radius": 16.0, "look": "bark", "pierce": true, "demolition": 20.0},
		"strength": "Good Nose: sniffs out invisible cats and hidden Roombas near him, and shows them to his whole team.",
		"weakness": "Butterfingers: drops the remote whenever he gets hit.",
		"tidy": 1.25, "carry_speed": 0.9,
		"tidy_note": "Fetches things back where they belong.",
	},
	"kiwi": {
		"name": "Kiwi", "team": Team.PETS, "species": "Budgie", "role": "Bomber",
		"blurb": "Flies over everything. Drops eggs on everything.",
		"hp": 60, "speed": 145.0, "flying": true, "hover": 18.0, "knock_mult": 1.6,
		"weapon": {"name": "Egg Bombs", "kind": Weapon.LOB, "damage": 14, "knock": 140.0,
			"cooldown": 0.45, "speed": 70.0, "range": 12.0, "arc": 0.0, "explode_radius": 20.0,
			"look": "egg", "demolition": 30.0, "decal": "yolk"},
		"special": {"name": "Feather Flurry", "kind": Special.PROJECTILE, "cooldown": 3.5, "damage": 9,
			"knock": 110.0, "stun": 0.0, "count": 3, "spread": 36.0, "speed": 280.0,
			"range": 170.0, "hit_radius": 8.0, "look": "feather", "pierce": false, "demolition": 6.0},
		"strength": "Flight: flies over furniture, bombs whatever is underneath, and can't be caught by slams or suction.",
		"weakness": "Featherweight: tiny health, and every hit sends her flying 60% further.",
		"tidy": 1.0, "carry_speed": 0.7,
		"tidy_note": "Can reach the high shelves.",
	},
	# ---------------------------------------------------------------- ROBOTS
	"zoomba": {
		"name": "Zoomba", "team": Team.ROBOTS, "species": "Robot Vacuum", "role": "Ambusher",
		"blurb": "Hides under the couch. Waits. Strikes.",
		"hp": 90, "speed": 155.0, "flying": false, "hover": 0.0,
		"low_profile": true, "flips": true, "vacuum": true,
		"weapon": {"name": "Dust Cannon", "kind": Weapon.SHOT, "damage": 6, "knock": 70.0,
			"cooldown": 0.55, "speed": 300.0, "range": 70.0, "count": 5, "spread": 36.0,
			"hit_radius": 5.0, "look": "dust", "demolition": 4.0,
			"sprite": "w_dustcannon", "hold": Vector2(-2, -10)},
		"special": {"name": "Turbo Suck", "kind": Special.PULL, "cooldown": 5.0, "damage": 6,
			"radius": 90.0, "knock": 230.0, "stun": 0.4},
		"strength": "Low Profile: drives under furniture and stays hidden there. Bursting out for a surprise attack does double damage and dazes.",
		"weakness": "Flips Over: a big hit leaves it upside down and helpless for a second and a half.",
		"tidy": 1.0, "carry_speed": 0.8,
		"tidy_note": "Vacuums up debris just by driving over it.",
	},
	"butler": {
		"name": "Unit-7", "team": Team.ROBOTS, "species": "Helper Bot", "role": "Engineer",
		"blurb": "Programmed to serve. Reprogrammed to fire toast.",
		"hp": 140, "speed": 110.0, "flying": false, "hover": 0.0,
		"reveal": 120.0, "handy": true, "dash_mult": 0.7,
		"weapon": {"name": "Toaster Cannon", "kind": Weapon.LOB, "damage": 16, "knock": 160.0,
			"cooldown": 0.6, "speed": 240.0, "range": 110.0, "arc": 20.0, "explode_radius": 18.0,
			"look": "toast", "demolition": 35.0, "decal": "scorch",
			"sprite": "w_toaster", "hold": Vector2(8, -9)},
		"special": {"name": "Rocket Fist", "kind": Special.PROJECTILE, "cooldown": 5.0, "damage": 22,
			"knock": 300.0, "stun": 0.3, "count": 1, "spread": 0.0, "speed": 300.0,
			"range": 220.0, "hit_radius": 9.0, "look": "rocket_fist", "pierce": false, "demolition": 60.0},
		"strength": "X-Ray Vision + Handy: spots invisible and hidden enemies from far away (for the whole team), and rebuilds anything twice as fast, even big furniture on its own.",
		"weakness": "Clunky: slow, with a short, stiff dash.",
		"tidy": 2.0, "carry_speed": 0.8,
		"tidy_note": "Literally built for this.",
	},
	"claw": {
		"name": "The Claw", "team": Team.ROBOTS, "species": "Ceiling Gantry", "role": "Wrecker",
		"blurb": "Rides the ceiling rails. Swings a wrecking ball. Indoors.",
		"hp": 75, "speed": 140.0, "flying": true, "hover": 40.0, "strong": true, "reboot": 3.0,
		"weapon": {"name": "Wrecking Ball", "kind": Weapon.MELEE, "damage": 18, "knock": 260.0,
			"cooldown": 0.75, "range": 32.0, "arc": 200.0, "demolition": 70.0,
			"sprite": "w_wreckingball", "hold": Vector2(0, 5)},
		"special": {"name": "Claw Drop", "kind": Special.SLAM, "cooldown": 5.5, "damage": 24,
			"radius": 34.0, "knock": 180.0, "stun": 0.9, "windup": 0.45, "rise": -34.0, "demolition": 60.0},
		"strength": "Ceiling Rider + Strong: glides over all the furniture, flattens whatever it swings at, and lifts heavy things alone.",
		"weakness": "Long Reboot: takes three extra seconds to come back after a KO.",
		"tidy": 1.0, "carry_speed": 0.8,
		"tidy_note": "Lifts heavy things on its own.",
	},
	"bass": {
		"name": "Bass", "team": Team.ROBOTS, "species": "Smart Speaker", "role": "Support",
		"blurb": "Drops beats. Drops shelves. Heals the squad.",
		"hp": 100, "speed": 120.0, "flying": false, "hover": 0.0, "playlist": true, "dash_mult": 0.5,
		"weapon": {"name": "Subwoofer Cannon", "kind": Weapon.SHOT, "damage": 11, "knock": 170.0,
			"cooldown": 0.5, "speed": 200.0, "range": 130.0, "count": 1, "spread": 0.0,
			"hit_radius": 10.0, "look": "ring", "pierce": true, "through_walls": true, "demolition": 15.0},
		"special": {"name": "Hype Track", "kind": Special.AURA, "cooldown": 8.0, "radius": 75.0,
			"heal": 30, "speed_mult": 1.35, "duration": 3.0},
		"strength": "Cleaning Playlist: during cleanup, everyone near Bass tidies 30% faster. Its bass waves go straight through furniture.",
		"weakness": "No Legs: hops instead of running, so its dash is tiny.",
		"tidy": 1.0, "carry_speed": 0.8,
		"tidy_note": "Cleaning music makes everything go faster.",
	},
}


static func get_char(id: String) -> Dictionary:
	return CHARACTERS.get(id, CHARACTERS["willow"])


static func ids_for_team(team: int) -> Array[String]:
	var out: Array[String] = []
	for id: String in CHARACTERS:
		if CHARACTERS[id]["team"] == team:
			out.append(id)
	return out


static func texture(sprite_name: String) -> Texture2D:
	return load("res://assets/sprites/%s.png" % sprite_name) as Texture2D


## The weapon (ability 0) or special (ability 1) of a character.
static func ability(data: Dictionary, which: int) -> Dictionary:
	return data["weapon"] if which == 0 else data["special"]
