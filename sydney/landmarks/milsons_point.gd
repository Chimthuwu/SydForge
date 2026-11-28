extends Node3D

## Milsons Point: a grounded station under the elevated platform with a walkable
## stair, low-rise blocks along the mapped local streets, and the Luna Park
## funfair on its harbour-front site. All geometry is authored here; the park's
## entrance face is an original design, not a copy of the real artwork.

const ART := preload("res://scripts/art.gd")

const BRICK := Color("8a5a46")
const SANDSTONE := Color("c2ab84")
const CONCRETE := Color("8f8b82")
const STEEL := Color("4b565c")
const CREAM := Color("efe3c2")
const RED := Color("c4392f")
const YELLOW := Color("f2bd3a")
const BLUE := Color("2f6fa8")

## Real site, converted from its offset to the station.
const PARK_AREA := Rect2(150.0, -2925.0, 90.0, 125.0)
const STAIR_LATERAL := 7.8   # clear of the bridge's outer parapet below
const STAIR_WIDTH := 3.0

var stats: Dictionary = {}


## `platform` is the track point at the station, `forward` the track direction.
func build(bridge: Node3D, platform: Vector3, forward: Vector3) -> void:
	name = "MilsonsPoint"
	_build_station(platform, forward)
	var buildings := _build_blocks(bridge, platform)
	_build_luna_park()
	stats = {"buildings": buildings, "platformTop": platform.y + 0.39}


# ------------------------------------------------------------------ station --
func _build_station(platform: Vector3, forward: Vector3) -> void:
	var station := Node3D.new()
	station.name = "MilsonsStation"
	var flat := Vector3(forward.x, 0.0, forward.z).normalized()
	var side := Vector3.UP.cross(flat).normalized()
	station.transform = Transform3D(Basis(side, Vector3.UP, flat), Vector3(platform.x, 0.0, platform.z))
	add_child(station)
	# Local +X is `side`; the stair goes on whichever side faces west.
	var west := -1.0 if side.x > 0.0 else 1.0
	var top := platform.y + 0.39  # top of the rail network's platform deck

	# Brick viaduct carrying the platform down to the ground, with arched bays.
	for lateral in [-3.5, 3.5]:
		ART.box(station, Vector3(lateral, (top - 0.7) * 0.5, 0.0),
			Vector3(0.7, top - 0.7, 86.0), BRICK, true)
		for bay in range(-36, 37, 12):
			var face: float = lateral + signf(lateral) * 0.38
			ART.box(station, Vector3(face, 3.0, bay), Vector3(0.1, 5.4, 7.0), Color("3a2a24"))
			ART.box(station, Vector3(face, 5.9, bay), Vector3(0.12, 0.45, 8.0), SANDSTONE)
	ART.box(station, Vector3(0.0, top - 1.0, 0.0), Vector3(8.4, 0.5, 86.0), SANDSTONE)

	# Two flights and a half landing, from the street up to platform level.
	var x := west * STAIR_LATERAL
	var half := top * 0.5
	_flight(station, x, Vector3(0.0, 0.0, 26.0), Vector3(0.0, half, 13.0))
	ART.box(station, Vector3(x, half - 0.15, 11.0), Vector3(STAIR_WIDTH, 0.3, 4.4), CONCRETE, true)
	_flight(station, x, Vector3(0.0, half, 9.0), Vector3(0.0, top, -4.0))
	# Top landing: bridges from the stair across to the platform edge.
	var inner := west * 3.6
	var outer := x + west * STAIR_WIDTH * 0.5
	ART.box(station, Vector3((inner + outer) * 0.5, top - 0.15, -6.2),
		Vector3(absf(outer - inner), 0.3, 4.6), CONCRETE, true)
	ART.box(station, Vector3(outer, top + 0.6, -6.2), Vector3(0.14, 1.2, 4.6), STEEL, true)
	ART.box(station, Vector3((inner + outer) * 0.5, top + 0.6, -8.45),
		Vector3(absf(outer - inner), 1.2, 0.14), STEEL, true)
	for post_z in [11.0, -6.0]:
		var post_top := half if post_z > 0.0 else top
		ART.box(station, Vector3(outer, (post_top - 0.3) * 0.5, post_z),
			Vector3(0.35, post_top - 0.3, 0.35), STEEL, true)

	# Street entrance at the foot of the stair.
	for post in [-1.0, 1.0]:
		ART.box(station, Vector3(x + post * 1.9, 1.7, 27.2), Vector3(0.3, 3.4, 0.3), SANDSTONE, true)
	ART.box(station, Vector3(x, 3.75, 27.2), Vector3(4.4, 0.8, 0.35), Color("1c3e54"))
	var sign := ART.label(station, Vector3(x, 3.75, 27.45), "MILSONS POINT STATION", 38)
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED


