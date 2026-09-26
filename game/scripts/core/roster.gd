class_name Roster
extends RefCounted
## Every playable character, and the numbers that make them feel different.
##
## Distances are in floor pixels (see Iso), times in seconds, speeds in floor
## pixels per second. Tweak freely: this is the balance sheet.

enum Team { PETS, ROBOTS }
enum Special { LEAP, SLAM, PROJECTILE, PULL, AURA }

const TEAM_NAMES: Array[String] = ["Pets", "Robots"]
const TEAM_COLORS: Array[Color] = [Color("ff9f68"), Color("62d6ff")]
const TEAM_SHOWS: Array[String] = ["Birds of the Rainforest", "Robot Rumble Reruns"]

const CHARACTERS := {
	# ------------------------------------------------------------------ PETS
	"willow": {
		"name": "Willow", "team": Team.PETS, "species": "Tabby Cat", "role": "Speedster",
		"blurb": "Fast, fragile, and absolutely going to knock that off the table.",
		"hp": 80, "speed": 150.0, "flying": false, "hover": 0.0,
		"attack": {"name": "Swipe", "damage": 16, "range": 22.0, "arc": 110.0, "knock": 150.0, "cooldown": 0.3},
		"special": {"name": "Pounce", "kind": Special.LEAP, "cooldown": 4.0, "damage": 20,
			"radius": 30.0, "knock": 240.0, "stun": 0.2, "distance": 95.0, "duration": 0.38},
		"tidy": 0.75, "carry_speed": 0.8, "clumsy": true,
		"tidy_note": "Cats are not great at chores. Knocks things over just by walking past.",
	},
	"biscuit": {
		"name": "Biscuit", "team": Team.PETS, "species": "Chonky Cat", "role": "Tank",
		"blurb": "A loaf with a lot of momentum.",
		"hp": 150, "speed": 115.0, "flying": false, "hover": 0.0,
		"attack": {"name": "Paw Smack", "damage": 22, "range": 24.0, "arc": 120.0, "knock": 200.0, "cooldown": 0.45},
		"special": {"name": "Belly Flop", "kind": Special.SLAM, "cooldown": 6.0, "damage": 24,
			"radius": 46.0, "knock": 320.0, "stun": 0.4, "windup": 0.35, "rise": 16.0},
		"tidy": 0.6, "carry_speed": 0.75, "clumsy": true,
		"tidy_note": "Mostly supervises. Knocks things over just by walking past.",
	},
	"pepper": {
		"name": "Pepper", "team": Team.PETS, "species": "Pup", "role": "Bruiser",
		"blurb": "Loyal, loud, and very good at fetching the remote.",
		"hp": 110, "speed": 135.0, "flying": false, "hover": 0.0,
		"attack": {"name": "Chomp", "damage": 19, "range": 22.0, "arc": 90.0, "knock": 170.0, "cooldown": 0.35},
		"special": {"name": "Big Bark", "kind": Special.PROJECTILE, "cooldown": 5.0, "damage": 8,
			"knock": 260.0, "stun": 0.8, "count": 1, "spread": 0.0, "speed": 240.0,
			"range": 150.0, "hit_radius": 16.0, "sprite": "", "pierce": true},
		"tidy": 1.25, "carry_speed": 0.9,
		"tidy_note": "Fetches things back where they belong.",
	},
	"kiwi": {
		"name": "Kiwi", "team": Team.PETS, "species": "Budgie", "role": "Flyer",
		"blurb": "Flies over furniture. Talks trash. Tiny.",
		"hp": 65, "speed": 145.0, "flying": true, "hover": 18.0,
		"attack": {"name": "Peck", "damage": 13, "range": 20.0, "arc": 90.0, "knock": 90.0, "cooldown": 0.25},
		"special": {"name": "Feather Flurry", "kind": Special.PROJECTILE, "cooldown": 3.5, "damage": 9,
			"knock": 110.0, "stun": 0.0, "count": 3, "spread": 18.0, "speed": 280.0,
			"range": 170.0, "hit_radius": 8.0, "sprite": "feather", "pierce": false},
		"tidy": 1.0, "carry_speed": 0.7,
		"tidy_note": "Can reach the high shelves.",
	},
	# ---------------------------------------------------------------- ROBOTS
	"zoomba": {
		"name": "Zoomba", "team": Team.ROBOTS, "species": "Robot Vacuum", "role": "Speedster",
		"blurb": "Sucks up dust, enemies, and remotes alike.",
		"hp": 90, "speed": 155.0, "flying": false, "hover": 0.0,
		"attack": {"name": "Bump", "damage": 15, "range": 20.0, "arc": 120.0, "knock": 160.0, "cooldown": 0.3},
		"special": {"name": "Turbo Suck", "kind": Special.PULL, "cooldown": 5.0, "damage": 6,
			"radius": 90.0, "knock": 230.0, "stun": 0.4},
		"tidy": 1.0, "carry_speed": 0.8, "vacuum": true,
		"tidy_note": "Vacuums up debris just by driving over it.",
	},
	"butler": {
		"name": "Unit-7", "team": Team.ROBOTS, "species": "Helper Bot", "role": "Tank",
		"blurb": "Programmed to serve. Reprogrammed to punch.",
		"hp": 140, "speed": 115.0, "flying": false, "hover": 0.0,
		"attack": {"name": "Bonk", "damage": 22, "range": 24.0, "arc": 110.0, "knock": 200.0, "cooldown": 0.45},
		"special": {"name": "Rocket Fist", "kind": Special.PROJECTILE, "cooldown": 5.0, "damage": 22,
			"knock": 300.0, "stun": 0.3, "count": 1, "spread": 0.0, "speed": 300.0,
			"range": 220.0, "hit_radius": 9.0, "sprite": "rocket_fist", "pierce": false},
		"tidy": 1.5, "carry_speed": 0.8,
		"tidy_note": "Literally built for this.",
	},
	"claw": {
		"name": "The Claw", "team": Team.ROBOTS, "species": "Ceiling Gantry", "role": "Flyer",
		"blurb": "Rides the ceiling rails. Grabs from above.",
		"hp": 70, "speed": 140.0, "flying": true, "hover": 40.0,
		"attack": {"name": "Pinch", "damage": 14, "range": 20.0, "arc": 160.0, "knock": 110.0, "cooldown": 0.3},
		"special": {"name": "Claw Drop", "kind": Special.SLAM, "cooldown": 5.5, "damage": 24,
			"radius": 34.0, "knock": 180.0, "stun": 0.9, "windup": 0.45, "rise": -34.0},
		"tidy": 1.0, "carry_speed": 0.8, "strong": true,
		"tidy_note": "Lifts heavy things on its own.",
	},
	"bass": {
		"name": "Bass", "team": Team.ROBOTS, "species": "Smart Speaker", "role": "Support",
		"blurb": "Drops beats. Drops enemies. Heals the squad.",
		"hp": 100, "speed": 125.0, "flying": false, "hover": 0.0,
		"attack": {"name": "Sound Pulse", "damage": 14, "range": 30.0, "arc": 80.0, "knock": 150.0, "cooldown": 0.4},
		"special": {"name": "Hype Track", "kind": Special.AURA, "cooldown": 8.0, "radius": 75.0,
			"heal": 30, "speed_mult": 1.35, "duration": 3.0},
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
