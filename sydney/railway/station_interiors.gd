extends Node3D

## Walkable, dressed station interiors for key Sydney rail stations.
##
## Builds concourses, ticket halls, platform furniture and access shafts as
## presentation geometry plus simple collision. Ground openings are exposed so
## CbdWorld can cut the street surface above underground spaces.
##
## Coordinates are the installed Sydney metre projection. Interiors are authored
## presentation derived from station/entrance positions, not surveyed plans.

const StationComponents := preload("res://sydney/railway/station_components.gd")

# Stations to flesh out. "route" stations sit on SydneyRailNetwork;
# "city" stations are placed from world transit coordinates.
const STATIONS := [
	{
		"id": "central",
		"name": "Central",
		"x": -174.7, "z": 1156.8,
		"kind": "surface",
		"length": 110.0, "width": 18.0,
		"concourse": Vector2(34.0, 18.0),
	},
	{
		"id": "town-hall",
		"name": "Town Hall",
		"x": -106.3, "z": 62.9,
		"kind": "underground",
		"depth": 10.0,
		"length": 92.0, "width": 16.0,
		"concourse": Vector2(30.0, 16.0),
	},
	{
		"id": "wynyard",
		"name": "Wynyard",
		"x": -202.5, "z": -778.2,
		"kind": "underground",
		"depth": 10.0,
		"length": 92.0, "width": 16.0,
		"concourse": Vector2(30.0, 16.0),
	},
	{
		"id": "circular-quay",
		"name": "Circular Quay",
		"x": 221.0, "z": -1283.0,
		"kind": "surface",
		"length": 96.0, "width": 16.0,
		"concourse": Vector2(28.0, 14.0),
	},
	{
		"id": "st-james",
		"name": "St James",
		"x": 348.8, "z": -263.9,
		"kind": "underground",
		"depth": 10.0,
		"length": 88.0, "width": 14.0,
		"concourse": Vector2(24.0, 14.0),
	},
	{
		"id": "museum",
		"name": "Museum",
		"x": 178.3, "z": 333.0,
		"kind": "underground",
		"depth": 10.0,
		"length": 88.0, "width": 14.0,
		"concourse": Vector2(24.0, 14.0),
	},
	{
		"id": "redfern",
		"name": "Redfern",
		"x": -858.1, "z": 2130.0,
		"kind": "surface",
		"length": 104.0, "width": 16.0,
		"concourse": Vector2(28.0, 14.0),
	},
	{
		"id": "milsons-point",
		"name": "Milsons Point",
		"x": 350.4, "z": -3014.8,
		"kind": "elevated",
		"elevation": 12.0,
		"length": 86.0, "width": 14.0,
		"concourse": Vector2(22.0, 12.0),
	},
]

var stats: Dictionary = {}


## Plan of the southern open rail cutting, sampled every second route index
## between the descent start and the first enclosed bore segment. The cut
## curves ~52 m across XZ, so axis-aligned rectangles either miss the ends or
## open a crater far wider than the trench (a 16 m square rotated 45° covers
## more than 22 m across the track). CbdWorld therefore cuts the ground with
## this centreline instead of subtracting squares from the slab.
const DESCENT_CUT_POINTS := [
	# From the portal where the route leaves street grade (index 248) so the
	# ground opening starts with the dive instead of burying 40 m of train.
	Vector2(-195.67, -1443.25), Vector2(-199.04, -1429.25),
	Vector2(-201.88, -1418.08), Vector2(-204.80, -1408.38),
	Vector2(-206.56, -1402.84), Vector2(-210.14, -1392.09),
	Vector2(-213.79, -1381.65), Vector2(-218.54, -1369.02),
	Vector2(-223.28, -1356.38), Vector2(-228.03, -1343.75),
	Vector2(-232.63, -1331.29), Vector2(-236.79, -1319.22),
	Vector2(-240.53, -1307.55), Vector2(-244.08, -1294.49),
	Vector2(-247.37, -1281.15), Vector2(-249.89, -1268.91),
	Vector2(-252.01, -1257.32), Vector2(-253.72, -1246.36),
	Vector2(-255.78, -1231.93), Vector2(-257.02, -1220.69),
	Vector2(-257.85, -1206.17), Vector2(-258.14, -1193.24),
	Vector2(-258.18, -1181.09), Vector2(-257.76, -1167.91),
	Vector2(-256.86, -1152.05), Vector2(-255.05, -1137.48),
	Vector2(-253.23, -1122.92), Vector2(-251.67, -1112.48),
	Vector2(-249.72, -1102.05), Vector2(-247.43, -1089.77),
	Vector2(-245.15, -1077.49), Vector2(-243.35, -1063.80),
	Vector2(-241.69, -1049.08), Vector2(-240.16, -1033.34),
	Vector2(-238.63, -1017.60), Vector2(-237.22, -1003.29),
	Vector2(-235.92, -990.41), Vector2(-234.69, -978.39),
	Vector2(-233.54, -967.22), Vector2(-232.06, -954.41),
	# The route's next point is the first enclosed bore segment (z = -948.01).
	Vector2(-231.32, -948.01),
]
## Ground opening half-width. The cutting's retaining walls stand 6.4 m either
## side of the centreline and are 0.7 m thick (outer face 6.75 m). The ground
## edge overlaps their top at 6.6 m, so there is no unsupported ledge to fall
## through beside the trench.
const DESCENT_CUT_HALF_WIDTH := 6.6