## A smooth ramp for collision (no step snagging) with visible treads on top.
func _flight(parent: Node3D, x: float, from: Vector3, to: Vector3) -> void:
	var low := Vector3(x, from.y, from.z)
	var high := Vector3(x, to.y, to.z)
	var along := high - low
	var length := along.length()
	var z_axis := along / length
	var x_axis := Vector3.RIGHT
	var y_axis := z_axis.cross(x_axis).normalized()
	if y_axis.y < 0.0:
		x_axis = Vector3.LEFT
		y_axis = z_axis.cross(x_axis).normalized()
	var basis := Basis(x_axis, y_axis, z_axis)
	var body := StaticBody3D.new()
	body.name = "StairRamp"
	body.transform = Transform3D(basis, (low + high) * 0.5 - y_axis * 0.15)
	var shape := BoxShape3D.new()
	shape.size = Vector3(STAIR_WIDTH, 0.3, length + 0.2)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	parent.add_child(body)
	var treads := 26
	for index in treads:
		var point := low.lerp(high, (float(index) + 0.5) / float(treads))
		ART.box(parent, point + Vector3(0.0, -0.16, 0.0),
			Vector3(STAIR_WIDTH, 0.22, absf(along.z) / float(treads) + 0.04),
			CONCRETE.darkened(0.06 if index % 2 == 0 else 0.0))
	for edge in [-1.0, 1.0]:
		var rail := ART.box(parent, (low + high) * 0.5 + Vector3(edge * STAIR_WIDTH * 0.5, 0.55, 0.0),
			Vector3(0.1, 1.1, length), STEEL, true)
		rail.basis = basis


# ------------------------------------------------------------------- blocks --
func _build_blocks(bridge: Node3D, platform: Vector3) -> int:
	var reference: Dictionary = bridge.get("reference")
	var route: Array = bridge.get("route")
	var streets: Array = []
	for street: Dictionary in reference.get("localStreets", []):
		var line: Array[Vector2] = []
		for xy: Array in street.points:
			line.append(Vector2(xy[0], xy[1]))
		streets.append(line)
	var land: Array = []
	for ring: Array in reference.get("landRings", []):
		var polygon := PackedVector2Array()
		for xy: Array in ring:
			polygon.append(Vector2(xy[0], xy[1]))
		land.append(polygon)

	var placed: Array[Vector2] = []
	var tones := [BRICK, SANDSTONE, Color("a66f52"), Color("b9b2a3"), Color("75808a")]
	for line: Array[Vector2] in streets:
		for index in line.size() - 1:
			var a: Vector2 = line[index]
			var b: Vector2 = line[index + 1]
			var along := (b - a).normalized()
			var normal := Vector2(-along.y, along.x)
			var travel := 6.0
			while travel < a.distance_to(b):
				for side in [-1.0, 1.0]:
					for row in [17.0, 37.0]:
						var spot: Vector2 = a + along * travel + normal * float(side) * float(row)
						if _can_build(spot, streets, route, platform, land, placed):
							_block(spot, along, tones[placed.size() % tones.size()], placed.size())
							placed.append(spot)
				travel += 21.0
	return placed.size()


