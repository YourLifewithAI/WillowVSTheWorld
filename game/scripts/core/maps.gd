class_name Maps
extends RefCounted
## Every home you can fight in. Each map is a scene under res://scenes/maps/
## built from the same pieces (Room, Furniture, MessItem, BaseZone, FloorZone).
## Optional keys override the match defaults for that map.

const LIST := {
	"living_room": {
		"name": "The Living Room", "home": "Family home",
		"blurb": "The classic. One big cozy room, a rug in the middle, bases in the corners.",
		"players": "4-6", "scene": "res://scenes/maps/living_room.tscn",
	},
	"studio": {
		"name": "Studio Apartment", "home": "City studio",
		"blurb": "Bed, desk and kitchenette in one tiny room. Short runs, constant chaos.",
		"players": "2-4", "scene": "res://scenes/maps/studio.tscn",
		"war_time": 150.0, "cleanup_time": 35.0,
	},
	"farmhouse": {
		"name": "The Farmhouse", "home": "Country farmhouse",
		"blurb": "Wood stove, farm table, muddy boots and a pie cooling somewhere it shouldn't be.",
		"players": "4-6", "scene": "res://scenes/maps/farmhouse.tscn",
		"cleanup_time": 50.0,
	},
	"suburbs": {
		"name": "Suburban House", "home": "Big house in the suburbs",
		"blurb": "Kitchen, living room and den split by half-walls. Long runs; the pets hold the kitchen.",
		"players": "6-8", "scene": "res://scenes/maps/suburbs.tscn",
		"war_time": 210.0, "cleanup_time": 55.0,
	},
}

const ORDER: Array[String] = ["living_room", "studio", "farmhouse", "suburbs"]
const DEFAULT := "living_room"


static func get_map(id: String) -> Dictionary:
	return LIST.get(id, LIST[DEFAULT])


static func exists(id: String) -> bool:
	return LIST.has(id)