## Centreline of the open rail cutting in world XZ. CbdWorld uses this to cut
## a corridor-shaped opening (not one square per sample).
static func descent_cut_path() -> Array:
	return DESCENT_CUT_POINTS.duplicate()


static func openings() -> Array:
	## World-space rectangular ground openings (axis-aligned in XZ), each with a
	## centre and full width/height in metres.
	var result: Array = []
	for spec in STATIONS:
		if str(spec.get("kind", "")) != "underground":
			continue
		var cx := float(spec["x"])
		var cz := float(spec["z"])
		var cw: float = float(spec.get("concourse", Vector2(24, 14)).x) + 4.0
		var ch: float = float(spec.get("concourse", Vector2(24, 14)).y) + 10.0
		result.append({"id": spec["id"], "x": cx, "z": cz, "w": cw, "h": ch})
	# The southern bridge descent is cut separately, as a corridor that follows
	# the route: `descent_cut_path` / `DESCENT_CUT_HALF_WIDTH`. Adding it here as
	# axis-aligned rectangles produced the reported hole in the street.
	return result


func build(railway: Node3D, world_data: Dictionary) -> void:
	name = "StationInteriors"
	var built := 0
	for spec in STATIONS:
		_build_station(spec, railway, world_data)
		built += 1
	stats = {"stations": built, "openings": openings().size()}


func _build_station(spec: Dictionary, railway: Node3D, world_data: Dictionary) -> void:
	var station := Node3D.new()
	station.name = "Interior_" + str(spec["id"]).replace("-", "")
	station.position = Vector3(float(spec["x"]), 0.0, float(spec["z"]))
	add_child(station)

	# The railway platform is built at the nearest track waypoint, which for
	# Wynyard is ~15 m west of the OSM station node. Dress the platform at the
	# track, not at the concourse centre, or the two platform volumes overlap.
	var rail_anchor: Vector3 = Vector3(float(spec["x"]), 0.0, float(spec["z"]))
	if railway != null and railway.has_method("get_station_route_index"):
		var route_index := int(railway.call("get_station_route_index", str(spec["id"])))
		var route: Array = railway.get("main_route_points")
		if route_index >= 0 and route_index < route.size():
			rail_anchor = route[route_index]

	var kind := str(spec.get("kind", "surface"))
	if kind == "underground":
		_build_underground_station(station, spec, rail_anchor)
	elif kind == "elevated":
		_build_surface_station(station, spec, float(spec.get("elevation", 12.0)))
	else:
		_build_surface_station(station, spec, 0.25)