func _can_build(spot: Vector2, streets: Array, route: Array, platform: Vector3,
		land: Array, placed: Array[Vector2]) -> bool:
	if PARK_AREA.grow(14.0).has_point(spot) or spot.distance_to(Vector2(platform.x, platform.z)) < 52.0:
		return false
	for other: Vector2 in placed:
		if other.distance_to(spot) < 19.0:
			return false
	for point: Vector3 in route:
		if Vector2(point.x, point.z).distance_to(spot) < 38.0:
			return false
	for line: Array[Vector2] in streets:
		for index in line.size() - 1:
			if Geometry2D.get_closest_point_to_segment(spot, line[index], line[index + 1]).distance_to(spot) < 15.0:
				return false
	for polygon: PackedVector2Array in land:
		var dry := true
		for corner: Vector2 in [Vector2(-9, -9), Vector2(9, -9), Vector2(9, 9), Vector2(-9, 9)]:
			dry = dry and Geometry2D.is_point_in_polygon(spot + corner, polygon)
		if dry:
			return true
	return false


func _block(spot: Vector2, along: Vector2, tone: Color, seed_index: int) -> void:
	var floors := 3 + (seed_index * 7) % 6
	var height := float(floors) * 3.1
	var width := 12.0 + float(seed_index % 3) * 1.5
	var holder := Node3D.new()
	holder.position = Vector3(spot.x, 0.0, spot.y)
	holder.rotation.y = atan2(along.x, along.y)
	add_child(holder)
	ART.box(holder, Vector3(0.0, height * 0.5, 0.0), Vector3(11.0, height, width), tone, true)
	ART.box(holder, Vector3(0.0, height + 0.2, 0.0), Vector3(11.5, 0.4, width + 0.5), tone.darkened(0.3))
	for level in floors:
		for face in [-1.0, 1.0]:
			ART.box(holder, Vector3(face * 5.55, 1.9 + float(level) * 3.1, 0.0),
				Vector3(0.08, 1.5, width - 2.0), Color("2b414c"))


# --------------------------------------------------------------- Luna Park --
func _build_luna_park() -> void:
	var park := Node3D.new()
	park.name = "LunaPark"
	var centre := PARK_AREA.get_center()
	park.position = Vector3(centre.x, 0.0, centre.y)
	add_child(park)
	# Boardwalk apron.
	ART.box(park, Vector3(0.0, 0.02, 0.0), Vector3(PARK_AREA.size.x, 0.06, PARK_AREA.size.y), Color("9c7a55"))
	_entrance(park, PARK_AREA.size.y * 0.5 - 4.0)
	_ferris_wheel(park, Vector3(-18.0, 0.0, -28.0), 17.0)
	_carousel(park, Vector3(20.0, 0.0, -10.0))
	for index in 5:
		var stall := Vector3(30.0, 0.0, 34.0 - float(index) * 14.0 - 4.0)
		if index in [2, 3]:
			stall.x = -30.0
		var colour: Color = [RED, BLUE, YELLOW][index % 3]
		ART.box(park, stall + Vector3(0.0, 1.4, 0.0), Vector3(7.0, 2.8, 5.0), CREAM, true)
		ART.cylinder(park, stall + Vector3(0.0, 3.8, 0.0), 4.8, 2.0, colour, 0.2)


