class_name SeatInput
extends Controls
## A person on this screen: reads their seat's keyboard or controller (see Seats).

var seat := 0


func _init(seat_index: int) -> void:
	seat = seat_index
	hold_to_aim = true


func think() -> Dictionary:
	return Seats.read(seat)
