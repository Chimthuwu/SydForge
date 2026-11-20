extends Node3D

## Walkable, dressed station interiors for key Sydney rail stations.
##
## Builds concourses, ticket halls, platform furniture and access shafts as
## presentation geometry plus simple collision. Ground openings are exposed so
## CbdWorld can cut the street surface above underground spaces.
##
## Coordinates are the installed Sydney metre projection. Interiors are authored
## presentation derived from station/entrance positions, not surveyed plans.

const ART := preload("res://scripts/art.gd")

const TILE_FLOOR := Color("8f8a7f")
const TILE_WALL := Color("d8d1c2")
const TILE_WALL_DARK := Color("b8b0a0")
const CONCRETE := Color("6f6c66")
const METAL := Color("596066")
const GLASS := Color("6f8b97")
const SIGN_BLUE := Color("1f4f7a")
const OPAL_YELLOW := Color("f2c230")
const WOOD := Color("6a4a32")
const LIGHT_WARM := Color("fff2d8")

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


static func openings() -> Array:
	## World-space rectangular ground openings (axis-aligned in XZ).
	## Each entry: {"x","z","w","h"} centre + half-extents in metres? no, use
	## centre x,z and full width/height for simplicity.
	var result: Array = []
	for spec in STATIONS:
		if str(spec.get("kind", "")) != "underground":
			continue
		var cx := float(spec["x"])
		var cz := float(spec["z"])
		var cw: float = float(spec.get("concourse", Vector2(24, 14)).x) + 4.0
		var ch: float = float(spec.get("concourse", Vector2(24, 14)).y) + 10.0
		result.append({"id": spec["id"], "x": cx, "z": cz, "w": cw, "h": ch})
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

	var kind := str(spec.get("kind", "surface"))
	if kind == "underground":
		_build_underground_station(station, spec)
	elif kind == "elevated":
		_build_surface_station(station, spec, float(spec.get("elevation", 12.0)))
	else:
		_build_surface_station(station, spec, 0.25)


func _build_underground_station(root: Node3D, spec: Dictionary) -> void:
	var depth := float(spec.get("depth", 10.0))
	var platform_y := -depth
	var conc_y := -depth * 0.55
	var conc_size: Vector2 = spec.get("concourse", Vector2(26.0, 14.0))
	var length := float(spec.get("length", 90.0))

	# Concourse hall (ticket hall) above platform level.
	var hall := _room(root, Vector3(0.0, conc_y, 0.0), Vector3(conc_size.x, 4.2, conc_size.y), TILE_FLOOR, TILE_WALL, CONCRETE)
	_add_lights(hall, Vector3(0.0, 3.6, 0.0), conc_size.x - 4.0, conc_size.y - 4.0, 3)
	_add_ticket_hall(hall, conc_size)
	_add_signage(hall, str(spec.get("name", "")), Vector3(0.0, 3.4, -conc_size.y * 0.5 + 0.4))

	# Stairs/escalator-like ramps from concourse up to street opening.
	var rise := 0.0 - conc_y
	var shaft_len := conc_size.y * 0.5 + 6.0
	_stairs(root, Vector3(0.0, conc_y + 0.1, conc_size.y * 0.5 + shaft_len * 0.5), 3.2, rise, shaft_len, 0.0)
	_stairs(root, Vector3(0.0, conc_y + 0.1, -conc_size.y * 0.5 - shaft_len * 0.5), 3.2, rise, shaft_len, PI)

	# Stairs down from concourse to platform level.
	var down_rise := conc_y - platform_y
	_stairs(root, Vector3(-conc_size.x * 0.22, platform_y + 0.1, 0.0), 3.0, down_rise, 8.0, PI * 0.5)
	_stairs(root, Vector3(conc_size.x * 0.22, platform_y + 0.1, 0.0), 3.0, down_rise, 8.0, -PI * 0.5)

	# Platform volume and dressing (visual, sits around/over rail shell).
	var platform := Node3D.new()
	platform.name = "PlatformInterior"
	platform.position = Vector3(0.0, platform_y, 0.0)
	root.add_child(platform)
	_platform_dressing(platform, length, float(spec.get("width", 14.0)), str(spec.get("name", "")), true)

	# Vertical access walls lining the opening shaft.
	var shaft_h: float = absf(platform_y) + 0.2
	for side in [-1.0, 1.0]:
		ART.box(root, Vector3(side * (conc_size.x * 0.5 + 0.25), -shaft_h * 0.5, conc_size.y * 0.5 + shaft_len * 0.5),
			Vector3(0.5, shaft_h, shaft_len + 2.0), TILE_WALL_DARK)
		ART.box(root, Vector3(side * (conc_size.x * 0.5 + 0.25), -shaft_h * 0.5, -conc_size.y * 0.5 - shaft_len * 0.5),
			Vector3(0.5, shaft_h, shaft_len + 2.0), TILE_WALL_DARK)