func _build_underground_station(root: Node3D, spec: Dictionary, rail_anchor: Vector3) -> void:
	var depth := float(spec.get("depth", 10.0))
	var platform_y := -depth
	var conc_y := -depth * 0.55
	var conc_size: Vector2 = spec.get("concourse", Vector2(26.0, 14.0))
	var length := float(spec.get("length", 90.0))

	# Concourse hall (ticket hall) above platform level.
	var hall := StationComponents.room(root, Vector3(0.0, conc_y, 0.0), Vector3(conc_size.x, 4.2, conc_size.y))
	StationComponents.lights(hall, Vector3(0.0, 3.6, 0.0), conc_size.x - 4.0, conc_size.y - 4.0, 3)
	StationComponents.ticket_hall(hall, conc_size)
	StationComponents.signage(hall, str(spec.get("name", "")), Vector3(0.0, 3.4, -conc_size.y * 0.5 + 0.4))

	# Stairs/escalator-like ramps from concourse up to street opening.
	var rise := 0.0 - conc_y
	var shaft_len := conc_size.y * 0.5 + 6.0
	StationComponents.stairs(root, Vector3(0.0, conc_y + 0.1, conc_size.y * 0.5 + shaft_len * 0.5), 3.2, rise, shaft_len, 0.0)
	StationComponents.stairs(root, Vector3(0.0, conc_y + 0.1, -conc_size.y * 0.5 - shaft_len * 0.5), 3.2, rise, shaft_len, PI)
	# Roof the street shaft either side of the stair opening. Without this the
	# platform view looks out through a long unlined slot into daylight.
	for z_sign in [-1.0, 1.0]:
		var shaft_z: float = z_sign * (conc_size.y * 0.5 + shaft_len * 0.5)
		for x_sign in [-1.0, 1.0]:
			StationComponents.ART.box(
				root,
				Vector3(float(x_sign) * (conc_size.x * 0.25 + 1.0), -0.35, shaft_z),
				Vector3(maxf(1.0, conc_size.x * 0.5 - 2.0), 0.3, shaft_len),
				StationComponents.DEFAULT_PALETTE["concrete"]
			)

	# Stairs down from concourse to platform level.
	var down_rise := conc_y - platform_y
	StationComponents.stairs(root, Vector3(-conc_size.x * 0.22, platform_y + 0.1, 0.0), 3.0, down_rise, 8.0, PI * 0.5)
	StationComponents.stairs(root, Vector3(conc_size.x * 0.22, platform_y + 0.1, 0.0), 3.0, down_rise, 8.0, -PI * 0.5)

	# Platform volume and dressing (visual, sits around/over rail shell).
	var platform := Node3D.new()
	platform.name = "PlatformInterior"
	platform.position = Vector3(
		rail_anchor.x - root.position.x,
		rail_anchor.y - root.position.y,
		rail_anchor.z - root.position.z
	)
	root.add_child(platform)
	StationComponents.platform_dressing(platform, length, float(spec.get("width", 14.0)), str(spec.get("name", "")), true)

	# Vertical access walls lining the opening shaft.
	var shaft_h: float = absf(platform_y) + 0.2
	for side in [-1.0, 1.0]:
		StationComponents.ART.box(root, Vector3(side * (conc_size.x * 0.5 + 0.25), -shaft_h * 0.5, conc_size.y * 0.5 + shaft_len * 0.5),
			Vector3(0.5, shaft_h, shaft_len + 2.0), StationComponents.DEFAULT_PALETTE["tile_wall_dark"])
		StationComponents.ART.box(root, Vector3(side * (conc_size.x * 0.5 + 0.25), -shaft_h * 0.5, -conc_size.y * 0.5 - shaft_len * 0.5),
			Vector3(0.5, shaft_h, shaft_len + 2.0), StationComponents.DEFAULT_PALETTE["tile_wall_dark"])


func _build_surface_station(root: Node3D, spec: Dictionary, base_y: float) -> void:
	var conc_size: Vector2 = spec.get("concourse", Vector2(26.0, 14.0))
	var length := float(spec.get("length", 96.0))

	var hall := StationComponents.room(root, Vector3(0.0, base_y, 0.0), Vector3(conc_size.x, 4.6, conc_size.y))
	StationComponents.lights(hall, Vector3(0.0, 4.0, 0.0), conc_size.x - 4.0, conc_size.y - 3.0, 3)
	StationComponents.ticket_hall(hall, conc_size)
	StationComponents.signage(hall, str(spec.get("name", "")), Vector3(0.0, 3.8, -conc_size.y * 0.5 + 0.4))

	# Platform dressing at the same level (offset along local Z as a simple concourse-to-platform relation).
	var platform := Node3D.new()
	platform.name = "PlatformInterior"
	platform.position = Vector3(0.0, base_y, -conc_size.y * 0.5 - 5.0)
	root.add_child(platform)
	StationComponents.platform_dressing(platform, length, float(spec.get("width", 14.0)), str(spec.get("name", "")), false)
