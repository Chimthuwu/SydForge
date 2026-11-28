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
	# Central is intentionally absent: its authored landmark in
	# cbd_landmarks.gd (shell, clock tower, canopies, platform slabs and
	# static carriages) owns the precinct presentation. The old surface
	# interior here built a sealed 34x18 m concourse room with no doorway
	# plus duplicated platform dressing ~100 m west of the landmark canopy
	# grid, which read as a locked concrete shed in the middle of the yard.
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


## Plan of the short open ramp at the southern end of the Harbour Bridge, where
## the track dives into the covered Wynyard bore (route indices 227..240). The
## ramp curves across XZ, so CbdWorld cuts the ground with this centreline
## instead of subtracting axis-aligned squares from the slab.
const DESCENT_CUT_POINTS := [
	Vector2(-152.24, -1562.58), Vector2(-155.16, -1556.74),
	Vector2(-157.58, -1551.77), Vector2(-160.01, -1546.80),
	Vector2(-162.43, -1541.83), Vector2(-164.63, -1536.82),
	Vector2(-166.83, -1531.81), Vector2(-169.03, -1526.80),
	Vector2(-171.04, -1521.74), Vector2(-173.04, -1516.67),
	Vector2(-175.05, -1511.61), Vector2(-177.51, -1505.42),
	Vector2(-179.31, -1500.31), Vector2(-181.12, -1495.21),
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
	var rail_yaw := 0.0
	if railway != null and railway.has_method("get_station_route_index"):
		var route_index := int(railway.call("get_station_route_index", str(spec["id"])))
		var route: Array = railway.get("main_route_points")
		if route_index >= 0 and route_index < route.size():
			rail_anchor = route[route_index]
		if railway.has_method("get_station_route_yaw"):
			rail_yaw = float(railway.call("get_station_route_yaw", str(spec["id"])))

	var kind := str(spec.get("kind", "surface"))
	if kind == "underground":
		_build_underground_station(station, spec, rail_anchor, rail_yaw)
	elif kind == "elevated":
		# Milsons Point is built grounded, with its stair, by milsons_point.gd.
		# The generic hall here hung in mid-air with no way up to it.
		pass
	else:
		_build_surface_station(station, spec, 0.25)


func _build_underground_station(root: Node3D, spec: Dictionary, rail_anchor: Vector3, rail_yaw: float = 0.0) -> void:
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
	platform.rotation.y = rail_yaw
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