func _build_surface_station(root: Node3D, spec: Dictionary, base_y: float) -> void:
	var conc_size: Vector2 = spec.get("concourse", Vector2(26.0, 14.0))
	var length := float(spec.get("length", 96.0))

	var hall := _room(root, Vector3(0.0, base_y, 0.0), Vector3(conc_size.x, 4.6, conc_size.y), TILE_FLOOR, TILE_WALL, CONCRETE)
	_add_lights(hall, Vector3(0.0, 4.0, 0.0), conc_size.x - 4.0, conc_size.y - 3.0, 3)
	_add_ticket_hall(hall, conc_size)
	_add_signage(hall, str(spec.get("name", "")), Vector3(0.0, 3.8, -conc_size.y * 0.5 + 0.4))

	# Platform dressing at the same level (offset along local Z as a simple concourse-to-platform relation).
	var platform := Node3D.new()
	platform.name = "PlatformInterior"
	platform.position = Vector3(0.0, base_y, -conc_size.y * 0.5 - 5.0)
	root.add_child(platform)
	_platform_dressing(platform, length, float(spec.get("width", 14.0)), str(spec.get("name", "")), false)


func _room(parent: Node3D, center: Vector3, size: Vector3, floor_c: Color, wall_c: Color, ceil_c: Color) -> Node3D:
	var room := Node3D.new()
	room.position = center
	parent.add_child(room)
	# Floor (solid).
	ART.box(room, Vector3(0.0, 0.08, 0.0), Vector3(size.x, 0.16, size.z), floor_c, true)
	# Ceiling.
	ART.box(room, Vector3(0.0, size.y, 0.0), Vector3(size.x, 0.2, size.z), ceil_c)
	# Walls.
	ART.box(room, Vector3(-size.x * 0.5, size.y * 0.5, 0.0), Vector3(0.3, size.y, size.z), wall_c)
	ART.box(room, Vector3(size.x * 0.5, size.y * 0.5, 0.0), Vector3(0.3, size.y, size.z), wall_c)
	ART.box(room, Vector3(0.0, size.y * 0.5, -size.z * 0.5), Vector3(size.x, size.y, 0.3), wall_c)
	ART.box(room, Vector3(0.0, size.y * 0.5, size.z * 0.5), Vector3(size.x, size.y, 0.3), wall_c)
	# Tiled wall bands.
	ART.box(room, Vector3(0.0, 1.1, -size.z * 0.5 + 0.18), Vector3(size.x - 0.4, 1.6, 0.06), TILE_WALL_DARK)
	ART.box(room, Vector3(0.0, 1.1, size.z * 0.5 - 0.18), Vector3(size.x - 0.4, 1.6, 0.06), TILE_WALL_DARK)
	return room


func _add_ticket_hall(parent: Node3D, size: Vector2) -> void:
	# Ticket barriers / Opal gates row.
	var gate_y := 0.9
	var count := 5
	var spacing := 1.6
	var start_x := -float(count - 1) * spacing * 0.5
	for i in count:
		var gx: float = start_x + float(i) * spacing
		ART.box(parent, Vector3(gx, gate_y, 0.0), Vector3(0.38, 1.8, 1.3), METAL)
		ART.box(parent, Vector3(gx, 1.65, 0.0), Vector3(0.5, 0.18, 1.1), OPAL_YELLOW)
		# Reader paddle.
		ART.box(parent, Vector3(gx + 0.22, 1.05, 0.2), Vector3(0.08, 0.35, 0.18), SIGN_BLUE)

	# Ticket machines along a side wall.
	for i in 3:
		var mx := -size.x * 0.5 + 1.6 + float(i) * 1.8
		ART.box(parent, Vector3(mx, 1.0, -size.y * 0.5 + 0.6), Vector3(0.8, 2.0, 0.6), METAL)
		ART.box(parent, Vector3(mx, 1.55, -size.y * 0.5 + 0.92), Vector3(0.55, 0.55, 0.05), SIGN_BLUE)

	# Benches and bins.
	for side in [-1.0, 1.0]:
		ART.box(parent, Vector3(side * (size.x * 0.5 - 2.0), 0.45, 2.2), Vector3(2.4, 0.12, 0.7), WOOD, true)
		ART.box(parent, Vector3(side * (size.x * 0.5 - 2.0), 0.22, 2.2), Vector3(2.2, 0.44, 0.1), METAL)
		ART.box(parent, Vector3(side * (size.x * 0.5 - 3.8), 0.5, -2.0), Vector3(0.5, 1.0, 0.5), METAL)
		ART.box(parent, Vector3(side * (size.x * 0.5 - 3.8), 1.02, -2.0), Vector3(0.56, 0.08, 0.56), Color("2e5a3a"))

	# Departure/info board.
	ART.box(parent, Vector3(0.0, 2.7, -size.y * 0.5 + 0.5), Vector3(5.5, 1.6, 0.2), Color("1a1f24"))
	ART.box(parent, Vector3(0.0, 2.7, -size.y * 0.5 + 0.62), Vector3(5.1, 1.2, 0.04), SIGN_BLUE)


