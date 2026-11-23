extends RefCounted

## Reusable station components shared by the authored station interiors and
## future Inner West stations.
##
## This is presentation geometry, not a station layout authority. Callers pass
## dimensions and a palette; the component library owns the repeated dressing
## (rooms, ticket halls, platform furniture, signage, lighting, stairs and
## canopies). Collision is limited to the floor/step volumes that the player
## must stand on, matching the existing interiors.
##
## Coordinates are the installed Sydney metre projection, Y up. Components are
## added under the parent node and positioned in that parent's local space.

const ART := preload("res://scripts/art.gd")

const DEFAULT_PALETTE := {
	"tile_floor": Color("8f8a7f"),
	"tile_wall": Color("d8d1c2"),
	"tile_wall_dark": Color("b8b0a0"),
	"concrete": Color("6f6c66"),
	"metal": Color("596066"),
	"glass": Color("6f8b97"),
	"sign_blue": Color("1f4f7a"),
	"opal_yellow": Color("f2c230"),
	"wood": Color("6a4a32"),
	"light_warm": Color("fff2d8"),
	"canopy": Color("596066"),
	"platform_edge": Color("d8c050"),
}


## Return a complete palette, applying caller overrides without mutating the
## shared defaults. Stations can therefore vary trim and materials while
## keeping the same component geometry.
static func make_palette(overrides: Dictionary = {}) -> Dictionary:
	var result := DEFAULT_PALETTE.duplicate()
	for key in overrides:
		result[key] = overrides[key]
	return result


## Four walls, a solid floor and a ceiling. Returns the room node so callers can
## add fixtures in room-local space.
static func room(
	parent: Node3D,
	center: Vector3,
	size: Vector3,
	palette: Dictionary = DEFAULT_PALETTE
) -> Node3D:
	var room_node := Node3D.new()
	room_node.position = center
	parent.add_child(room_node)
	# Floor (solid).
	ART.box(room_node, Vector3(0.0, 0.08, 0.0), Vector3(size.x, 0.16, size.z), palette["tile_floor"], true)
	# Ceiling.
	ART.box(room_node, Vector3(0.0, size.y, 0.0), Vector3(size.x, 0.2, size.z), palette["concrete"])
	# Walls.
	ART.box(room_node, Vector3(-size.x * 0.5, size.y * 0.5, 0.0), Vector3(0.3, size.y, size.z), palette["tile_wall"])
	ART.box(room_node, Vector3(size.x * 0.5, size.y * 0.5, 0.0), Vector3(0.3, size.y, size.z), palette["tile_wall"])
	ART.box(room_node, Vector3(0.0, size.y * 0.5, -size.z * 0.5), Vector3(size.x, size.y, 0.3), palette["tile_wall"])
	ART.box(room_node, Vector3(0.0, size.y * 0.5, size.z * 0.5), Vector3(size.x, size.y, 0.3), palette["tile_wall"])
	# Tiled wall bands.
	ART.box(room_node, Vector3(0.0, 1.1, -size.z * 0.5 + 0.18), Vector3(size.x - 0.4, 1.6, 0.06), palette["tile_wall_dark"])
	ART.box(room_node, Vector3(0.0, 1.1, size.z * 0.5 - 0.18), Vector3(size.x - 0.4, 1.6, 0.06), palette["tile_wall_dark"])
	return room_node


