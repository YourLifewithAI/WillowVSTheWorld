class_name Iso
extends RefCounted
## Isometric helpers.
##
## The world lives in "screen space": positions are the pixels you see, drawn
## with a 2:1 isometric projection (one floor tile is 32x16 px). Moving one
## pixel up the screen covers twice as much floor as moving one pixel sideways,
## so anything that measures distance on the floor (attack ranges, pickup
## radii, movement speed) converts to "floor space" first, where the y axis is
## stretched back out and every direction is equal.

const TILE_W := 32.0
const TILE_H := 16.0

## Tile coordinates -> screen offset. Tile axis i runs down-right, j runs down-left.
static func tile_to_local(t: Vector2) -> Vector2:
	return Vector2((t.x - t.y) * TILE_W * 0.5, (t.x + t.y) * TILE_H * 0.5)


static func local_to_tile(p: Vector2) -> Vector2:
	var a := p.x / (TILE_W * 0.5)
	var b := p.y / (TILE_H * 0.5)
	return Vector2((a + b) * 0.5, (b - a) * 0.5)


## Screen-space offset -> floor-space offset (equal distances in every direction).
static func to_floor(v: Vector2) -> Vector2:
	return Vector2(v.x, v.y * 2.0)


## Floor-space offset -> screen-space offset.
static func to_screen(v: Vector2) -> Vector2:
	return Vector2(v.x, v.y * 0.5)


## Distance between two screen positions, measured on the floor.
static func fdist(a: Vector2, b: Vector2) -> float:
	return to_floor(b - a).length()


## The four ground corners of a box footprint centred on the origin,
## ordered back, right, front, left. Size is in tiles (i, j).
static func footprint(size: Vector2) -> PackedVector2Array:
	var hw := size.x * 0.5
	var hd := size.y * 0.5
	return PackedVector2Array([
		tile_to_local(Vector2(-hw, -hd)),
		tile_to_local(Vector2(hw, -hd)),
		tile_to_local(Vector2(hw, hd)),
		tile_to_local(Vector2(-hw, hd)),
	])


## Points of a flat ellipse on the floor (for shadows, rings and zones).
static func ellipse(radius: float, segments: int = 24) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for s in segments:
		var a := TAU * s / segments
		pts.append(Vector2(cos(a) * radius, sin(a) * radius * 0.5))
	return pts
