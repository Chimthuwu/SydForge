extends RefCounted

## Single source of truth for Hyde Park, shared by the civic landmarks (paving,
## benches, memorial) and the greenery (where trees may and may not stand).
##
## The memorial, pool and southern walk are placed from the OSM pedestrian ways
## in the Stage B export. The northern avenue and the diagonal walks are
## authored: the export carries no footways through the northern lawns.

const PARK_IDS := ["way/148341695", "way/150583873"]  # Hyde Park North / South

const FOUNTAIN := Vector2(329.0, -178.0)
const FOUNTAIN_RADIUS := 27.0
const OBELISK := Vector2(270.0, -300.0)
const POOL := Vector2(283.5, 233.0)
const POOL_SIZE := Vector2(18.0, 56.0)
const MEMORIAL := Vector2(282.0, 296.0)

## The great central walk, lined both sides with Moreton Bay and Hills figs.
const AVENUE_WIDTH := 10.0
const AVENUES := [
	[Vector2(331.0, -325.0), Vector2(329.5, -205.0)],
	[Vector2(327.5, -151.0), Vector2(309.0, 22.0)],
	[Vector2(304.0, 82.0), Vector2(291.0, 196.0)],
]

## Narrower walks radiating from the fountain and crossing the southern lawns.
const WALK_WIDTH := 4.5
const WALKS := [
	[Vector2(310.0, -194.0), Vector2(226.0, -303.0)],
	[Vector2(348.0, -194.0), Vector2(404.0, -262.0)],
	[Vector2(303.0, -172.0), Vector2(218.0, -130.0)],
	[Vector2(355.0, -170.0), Vector2(418.0, -135.0)],
	[Vector2(312.0, 0.0), Vector2(216.0, -72.0)],
	[Vector2(314.0, 0.0), Vector2(394.0, -62.0)],
	[Vector2(296.0, 150.0), Vector2(190.0, 118.0)],
	[Vector2(298.0, 150.0), Vector2(388.0, 168.0)],
]


## Every paved route as [a, b, width].
static func paths() -> Array:
	var result: Array = []
	for line: Array in AVENUES:
		result.append([line[0], line[1], AVENUE_WIDTH])
	for line: Array in WALKS:
		result.append([line[0], line[1], WALK_WIDTH])
	return result


static func segment_distance(point: Vector2, a: Vector2, b: Vector2) -> float:
	return point.distance_to(Geometry2D.get_closest_point_to_segment(point, a, b))


## True when `point` is on, or within `margin` of, an authored walk.
static func near_path(point: Vector2, margin: float) -> bool:
	for path: Array in paths():
		if segment_distance(point, path[0], path[1]) < float(path[2]) * 0.5 + margin:
			return true
	return false


## True when `point` is within `margin` of any surface road or OSM walkway.
static func near_road(point: Vector2, roads: Array, margin: float) -> bool:
	for road: Dictionary in roads:
		if bool(road.get("tunnel", false)):
			continue
		var half := float(road.get("widthM", 8.0)) * 0.5 + margin
		var points: Array = road.get("points", [])
		for i in range(points.size() - 1):
			var a := Vector2(float(points[i][0]), float(points[i][1]))
			var b := Vector2(float(points[i + 1][0]), float(points[i + 1][1]))
			if segment_distance(point, a, b) < half:
				return true
	return false


## Fountain apron, obelisk, pool and memorial keep their own open ground.
static func on_monument(point: Vector2, margin: float) -> bool:
	if point.distance_to(FOUNTAIN) < FOUNTAIN_RADIUS + margin:
		return true
	if point.distance_to(OBELISK) < 9.0 + margin:
		return true
	var pool := Rect2(POOL - POOL_SIZE * 0.5, POOL_SIZE).grow(7.0 + margin)
	var memorial := Rect2(MEMORIAL - Vector2(17.0, 13.0), Vector2(34.0, 26.0)).grow(margin)
	return pool.has_point(point) or memorial.has_point(point)