## Opal gates, ticket machines, benches, bins and a departure board.
static func ticket_hall(
	parent: Node3D,
	size: Vector2,
	palette: Dictionary = DEFAULT_PALETTE
) -> void:
	# Ticket barriers / Opal gates row.
	var gate_y := 0.9
	var count := 5
	var spacing := 1.6
	var start_x := -float(count - 1) * spacing * 0.5
	for i in count:
		var gx: float = start_x + float(i) * spacing
		ART.box(parent, Vector3(gx, gate_y, 0.0), Vector3(0.38, 1.8, 1.3), palette["metal"])
		ART.box(parent, Vector3(gx, 1.65, 0.0), Vector3(0.5, 0.18, 1.1), palette["opal_yellow"])
		# Reader paddle.
		ART.box(parent, Vector3(gx + 0.22, 1.05, 0.2), Vector3(0.08, 0.35, 0.18), palette["sign_blue"])

	# Ticket machines along a side wall.
	for i in 3:
		var mx := -size.x * 0.5 + 1.6 + float(i) * 1.8
		ART.box(parent, Vector3(mx, 1.0, -size.y * 0.5 + 0.6), Vector3(0.8, 2.0, 0.6), palette["metal"])
		ART.box(parent, Vector3(mx, 1.55, -size.y * 0.5 + 0.92), Vector3(0.55, 0.55, 0.05), palette["sign_blue"])

	# Benches and bins.
	for side in [-1.0, 1.0]:
		ART.box(parent, Vector3(side * (size.x * 0.5 - 2.0), 0.45, 2.2), Vector3(2.4, 0.12, 0.7), palette["wood"], true)
		ART.box(parent, Vector3(side * (size.x * 0.5 - 2.0), 0.22, 2.2), Vector3(2.2, 0.44, 0.1), palette["metal"])
		ART.box(parent, Vector3(side * (size.x * 0.5 - 3.8), 0.5, -2.0), Vector3(0.5, 1.0, 0.5), palette["metal"])
		ART.box(parent, Vector3(side * (size.x * 0.5 - 3.8), 1.02, -2.0), Vector3(0.56, 0.08, 0.56), Color("2e5a3a"))

	# Departure/info board.
	ART.box(parent, Vector3(0.0, 2.7, -size.y * 0.5 + 0.5), Vector3(5.5, 1.6, 0.2), Color("1a1f24"))
	ART.box(parent, Vector3(0.0, 2.7, -size.y * 0.5 + 0.62), Vector3(5.1, 1.2, 0.04), palette["sign_blue"])


## Platform edge strips, tactile band, seating, help points, overhead signage
## and lighting. The platform slab itself is owned by the station builder.
static func platform_dressing(
	parent: Node3D,
	length: float,
	width: float,
	station_name: String,
	underground: bool,
	palette: Dictionary = DEFAULT_PALETTE
) -> void:
	# Platform edge strip, tactile band and seating along length.
	for side in [-1.0, 1.0]:
		ART.box(parent, Vector3(side * 3.2, 0.08, 0.0), Vector3(0.9, 0.1, length - 6.0), palette["platform_edge"])
		ART.box(parent, Vector3(side * 3.8, 0.06, 0.0), Vector3(0.3, 0.08, length - 6.0), palette["tile_wall_dark"])
	# Benches, bins, help points.
	var step_z := 18.0
	var z := -length * 0.5 + 12.0
	while z < length * 0.5 - 10.0:
		ART.box(parent, Vector3(0.0, 0.45, z), Vector3(2.6, 0.12, 0.75), palette["wood"], true)
		ART.box(parent, Vector3(0.0, 0.22, z), Vector3(2.4, 0.44, 0.1), palette["metal"])
		ART.box(parent, Vector3(2.2, 0.5, z + 1.4), Vector3(0.45, 1.0, 0.45), palette["metal"])
		ART.box(parent, Vector3(-2.2, 1.0, z - 1.4), Vector3(0.4, 2.0, 0.25), palette["sign_blue"])
		ART.box(parent, Vector3(-2.2, 1.85, z - 1.4), Vector3(0.3, 0.3, 0.05), palette["opal_yellow"])
		z += step_z

	# Overhead signs.
	ART.box(parent, Vector3(0.0, 3.4, -length * 0.5 + 5.0), Vector3(6.0, 0.9, 0.25), palette["sign_blue"])
	var label := ART.label(parent, Vector3(0.0, 3.45, -length * 0.5 + 5.15), station_name.to_upper(), 36)
	label.modulate = Color("ffffff")
	ART.box(parent, Vector3(0.0, 3.4, length * 0.5 - 5.0), Vector3(6.0, 0.9, 0.25), palette["sign_blue"])

	# Lighting strips.
	lights(parent, Vector3(0.0, 3.8 if underground else 5.6, 0.0), 2.0, length - 12.0, 5, palette)


