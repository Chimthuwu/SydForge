extends Node3D

## Named street definitions and signage for the two corridors the player asked
## to be explicit: George Street and Parramatta Road.
##
## George Street exists in the Stage B OSM road set, so its blades are placed on
## real sampled road points. Parramatta Road leaves the Stage B bounds and is
## owned by the inner-west world; this module still defines it and places a
## directional gateway at the western CBD edge rather than inventing a new road.

const ArtUtil := preload("res://scripts/art.gd")

const STREETS := [
	{
		"name": "George Street",
		"label": "GEORGE ST",
		"type": "major",
		"color": Color("226b52"),
		"defined": true,
	},
	{
		"name": "Parramatta Road",
		"label": "PARRAMATTA RD",
		"type": "arterial",
		"color": Color("7b5c2c"),
		"defined": true,
	},
]

var stats: Dictionary = {}
var _george_points: Array[Vector2] = []


func build(world_data: Dictionary) -> void:
	name = "StreetSignage"
	var george_roads: Array = []
	for road: Dictionary in world_data.get("roads", []):
		var road_name := str(road.get("name", ""))
		if road_name == "George Street":
			george_roads.append(road)
	# Sample the real George Street centreline at recognisable CBD intervals.
	for road: Dictionary in george_roads:
		var points: Array = road.get("points", [])
		for index in range(0, points.size(), maxi(1, points.size() / 7)):
			var point: Array = points[index]
			if point.size() < 2:
				continue
			var xz := Vector2(float(point[0]), float(point[1]))
			if xz.x < -400.0 or xz.x > 500.0 or xz.y < -1750.0 or xz.y > 1200.0:
				continue
			var duplicate := false
			for existing: Vector2 in _george_points:
				if existing.distance_to(xz) < 180.0:
					duplicate = true
					break
			if not duplicate:
				_george_points.append(xz)
	_george_points.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.y < b.y)
	for point: Vector2 in _george_points:
		_street_blade(Vector3(point.x + 5.5, 0.0, point.y), "GEORGE ST", Color("226b52"), -PI * 0.5)
	# Directional gateway at the western edge toward Parramatta Road.
	var gateway := Node3D.new()
	gateway.name = "ParramattaRoadGateway"
	gateway.position = Vector3(-1210.0, 0.0, 1170.0)
	add_child(gateway)
	for side in [-2.4, 2.4]:
		ArtUtil.cylinder(gateway, Vector3(side, 2.3, 0.0), 0.12, 4.6, Color("3c4a4a"))
	ArtUtil.box(gateway, Vector3(0.0, 4.25, 0.0), Vector3(6.4, 1.0, 0.22), Color("7b5c2c"))
	var label := ArtUtil.label(gateway, Vector3(0.0, 4.25, 0.18), "PARRAMATTA RD  →", 34)
	label.modulate = Color("fff0c9")
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	var sub := ArtUtil.label(gateway, Vector3(0.0, 3.45, 0.18), "WESTERN CORRIDOR", 22)
	sub.modulate = Color("f0e5cc")
	sub.billboard = BaseMaterial3D.BILLBOARD_DISABLED

	stats = {
		"streets": STREETS.size(),
		"georgeStreetBlades": _george_points.size(),
		"georgeStreetDefined": true,
		"parramattaRoadDefined": true,
		"parramattaGateway": true,
		"definitions": STREETS,
	}


func _street_blade(position: Vector3, text: String, color: Color, yaw: float) -> void:
	var pole := Node3D.new()
	pole.name = "StreetBlade"
	pole.position = position
	pole.rotation.y = yaw
	add_child(pole)
	ArtUtil.cylinder(pole, Vector3(0.0, 1.5, 0.0), 0.08, 3.0, Color("455253"))
	ArtUtil.box(pole, Vector3(0.0, 3.05, 0.0), Vector3(2.8, 0.52, 0.12), color)
	var label := ArtUtil.label(pole, Vector3(0.0, 3.05, 0.09), text, 30)
	label.modulate = Color("fff8e5")
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