func _platform_dressing(parent: Node3D, length: float, width: float, station_name: String, underground: bool) -> void:
	# Platform edge strip, tactile band and seating along length.
	for side in [-1.0, 1.0]:
		ART.box(parent, Vector3(side * 3.2, 0.08, 0.0), Vector3(0.9, 0.1, length - 6.0), Color("d8c050"))
		ART.box(parent, Vector3(side * 3.8, 0.06, 0.0), Vector3(0.3, 0.08, length - 6.0), Color("bdb59a"))
	# Benches, bins, help points.
	var step_z := 18.0
	var z := -length * 0.5 + 12.0
	while z < length * 0.5 - 10.0:
		ART.box(parent, Vector3(0.0, 0.45, z), Vector3(2.6, 0.12, 0.75), WOOD, true)
		ART.box(parent, Vector3(0.0, 0.22, z), Vector3(2.4, 0.44, 0.1), METAL)
		ART.box(parent, Vector3(2.2, 0.5, z + 1.4), Vector3(0.45, 1.0, 0.45), METAL)
		ART.box(parent, Vector3(-2.2, 1.0, z - 1.4), Vector3(0.4, 2.0, 0.25), SIGN_BLUE)
		ART.box(parent, Vector3(-2.2, 1.85, z - 1.4), Vector3(0.3, 0.3, 0.05), OPAL_YELLOW)
		z += step_z

	# Overhead signs.
	ART.box(parent, Vector3(0.0, 3.4, -length * 0.5 + 5.0), Vector3(6.0, 0.9, 0.25), SIGN_BLUE)
	var label := ART.label(parent, Vector3(0.0, 3.45, -length * 0.5 + 5.15), station_name.to_upper(), 36)
	label.modulate = Color("ffffff")
	ART.box(parent, Vector3(0.0, 3.4, length * 0.5 - 5.0), Vector3(6.0, 0.9, 0.25), SIGN_BLUE)

	# Lighting strips.
	_add_lights(parent, Vector3(0.0, 3.8 if underground else 5.6, 0.0), 2.0, length - 12.0, 5)


func _add_signage(parent: Node3D, station_name: String, pos: Vector3) -> void:
	ART.box(parent, pos, Vector3(7.0, 1.0, 0.2), SIGN_BLUE)
	var label := ART.label(parent, pos + Vector3(0.0, 0.0, 0.12), station_name.to_upper(), 40)
	label.modulate = Color("ffffff")
	ART.box(parent, pos + Vector3(4.2, 0.0, 0.0), Vector3(1.2, 1.0, 0.2), OPAL_YELLOW)


func _add_lights(parent: Node3D, center: Vector3, span_x: float, span_z: float, count: int) -> void:
	if count <= 1:
		count = 2
	for i in count:
		var tz := -span_z * 0.5 + span_z * float(i) / float(count - 1)
		var fixture := ART.box(parent, center + Vector3(0.0, 0.0, tz), Vector3(maxf(span_x, 1.2), 0.12, 0.6), LIGHT_WARM)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = LIGHT_WARM
		mat.emission_enabled = true
		mat.emission = LIGHT_WARM
		mat.emission_energy_multiplier = 1.2
		fixture.material_override = mat


func _stairs(parent: Node3D, start: Vector3, width: float, rise: float, run: float, yaw: float) -> void:
	var steps := maxi(int(run / 0.32), 6)
	var step_h := rise / float(steps)
	var step_d := run / float(steps)
	var root := Node3D.new()
	root.position = start
	root.rotation.y = yaw
	parent.add_child(root)
	for i in steps:
		var y := float(i) * step_h + step_h * 0.5
		var z := -run * 0.5 + float(i) * step_d + step_d * 0.5
		ART.box(root, Vector3(0.0, y, z), Vector3(width, step_h, step_d + 0.02), CONCRETE, true)
	# Handrails.
	for side in [-1.0, 1.0]:
		ART.box(root, Vector3(side * (width * 0.5 - 0.08), rise * 0.5 + 0.5, 0.0), Vector3(0.08, rise + 1.0, run), METAL)
		ART.box(root, Vector3(side * (width * 0.5 - 0.08), rise + 0.95, 0.0), Vector3(0.1, 0.08, run), METAL)