## A simple low-poly canopy for surface and suburban platforms. Posts are spaced
## along the platform; the roof is a single fascia-lined slab so it stays cheap
## to instance at every station.
static func canopy(
	parent: Node3D,
	center: Vector3,
	length: float,
	width: float,
	height: float,
	palette: Dictionary = DEFAULT_PALETTE
) -> Node3D:
	var canopy_root := Node3D.new()
	canopy_root.position = center
	parent.add_child(canopy_root)
	var post_spacing := 12.0
	var posts := maxi(int(length / post_spacing) + 1, 2)
	for i in posts:
		var z := -length * 0.5 + length * float(i) / float(posts - 1)
		for side in [-1.0, 1.0]:
			ART.box(
				canopy_root,
				Vector3(side * (width * 0.5 - 0.7), height * 0.5, z),
				Vector3(0.22, height, 0.22),
				palette["metal"]
			)
	ART.box(canopy_root, Vector3(0.0, height, 0.0), Vector3(width, 0.22, length), palette["canopy"])
	ART.box(canopy_root, Vector3(0.0, height - 0.2, -length * 0.5), Vector3(width, 0.35, 0.16), palette["sign_blue"])
	ART.box(canopy_root, Vector3(0.0, height - 0.2, length * 0.5), Vector3(width, 0.35, 0.16), palette["sign_blue"])
	return canopy_root


## Station name board with the yellow wayfinding tab.
static func signage(
	parent: Node3D,
	station_name: String,
	pos: Vector3,
	palette: Dictionary = DEFAULT_PALETTE
) -> void:
	ART.box(parent, pos, Vector3(7.0, 1.0, 0.2), palette["sign_blue"])
	var label := ART.label(parent, pos + Vector3(0.0, 0.0, 0.12), station_name.to_upper(), 40)
	label.modulate = Color("ffffff")
	ART.box(parent, pos + Vector3(4.2, 0.0, 0.0), Vector3(1.2, 1.0, 0.2), palette["opal_yellow"])


## Emissive ceiling strips. Count is clamped to at least two so a short room
## still reads as lit.
static func lights(
	parent: Node3D,
	center: Vector3,
	span_x: float,
	span_z: float,
	count: int,
	palette: Dictionary = DEFAULT_PALETTE
) -> void:
	if count <= 1:
		count = 2
	for i in count:
		var tz := -span_z * 0.5 + span_z * float(i) / float(count - 1)
		var fixture := ART.box(parent, center + Vector3(0.0, 0.0, tz), Vector3(maxf(span_x, 1.2), 0.12, 0.6), palette["light_warm"])
		var mat := StandardMaterial3D.new()
		mat.albedo_color = palette["light_warm"]
		mat.emission_enabled = true
		mat.emission = palette["light_warm"]
		mat.emission_energy_multiplier = 1.2
		fixture.material_override = mat


## Solid stair flight with slim inclined handrails. `yaw` rotates the flight;
## the caller positions its base at `start`.
static func stairs(
	parent: Node3D,
	start: Vector3,
	width: float,
	rise: float,
	run: float,
	yaw: float,
	palette: Dictionary = DEFAULT_PALETTE
) -> void:
	var steps := maxi(int(run / 0.32), 6)
	var step_h := rise / float(steps)
	var step_d := run / float(steps)
	var stair_root := Node3D.new()
	stair_root.position = start
	stair_root.rotation.y = yaw
	parent.add_child(stair_root)
	for i in steps:
		var y := float(i) * step_h + step_h * 0.5
		var z := -run * 0.5 + float(i) * step_d + step_d * 0.5
		ART.box(stair_root, Vector3(0.0, y, z), Vector3(width, step_h, step_d + 0.02), palette["concrete"], true)
	# Slim inclined handrails. The old solid slab was `rise + 1` metres tall,
	# which read as an enormous blue wedge from the platform instead of a rail.
	for side in [-1.0, 1.0]:
		var rail := ART.box(
			stair_root,
			Vector3(side * (width * 0.5 - 0.08), rise * 0.5 + 0.95, 0.0),
			Vector3(0.09, 0.1, run + 0.2), palette["metal"]
		)
		rail.rotation.x = -atan2(rise, maxf(run, 0.1))
		for post in 4:
			var t := float(post) / 3.0
			ART.box(
				stair_root,
				Vector3(side * (width * 0.5 - 0.08), t * rise + 0.5, -run * 0.5 + t * run),
				Vector3(0.08, 1.0, 0.08), palette["metal"]
			)