## Two ribbed towers either side of a great smiling face you walk in through.
func _entrance(park: Node3D, z: float) -> void:
	for sign_x in [-1.0, 1.0]:
		var x: float = sign_x * 13.0
		ART.box(park, Vector3(x, 9.0, z), Vector3(4.6, 18.0, 4.6), CREAM, true)
		for rib in [-1.5, 0.0, 1.5]:
			ART.box(park, Vector3(x + rib, 9.5, z + 2.4), Vector3(0.5, 19.0, 0.3), RED)
		for step in 3:
			ART.box(park, Vector3(x, 18.6 + float(step) * 1.2, z),
				Vector3(4.0 - float(step) * 1.1, 1.2, 4.0 - float(step) * 1.1),
				YELLOW if step % 2 == 0 else RED)
		ART.sphere(park, Vector3(x, 23.0, z), 0.8, YELLOW)
		# Cheeks flanking the open mouth that forms the gateway.
		ART.box(park, Vector3(sign_x * 7.4, 3.6, z), Vector3(6.6, 7.2, 1.6), YELLOW, true)
	var face := ART.cylinder(park, Vector3(0.0, 13.0, z), 9.5, 1.6, YELLOW)
	face.rotation.x = PI * 0.5
	for sign_x in [-1.0, 1.0]:
		ART.sphere(park, Vector3(sign_x * 3.4, 15.2, z + 0.9), 1.7, Color.WHITE)
		ART.sphere(park, Vector3(sign_x * 3.4, 15.0, z + 2.3), 0.7, Color("1d2a33"))
	ART.sphere(park, Vector3(0.0, 12.6, z + 1.2), 1.2, RED)
	for index in 9:
		var t := float(index) / 8.0
		var angle := lerpf(PI * 1.15, PI * 1.85, t)
		ART.box(park, Vector3(cos(angle) * 6.2, 13.4 + sin(angle) * 5.2, z + 0.95),
			Vector3(1.7, 1.2, 0.3), Color.WHITE)
	# Sun rays around the face.
	for index in 11:
		var angle := lerpf(-0.15, PI + 0.15, float(index) / 10.0)
		var ray := ART.box(park, Vector3(cos(angle) * 11.2, 13.0 + sin(angle) * 11.2, z - 0.2),
			Vector3(3.4, 1.0, 0.5), RED if index % 2 == 0 else CREAM)
		ray.rotation.z = angle
	var title := ART.label(park, Vector3(0.0, 27.0, z + 0.6), "LUNA PARK", 220)
	title.modulate = YELLOW
	title.billboard = BaseMaterial3D.BILLBOARD_ENABLED


func _ferris_wheel(park: Node3D, base: Vector3, radius: float) -> void:
	var hub := base + Vector3(0.0, radius + 3.0, 0.0)
	for leg_x in [-8.0, 8.0]:
		for leg_z in [-2.6, 2.6]:
			var foot := base + Vector3(leg_x, 0.0, leg_z)
			_beam(park, foot, hub + Vector3(0.0, 0.0, leg_z * 0.6), 0.55, CREAM)
	var spokes := 16
	for index in spokes:
		var angle := TAU * float(index) / float(spokes)
		var next := TAU * float(index + 1) / float(spokes)
		var rim := hub + Vector3(cos(angle), sin(angle), 0.0) * radius
		var rim_next := hub + Vector3(cos(next), sin(next), 0.0) * radius
		for depth in [-1.3, 1.3]:
			var offset := Vector3(0.0, 0.0, depth)
			_beam(park, rim + offset, rim_next + offset, 0.28, RED)
			_beam(park, hub + offset, rim + offset, 0.14, STEEL)
		ART.box(park, rim + Vector3(0.0, -1.1, 0.0), Vector3(1.9, 1.4, 1.9),
			[YELLOW, BLUE, RED, CREAM][index % 4])
		ART.sphere(park, rim + Vector3(0.0, 0.0, 1.5), 0.22, YELLOW)
	var axle := ART.cylinder(park, hub, 1.1, 4.2, YELLOW)
	axle.rotation.x = PI * 0.5


func _carousel(park: Node3D, base: Vector3) -> void:
	ART.cylinder(park, base + Vector3(0.0, 0.35, 0.0), 9.0, 0.5, RED)
	ART.cylinder(park, base + Vector3(0.0, 2.9, 0.0), 1.0, 4.8, YELLOW)
	for index in 12:
		var angle := TAU * float(index) / 12.0
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * 7.4
		ART.cylinder(park, base + offset + Vector3(0.0, 2.9, 0.0), 0.09, 4.8, CREAM)
		ART.box(park, base + offset + Vector3(0.0, 1.7 + 0.35 * (index % 2), 0.0),
			Vector3(0.6, 0.8, 1.6), [CREAM, BLUE, YELLOW][index % 3])
	ART.cylinder(park, base + Vector3(0.0, 6.4, 0.0), 9.8, 2.4, RED, 0.4)
	ART.sphere(park, base + Vector3(0.0, 8.0, 0.0), 0.7, YELLOW)


func _beam(parent: Node3D, from: Vector3, to: Vector3, thickness: float, color: Color) -> void:
	var delta := to - from
	var beam := ART.box(parent, (from + to) * 0.5, Vector3(thickness, delta.length(), thickness), color)
	beam.basis = Basis(Quaternion(Vector3.UP, delta.normalized()))
