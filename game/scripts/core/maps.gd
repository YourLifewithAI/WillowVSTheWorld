class_name Maps
extends RefCounted
## Every home you can fight in. Each map is a scene under res://scenes/maps/
## built from the same pieces (Room, Furniture, MessItem, BaseZone, FloorZone,
## and WallRun for homes with several rooms).
## Optional keys override the match defaults for that map.

const LIST := {
	"family_home": {
		"name": "The Family Home", "home": "Family home",
		"blurb": "Kitchen, dining room, den and a big living room in a ring. Bases behind doors; the big hitters can knock through walls.",
		"players": "4-8", "scene": "res://scenes/maps/family_home.tscn",
		"war_time": 180.0, "cleanup_time": 65.0,
	},
	"living_room": {
		"name": "The Living Room (classic)", "home": "Open-plan living room",
		"blurb": "The classic: one big open room, no walls. A good place to learn.",
		"players": "4-6", "scene": "res://scenes/maps/living_room.tscn",
		"cleanup_time": 50.0,
	},
	"studio": {
		"name": "Studio Apartment", "home": "City studio",
		"blurb": "Bed, desk and kitchenette in one tiny room. Short runs, constant chaos.",
		"players": "2-4", "scene": "res://scenes/maps/studio.tscn",
		"war_time": 150.0, "cleanup_time": 45.0,
	},
	"farmhouse": {
		"name": "The Farmhouse", "home": "Country farmhouse",
		"blurb": "Pantry, mudroom, workshop and a farm kitchen around an old stone chimney, with a porch all the way round.",
		"players": "4-6", "scene": "res://scenes/maps/farmhouse.tscn",
		"cleanup_time": 60.0,
	},
	"suburbs": {
		"name": "Suburban House", "home": "Big house in the suburbs",
		"blurb": "A long ranch house: kitchen, dining room, living room, garage and den. Long runs, so passing matters.",
		"players": "6-8", "scene": "res://scenes/maps/suburbs.tscn",
		"war_time": 210.0, "cleanup_time": 70.0,
	},
}

const ORDER: Array[String] = ["family_home", "suburbs", "farmhouse", "studio", "living_room"]
const DEFAULT := "family_home"


static func get_map(id: String) -> Dictionary:
	return LIST.get(id, LIST[DEFAULT])


static func exists(id: String) -> bool:
	return LIST.has(id)
