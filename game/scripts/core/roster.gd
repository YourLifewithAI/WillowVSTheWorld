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
## Sounds: "sfx" plays when a move is used, "hit_sfx" where a lobbed shell
## lands, "land_sfx" when a slam lands, and "swing_sfx" for each swing of a gag
## weapon. "voice" picks the character's hello / KO noises (hi_<voice>, ko_<voice>),
## pitched by "voice_pitch". All of them are names in res://assets/sounds.
##
## Close-up moves ("melee", ability index 3, the right button when you aren't
## carrying the remote): a swing in a cone (range, arc) with an optional effect:
##   lunge        hop effect_value px forward first, then swing where you land
##   drain        heal yourself for effect_value x the damage dealt
##   steal        take the remote from the carrier you hit
##   shove_items  knock things over with effect_value force (200+ topples heavy ones)
##   knockup      pop the target effect_value px into the air (use "stun" for the daze)
##   pull         yank the target toward you instead of away
## "look" picks the swing's visuals and its sound (m_<look>).
##
## Gags are each character's big silly move. They charge up during the war
## (faster when you land hits) and play to that character's strengths.
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
##   playlist      everyone nearby works faster during cleanup
##   clumsy        knocks light things over just by walking into them

enum Team { PETS, ROBOTS }
enum Weapon { MELEE, SHOT, LOB }
enum Special { SLAM, PROJECTILE, PULL, AURA, VANISH }
## Every character's big, silly, charge-up move (ability index 2).
enum Gag { LITTER, BONE, FLOCK, MEGA_SUCK, SATELLITE, CLAW_MACHINE, DANCE }

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
			"hit_radius": 5.0, "look": "laser", "demolition": 8.0, "sfx": "laser",
			"sprite": "w_laser", "hold": Vector2(8, -5)},
		"special": {"name": "Vanish", "kind": Special.VANISH, "cooldown": 9.0, "duration": 4.0, "sfx": "poof"},
		"melee": {"name": "Pounce", "damage": 12, "knock": 90.0, "stun": 0.0, "range": 18.0, "arc": 90.0,
			"cooldown": 1.4, "demolition": 6.0, "effect": "lunge", "effect_value": 28.0, "look": "swipe",
			"blurb": "Wiggle, hop forward and swipe. Catches runaway carriers, and hits twice as hard from hiding."},
		"gag": {"name": "Litter Bomb", "kind": Gag.LITTER, "speed": 200.0, "range": 110.0, "arc": 30.0,
			"explode_radius": 18.0, "damage": 10, "knock": 150.0, "demolition": 20.0, "look": "litter",
			"sfx": "lob", "cloud_radius": 46.0, "cloud_time": 7.0,
			"blurb": "Lob a whole litter box. The dust cloud keeps cats invisible even while they run, bogs everyone else down, and leaves litter everywhere."},
		"sneaky": true, "clumsy": true, "voice": "cat", "voice_pitch": 1.15,
		"strength": "Sneaky: invisible to enemies whenever she sits still. Vanish keeps her invisible on the move, and her first hit from hiding does double damage.",
		"weakness": "Fragile: the lowest health in the house.",
		"carry_speed": 0.8,
		"tidy_note": "Run over books and toys to hide them",
	},
	"biscuit": {
		"name": "Biscuit", "team": Team.PETS, "species": "Chonky Cat", "role": "Demolisher",
		"blurb": "A loaf with a lot of momentum and a bazooka full of catnip.",
		"hp": 150, "speed": 105.0, "flying": false, "hover": 0.0, "knock_mult": 0.5,
		"weapon": {"name": "Catnip Bazooka", "kind": Weapon.LOB, "damage": 20, "knock": 240.0,
			"cooldown": 1.1, "speed": 230.0, "range": 120.0, "arc": 26.0, "explode_radius": 30.0,
			"look": "rocket", "demolition": 60.0, "decal": "scorch", "sfx": "bazooka", "hit_sfx": "boom",
			"sprite": "w_bazooka", "hold": Vector2(1, -12)},
		"special": {"name": "Belly Flop", "kind": Special.SLAM, "cooldown": 6.0, "damage": 24,
			"radius": 46.0, "knock": 320.0, "stun": 0.4, "windup": 0.35, "rise": 16.0, "demolition": 80.0,
			"sfx": "jump", "land_sfx": "slam"},
		"melee": {"name": "Making Biscuits", "damage": 6, "knock": 30.0, "stun": 0.0, "range": 18.0, "arc": 110.0,
			"cooldown": 0.5, "demolition": 15.0, "effect": "drain", "effect_value": 0.5, "look": "knead",
			"blurb": "Knead whoever is in front, purring. Every knead heals her for half the damage (and shreds the couch)."},
		"gag": {"name": "Litter Bomb", "kind": Gag.LITTER, "speed": 200.0, "range": 110.0, "arc": 30.0,
			"explode_radius": 18.0, "damage": 10, "knock": 150.0, "demolition": 20.0, "look": "litter",
			"sfx": "lob", "cloud_radius": 58.0, "cloud_time": 7.0,
			"blurb": "Lob an extra-large (chonky) litter box. The dust cloud keeps cats invisible even while they run, bogs everyone else down, and leaves litter everywhere."},
		"sneaky": true, "clumsy": true, "voice": "cat", "voice_pitch": 0.8,
		"strength": "Heavy: shrugs off half of all knockback. Also a cat, so she vanishes whenever she sits still (which is always).",
		"weakness": "Slow: the slowest thing in the house, and the bazooka takes a while to reload.",
		"carry_speed": 0.75,
		"tidy_note": "Hold {interact} by cushions and saggy couches",
	},
	"pepper": {
		"name": "Pepper", "team": Team.PETS, "species": "Pup", "role": "Tracker",
		"blurb": "Loyal, loud, and carrying a tennis ball gatling gun.",
		"hp": 110, "speed": 140.0, "flying": false, "hover": 0.0, "reveal": 70.0, "butterfingers": true,
		"voice": "dog",
		"weapon": {"name": "Tennis Ball Gatling", "kind": Weapon.SHOT, "damage": 5, "knock": 45.0,
			"cooldown": 0.11, "speed": 330.0, "range": 150.0, "count": 1, "spread": 14.0,
			"hit_radius": 4.0, "look": "ball", "demolition": 4.0, "sfx": "ball",
			"sprite": "w_gatling", "hold": Vector2(9, -6)},
		"special": {"name": "Big Bark", "kind": Special.PROJECTILE, "cooldown": 5.0, "damage": 8,
			"knock": 260.0, "stun": 0.8, "count": 1, "spread": 0.0, "speed": 240.0,
			"range": 150.0, "hit_radius": 16.0, "look": "bark", "pierce": true, "demolition": 20.0, "sfx": "bark"},
		"melee": {"name": "Gimme!", "damage": 5, "knock": 50.0, "stun": 0.0, "range": 18.0, "arc": 70.0,
			"cooldown": 2.0, "demolition": 0.0, "effect": "steal", "effect_value": 0.0, "look": "chomp",
			"blurb": "A quick bite that snatches the remote right out of the carrier's hands."},
		"gag": {"name": "Big Bone", "kind": Gag.BONE, "duration": 8.0, "damage": 22, "knock": 420.0,
			"range": 30.0, "arc": 170.0, "cooldown": 0.45, "demolition": 60.0, "sfx": "tada", "swing_sfx": "whoosh",
			"sprite": "w_bone", "hold": Vector2(0, 2),
			"blurb": "Swaps the gatling for a giant bone. Every whack is a home run, and a dog never lets go of a bone: no dropping the remote while he's holding it."},
		"strength": "Good Nose: sniffs out invisible cats and hidden Roombas near him, and shows them to his whole team.",
		"weakness": "Butterfingers: drops the remote whenever he gets hit.",
		"carry_speed": 0.9,
		"tidy_note": "Run into knocked-over things",
	},
	"kiwi": {
		"name": "Kiwi", "team": Team.PETS, "species": "Budgie", "role": "Bomber",
		"blurb": "Flies over everything. Drops eggs on everything.",
		"hp": 60, "speed": 145.0, "flying": true, "hover": 18.0, "knock_mult": 1.6, "voice": "bird",
		"weapon": {"name": "Egg Bombs", "kind": Weapon.LOB, "damage": 14, "knock": 140.0,
			"cooldown": 0.45, "speed": 70.0, "range": 12.0, "arc": 0.0, "explode_radius": 20.0,
			"look": "egg", "demolition": 30.0, "decal": "yolk", "sfx": "egg_drop", "hit_sfx": "splat"},
		"special": {"name": "Feather Flurry", "kind": Special.PROJECTILE, "cooldown": 3.5, "damage": 9,
			"knock": 110.0, "stun": 0.0, "count": 3, "spread": 36.0, "speed": 280.0,
			"range": 170.0, "hit_radius": 8.0, "look": "feather", "pierce": false, "demolition": 6.0, "sfx": "feathers"},
		"melee": {"name": "Peck Peck Peck", "damage": 3, "knock": 20.0, "stun": 0.0, "range": 16.0, "arc": 60.0,
			"cooldown": 0.18, "demolition": 2.0, "effect": "shove_items", "effect_value": 260.0, "look": "peck",
			"blurb": "Mash it. Tiny pecks that keep interrupting a carrier, and topple even the heavy shelves."},
		"gag": {"name": "Flock Call", "kind": Gag.FLOCK, "damage": 14, "knock": 260.0, "length": 280.0,
			"width": 34.0, "speed_mult": 1.6, "duration": 3.5, "sfx": "flock",
			"blurb": "Calls in the whole flock. A stampede of budgies sweeps the room, bowling everyone over, and Kiwi rides along at top speed."},
		"strength": "Flight: flies over furniture, bombs whatever is underneath, and can't be caught by slams or suction.",
		"weakness": "Featherweight: tiny health, and every hit sends her flying 60% further.",
		"carry_speed": 0.7,
		"tidy_note": "Hold {interact} by pictures and high things",
	},
	# ---------------------------------------------------------------- ROBOTS
	"zoomba": {
		"name": "Zoomba", "team": Team.ROBOTS, "species": "Robot Vacuum", "role": "Ambusher",
		"blurb": "Hides under the couch. Waits. Strikes.",
		"hp": 90, "speed": 155.0, "flying": false, "hover": 0.0,
		"low_profile": true, "flips": true, "voice": "vacuum",
		"weapon": {"name": "Dust Cannon", "kind": Weapon.SHOT, "damage": 6, "knock": 70.0,
			"cooldown": 0.55, "speed": 300.0, "range": 70.0, "count": 5, "spread": 36.0,
			"hit_radius": 5.0, "look": "dust", "demolition": 4.0, "sfx": "dust",
			"sprite": "w_dustcannon", "hold": Vector2(-2, -10)},
		"special": {"name": "Turbo Suck", "kind": Special.PULL, "cooldown": 5.0, "damage": 6,
			"radius": 90.0, "knock": 230.0, "stun": 0.4, "sfx": "suck"},
		"melee": {"name": "Spot Clean", "damage": 8, "knock": 170.0, "stun": 0.0, "range": 20.0, "arc": 360.0,
			"cooldown": 1.5, "demolition": 0.0, "effect": "", "effect_value": 0.0, "look": "spin",
			"blurb": "Spin in place and fling everyone around you away. No aiming needed (great from under the couch)."},
		"gag": {"name": "Mega Suck", "kind": Gag.MEGA_SUCK, "duration": 3.0, "radius": 110.0, "pull": 260.0,
			"swallow_time": 2.0, "damage": 18, "knock": 380.0, "stun": 0.5, "sfx": "vacuum",
			"blurb": "Maximum suction. Drags everyone nearby in and swallows anyone who gets too close, remote and all, then spits them across the room."},
		"strength": "Low Profile: drives under furniture and stays hidden there. Bursting out for a surprise attack does double damage and dazes.",
		"weakness": "Flips Over: a big hit leaves it upside down and helpless for a second and a half.",
		"carry_speed": 0.8,
		"tidy_note": "Drive over fur, dust and crumbs",
	},
	"butler": {
		"name": "Unit-7", "team": Team.ROBOTS, "species": "Helper Bot", "role": "Engineer",
		"blurb": "Programmed to serve. Reprogrammed to fire toast.",
		"hp": 140, "speed": 110.0, "flying": false, "hover": 0.0,
		"reveal": 120.0, "dash_mult": 0.7, "voice": "robot",
		"weapon": {"name": "Toaster Cannon", "kind": Weapon.LOB, "damage": 16, "knock": 160.0,
			"cooldown": 0.6, "speed": 240.0, "range": 110.0, "arc": 20.0, "explode_radius": 18.0,
			"look": "toast", "demolition": 35.0, "decal": "scorch", "sfx": "toaster", "hit_sfx": "boom",
			"sprite": "w_toaster", "hold": Vector2(8, -9)},
		"special": {"name": "Rocket Fist", "kind": Special.PROJECTILE, "cooldown": 5.0, "damage": 22,
			"knock": 300.0, "stun": 0.3, "count": 1, "spread": 0.0, "speed": 300.0,
			"range": 220.0, "hit_radius": 9.0, "look": "rocket_fist", "pierce": false, "demolition": 60.0, "sfx": "rocket"},
		"melee": {"name": "Spatula Flip", "damage": 8, "knock": 30.0, "stun": 0.6, "range": 20.0, "arc": 90.0,
			"cooldown": 3.5, "demolition": 0.0, "effect": "knockup", "effect_value": 20.0, "look": "flip",
			"blurb": "Flips whoever is in front into the air like a pancake: helpless for a moment."},
		"gag": {"name": "Satellite Laser", "kind": Gag.SATELLITE, "delay": 1.2, "radius": 38.0, "damage": 40,
			"knock": 320.0, "stun": 0.4, "demolition": 150.0, "reach": 150.0, "scan": 6.0,
			"blurb": "Calls down an orbital laser on the nearest enemy (or straight ahead). The satellite also scans the house: every hidden pet shows up for the whole robot team."},
		"strength": "X-Ray Vision: spots invisible and hidden enemies from far away, for the whole team.",
		"weakness": "Clunky: slow, with a short, stiff dash.",
		"carry_speed": 0.8,
		"tidy_note": "Hold {interact} by cracked and broken things",
	},
	"claw": {
		"name": "The Claw", "team": Team.ROBOTS, "species": "Ceiling Gantry", "role": "Wrecker",
		"blurb": "Rides the ceiling rails. Swings a wrecking ball. Indoors.",
		"hp": 75, "speed": 140.0, "flying": true, "hover": 40.0, "reboot": 3.0, "voice": "claw",
		"weapon": {"name": "Wrecking Ball", "kind": Weapon.MELEE, "damage": 18, "knock": 260.0,
			"cooldown": 0.75, "range": 32.0, "arc": 200.0, "demolition": 70.0, "sfx": "whoosh",
			"sprite": "w_wreckingball", "hold": Vector2(0, 5)},
		"special": {"name": "Claw Drop", "kind": Special.SLAM, "cooldown": 5.5, "damage": 24,
			"radius": 34.0, "knock": 180.0, "stun": 0.9, "windup": 0.45, "rise": -34.0, "demolition": 60.0,
			"sfx": "servo", "land_sfx": "clank"},
		"melee": {"name": "Yoink!", "damage": 6, "knock": 190.0, "stun": 0.3, "range": 26.0, "arc": 60.0,
			"cooldown": 2.2, "demolition": 0.0, "effect": "pull", "effect_value": 0.0, "look": "yoink",
			"blurb": "Grabs whoever is in front and reels them in under the claw, dazed."},
		"gag": {"name": "Claw Machine", "kind": Gag.CLAW_MACHINE, "radius": 40.0, "hold": 3.0, "damage": 20,
			"knock": 120.0, "stun": 1.0, "sfx": "claw_machine",
			"blurb": "Just like the arcade: grabs whoever is underneath and carries them around the ceiling. If they had the remote, it's the Claw's now."},
		"strength": "Ceiling Rider: glides over all the furniture and flattens whatever it swings at.",
		"weakness": "Long Reboot: takes three extra seconds to come back after a KO.",
		"carry_speed": 0.8,
		"tidy_note": "Hold {interact} by heavy things and wrecks",
	},
	"bass": {
		"name": "Bass", "team": Team.ROBOTS, "species": "Smart Speaker", "role": "Support",
		"blurb": "Drops beats. Drops shelves. Heals the squad.",
		"hp": 100, "speed": 120.0, "flying": false, "hover": 0.0, "playlist": true, "dash_mult": 0.5,
		"voice": "speaker",
		"weapon": {"name": "Subwoofer Cannon", "kind": Weapon.SHOT, "damage": 11, "knock": 170.0,
			"cooldown": 0.5, "speed": 200.0, "range": 130.0, "count": 1, "spread": 0.0,
			"hit_radius": 10.0, "look": "ring", "pierce": true, "through_walls": true, "demolition": 15.0,
			"sfx": "sub"},
		"special": {"name": "Hype Track", "kind": Special.AURA, "cooldown": 8.0, "radius": 75.0,
			"heal": 30, "speed_mult": 1.35, "duration": 3.0, "sfx": "hype"},
		"melee": {"name": "Feedback", "damage": 4, "knock": 330.0, "stun": 0.0, "range": 22.0, "arc": 150.0,
			"cooldown": 2.5, "demolition": 10.0, "effect": "", "effect_value": 0.0, "look": "feedback",
			"blurb": "An ear-splitting squeal that blasts everyone in front far away (shelves too)."},
		"gag": {"name": "Dance Party", "kind": Gag.DANCE, "radius": 110.0, "duration": 2.8, "heal": 25, "sfx": "disco",
			"blurb": "Drops the beat so hard that every enemy nearby has to dance. Allies on the dance floor heal up."},
		"strength": "Cleaning Playlist: during cleanup, everyone near Bass works 20% faster. Its bass waves go straight through furniture.",
		"weakness": "No Legs: hops instead of running, so its dash is tiny.",
		"carry_speed": 0.8,
		"tidy_note": "Hold {interact} to THUMP the stains away",
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


## Kept once loaded: something drawn with draw_texture() in _draw() only holds
## the texture's id, so a texture nobody else holds on to would be freed straight
## after (and drawn as a white square).
static var _textures: Dictionary = {}


static func texture(sprite_name: String) -> Texture2D:
	if not _textures.has(sprite_name):
		_textures[sprite_name] = load("res://assets/sprites/%s.png" % sprite_name) as Texture2D
	return _textures[sprite_name]


## Lets go of the textures (on the way out, so nothing counts as leaked).
static func forget_textures() -> void:
	_textures.clear()


## The weapon (ability 0), special (1), gag (2) or melee move (3) of a character.
static func ability(data: Dictionary, which: int) -> Dictionary:
	match which:
		0:
			return data["weapon"]
		1:
			return data["special"]
		3:
			return data["melee"]
	return data["gag"]
