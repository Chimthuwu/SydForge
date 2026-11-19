extends Node3D

## Static double-track route and station shells for the Sydney intercity rail
## corridor. The sourced alignment runs Milsons Point–Wynyard–Town Hall–Central–
## Redfern; the existing HarbourBridge module supplies the elevated bridge rails.
## Tunnel depths, station interiors and parallel-track spacing are authored
## presentation, not surveyed elevations.

const DATA_PATH := "res://sydney/railway/milsons_redfern.json"
const ART := preload("res://scripts/art.gd")
const TRACK_GAUGE := 1.435
const TRACK_CENTRE_SPACING := 3.8
const SLEEPER_SPACING := 3.0
const RAIL_OFFSET := 0.7175
const MAX_ROUTE_GAP := 180.0

var source: Dictionary = {}
var stats: Dictionary = {}
var main_route_points: Array[Vector3] = []
var station_nodes: Dictionary = {}
var station_route_indices: Dictionary = {}
var _ways_by_id: Dictionary = {}
var _bridge_range := Vector2i(-1, -1)
var _stations: Array[Dictionary] = []
var _bridge: Node3D


func build(world_data: Dictionary, harbour_bridge: Node3D) -> bool:
	_bridge = harbour_bridge
	var error := _load_source()
	if not error.is_empty():
		push_error("CbdRailNetwork: " + error)
		return false
	_index_ways()
	if not _assemble_route():
		return false
	_trim_to_station_endpoints()
	_apply_station_elevations()
	_index_station_route_positions()
	_build_track_meshes()
	_build_stations(world_data)
	stats = {
		"stations": station_nodes.size(),
		"routePoints": main_route_points.size(),
		"sourceWays": _ways_by_id.size(),
		"tunnelWays": _count_way_tag("tunnel", "yes"),
		"bridgeIntegration": _bridge_range.y > _bridge_range.x,
		"mainRouteLengthM": _route_length(main_route_points),
		"trackGaugeM": TRACK_GAUGE,
		"parallelTrackSpacingM": TRACK_CENTRE_SPACING,
		"attribution": source.get("attribution", ""),
	}
	return true


func _load_source() -> String:
	if not FileAccess.file_exists(DATA_PATH):
		return "rail data missing: " + DATA_PATH
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return "rail data is not a JSON object"
	source = parsed
	if str(source.get("format", "")) != "splooge-sydney-railway" \
	or int(source.get("formatVersion", 0)) != 1:
		return "unsupported rail data format"
	return ""


func _index_ways() -> void:
	_ways_by_id.clear()
	for way: Dictionary in source.get("ways", []):
		var points: Array[Vector2] = []
		for raw_point: Array in way.get("pointsXZ", []):
			if raw_point.size() < 2:
				continue
			var point := Vector2(float(raw_point[0]), float(raw_point[1]))
			if points.is_empty() or points[-1].distance_to(point) > 0.01:
				points.append(point)
		if points.size() >= 2:
			_ways_by_id[str(way.get("osmId", ""))] = {
				"points": points,
				"tunnel": str(way.get("tunnel", "")) == "yes",
				"bridge": str(way.get("bridge", "")) == "yes",
				"layer": str(way.get("layer", "")),
			}
	_stations.clear()
	for station: Dictionary in source.get("stations", []):
		_stations.append(station)


func _assemble_route() -> bool:
	main_route_points.clear()
	_bridge_range = Vector2i(-1, -1)
	var parts: Array = source.get("routeParts", [])
	if parts.is_empty():
		push_error("CbdRailNetwork: routeParts is empty")
		return false

	for part_index in parts.size():
		var part: Dictionary = parts[part_index]
		if part.has("bridge"):
			if _bridge == null or main_route_points.is_empty():
				push_error("CbdRailNetwork: Harbour Bridge is required to join the rail route")
				return false
			var next_point: Variant = _next_part_start(parts, part_index + 1)
			if next_point == null:
				push_error("CbdRailNetwork: bridge has no following rail section")
				return false
			var offset := float(part.get("trackOffsetM", -19.0))
			_append_bridge_route(main_route_points[-1], next_point, offset)
			continue

		var way_id := str(part.get("wayId", ""))
		if not _ways_by_id.has(way_id):
			push_error("CbdRailNetwork: missing route way " + way_id)
			return false
		var way: Dictionary = _ways_by_id[way_id]
		var way_points: Array[Vector2] = way["points"]
		var ordered := way_points.duplicate()
		if bool(part.get("reverse", false)):
			ordered.reverse()
		for point: Vector2 in ordered:
			_append_connected_point(Vector3(point.x, 0.1, point.y))

	if main_route_points.size() < 20:
		push_error("CbdRailNetwork: route is unexpectedly short")
		return false
	return true


func _next_part_start(parts: Array, part_index: int) -> Variant:
	for index in range(part_index, parts.size()):
		var part: Dictionary = parts[index]
		if not part.has("wayId"):
			continue
		var way_id := str(part["wayId"])
		if not _ways_by_id.has(way_id):
			return null
		var points: Array[Vector2] = _ways_by_id[way_id]["points"]
		if points.is_empty():
			return null
		var point: Vector2 = points[-1] if bool(part.get("reverse", false)) else points[0]
		return Vector3(point.x, 0.1, point.y)
	return null


func _append_bridge_route(start_point: Vector3, end_point: Vector3, offset: float) -> void:
	var route: Array = _bridge.get("route")
	var route_east: Array = _bridge.get("route_east")
	if route.size() < 2 or route_east.size() != route.size():
		push_error("CbdRailNetwork: Harbour Bridge route data is invalid")
		return
	var start_index := _nearest_bridge_index(start_point, route, route_east, offset)
	var end_index := _nearest_bridge_index(end_point, route, route_east, offset)
	if start_index < end_index:
		push_error("CbdRailNetwork: bridge join order does not match Milsons-to-Redfern route")
		return
	_bridge_range.x = main_route_points.size()
	for index in range(start_index, end_index - 1, -1):
		var point: Vector3 = route[index] + route_east[index] * offset + Vector3.UP * 0.1
		_append_connected_point(point)
	_bridge_range.y = main_route_points.size() - 1


func _nearest_bridge_index(
	target: Vector3,
	route: Array,
	route_east: Array,
	offset: float
) -> int:
	var best_index := 0
	var best_distance := INF
	for index in route.size():
		var point: Vector3 = route[index] + route_east[index] * offset
		var distance_sq := Vector2(point.x - target.x, point.z - target.z).length_squared()
		if distance_sq < best_distance:
			best_distance = distance_sq
			best_index = index
	return best_index


func _append_connected_point(point: Vector3) -> void:
	if main_route_points.is_empty():
		main_route_points.append(point)
		return
	var previous := main_route_points[-1]
	var distance := previous.distance_to(point)
	if distance < 0.1:
		return
	var steps := ceili(distance / 8.0)
	if distance > 180.0:
		push_warning("CbdRailNetwork: interpolating a %.1f m OSM route gap" % distance)
	for step in range(1, steps):
		main_route_points.append(previous.lerp(point, float(step) / float(steps)))
	main_route_points.append(point)


func _trim_to_station_endpoints() -> void:
	var start_position: Vector3 = _station_position("milsons-point")
	var end_position: Vector3 = _station_position("redfern")
	if not start_position.is_finite() or not end_position.is_finite():
		push_error("CbdRailNetwork: route endpoint station anchors are missing")
		return
	var start_index := _nearest_route_index(start_position)
	var end_index := _nearest_route_index(end_position)
	if start_index >= end_index:
		push_error("CbdRailNetwork: Milsons Point and Redfern are out of route order")
		return
	var trimmed: Array[Vector3] = []
	for index in range(start_index, end_index + 1):
		trimmed.append(main_route_points[index])
	main_route_points = trimmed
	if _bridge_range.x >= 0:
		_bridge_range.x -= start_index
		_bridge_range.y -= start_index
	if main_route_points[0].distance_to(start_position) > 1.0:
		main_route_points.push_front(start_position + Vector3.UP * 0.1)
		if _bridge_range.x >= 0:
			_bridge_range.x += 1
			_bridge_range.y += 1
	if main_route_points[-1].distance_to(end_position) > 1.0:
		_append_connected_point(end_position + Vector3.UP * 0.1)


func _station_position(station_id: String) -> Vector3:
	for station: Dictionary in _stations:
		if str(station.get("id", "")) == station_id:
			return Vector3(float(station["x"]), 0.0, float(station["z"]))
	return Vector3(INF, 0.0, INF)


func _nearest_route_index(target: Vector3) -> int:
	var best_index := 0
	var best_distance := INF
	for index in main_route_points.size():
		var point := main_route_points[index]
		var distance_sq := Vector2(point.x - target.x, point.z - target.z).length_squared()
		if distance_sq < best_distance:
			best_distance = distance_sq
			best_index = index
	return best_index


func _apply_station_elevations() -> void:
	var wynyard_index := _nearest_route_index(_station_position("wynyard"))
	var town_hall_index := _nearest_route_index(_station_position("town-hall"))
	var central_index := _nearest_route_index(_station_position("central"))
	var redfern_index := main_route_points.size() - 1
	if wynyard_index < _bridge_range.y or town_hall_index <= wynyard_index \
	or central_index <= town_hall_index or redfern_index <= central_index:
		push_error("CbdRailNetwork: station order along route is invalid")
		return

	_set_route_elevation(0, _bridge_range.x, 0.1, main_route_points[_bridge_range.x].y)
	# The bridge keeps its authored height profile.
	for index in range(_bridge_range.y + 1, wynyard_index + 1):
		var t := _distance_fraction(_bridge_range.y, wynyard_index, index)
		main_route_points[index].y = lerpf(0.1, -10.0, t)
	_set_route_elevation(wynyard_index, town_hall_index, -10.0, -10.0)
	_set_route_elevation(town_hall_index, central_index, -10.0, 0.1)
	_set_route_elevation(central_index, redfern_index, 0.1, 0.1)


func _distance_fraction(start_index: int, end_index: int, current_index: int) -> float:
	var total := 0.0
	var travelled := 0.0
	for index in range(start_index, end_index):
		var length := main_route_points[index].distance_to(main_route_points[index + 1])
		total += length
		if index < current_index:
			travelled += length
	return 0.0 if total <= 0.001 else travelled / total


func _set_route_elevation(start_index: int, end_index: int, start_y: float, end_y: float) -> void:
	if start_index < 0 or end_index >= main_route_points.size() or end_index < start_index:
		return
	var total := 0.0
	for index in range(start_index, end_index):
		total += main_route_points[index].distance_to(main_route_points[index + 1])
	var travelled := 0.0
	for index in range(start_index, end_index + 1):
		var t := 0.0 if total <= 0.001 else travelled / total
		main_route_points[index].y = lerpf(start_y, end_y, t)
		if index < end_index:
			travelled += main_route_points[index].distance_to(main_route_points[index + 1])


func _index_station_route_positions() -> void:
	station_route_indices.clear()
	for station: Dictionary in _stations:
		var station_id := str(station.get("id", ""))
		var position := Vector3(float(station["x"]), 0.0, float(station["z"]))
		station_route_indices[station_id] = _nearest_route_index(position)


func _build_track_meshes() -> void:
	var ballast_surface := SurfaceTool.new()
	var sleeper_surface := SurfaceTool.new()
	var rail_surface := SurfaceTool.new()
	ballast_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	sleeper_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	rail_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sleeper_phase := 0.0

	for segment_index in range(main_route_points.size() - 1):
		if _is_bridge_segment(segment_index):
			continue
		var a := main_route_points[segment_index]
		var b := main_route_points[segment_index + 1]
		var direction := b - a
		direction.y = 0.0
		var length := direction.length()
		if length < 0.05:
			continue
		direction /= length
		var midpoint := (a + b) * 0.5
		var centerline_y := (a.y + b.y) * 0.5
		var vertical_basis := _track_basis(direction)
		_emit_box(
			ballast_surface,
			midpoint + Vector3.UP * (centerline_y - 0.13),
			vertical_basis,
			Vector3(8.2, 0.18, length),
			Vector3.UP
		)
		for track_side in [-1.0, 1.0]:
			var track_center: Vector3 = vertical_basis.x * track_side * TRACK_CENTRE_SPACING * 0.5
			for rail_side in [-1.0, 1.0]:
				var rail_position: Vector3 = midpoint + track_center \
					+ vertical_basis.x * rail_side * RAIL_OFFSET \
					+ Vector3.UP * (centerline_y + 0.075)
				_emit_box(
					rail_surface, rail_position, vertical_basis,
					Vector3(0.12, 0.16, length), vertical_basis.x
				)
			var next_sleeper := SLEEPER_SPACING - sleeper_phase
			while next_sleeper < length:
				var sleeper_center: Vector3 = a.lerp(b, next_sleeper / length) + track_center \
					+ Vector3.UP * (centerline_y - 0.015)
				_emit_box(
					sleeper_surface, sleeper_center, vertical_basis,
					Vector3(2.8, 0.14, 0.28), Vector3.UP
				)
				next_sleeper += SLEEPER_SPACING
		sleeper_phase = fposmod(sleeper_phase + length, SLEEPER_SPACING)

	_commit_mesh("RailBallast", ballast_surface, Color("3d3b38"), 0.95)
	_commit_mesh("RailSleepers", sleeper_surface, Color("51463b"), 0.9)
	_commit_mesh("RailSteel", rail_surface, Color("90999c"), 0.45)


func _is_bridge_segment(segment_index: int) -> bool:
	return _bridge_range.x >= 0 \
		and segment_index >= _bridge_range.x \
		and segment_index < _bridge_range.y


func _track_basis(direction: Vector3) -> Basis:
	var forward := Vector3(direction.x, 0.0, direction.z).normalized()
	var side := Vector3.UP.cross(forward).normalized()
	return Basis(side, Vector3.UP, forward)


func _emit_box(
	surface: SurfaceTool,
	center: Vector3,
	basis: Basis,
	size: Vector3,
	normal: Vector3
) -> void:
	var x := basis.x * size.x * 0.5
	var y := basis.y * size.y * 0.5
	var z := basis.z * size.z * 0.5
	var p000 := center - x - y - z
	var p100 := center + x - y - z
	var p110 := center + x + y - z
	var p010 := center - x + y - z
	var p001 := center - x - y + z
	var p101 := center + x - y + z
	var p111 := center + x + y + z
	var p011 := center - x + y + z
	_emit_face(surface, [p000, p100, p110, p010], -basis.z)
	_emit_face(surface, [p101, p001, p011, p111], basis.z)
	_emit_face(surface, [p001, p000, p010, p011], -basis.x)
	_emit_face(surface, [p100, p101, p111, p110], basis.x)
	_emit_face(surface, [p010, p110, p111, p011], basis.y)
	_emit_face(surface, [p001, p101, p100, p000], -basis.y)


func _emit_face(surface: SurfaceTool, points: Array, normal: Vector3) -> void:
	var a: Vector3 = points[0]
	var b: Vector3 = points[1]
	var c: Vector3 = points[2]
	if (b - a).cross(c - a).dot(normal) < 0.0:
		points.reverse()
	for index in [0, 1, 2, 0, 2, 3]:
		surface.set_normal(normal)
		surface.add_vertex(points[index])


func _commit_mesh(
	node_name: String,
	surface: SurfaceTool,
	color: Color,
	roughness: float
) -> void:
	var mesh := surface.commit()
	if mesh == null or mesh.get_surface_count() == 0:
		return
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, material)
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	add_child(instance)


func _build_stations(world_data: Dictionary) -> void:
	station_nodes.clear()
	for station: Dictionary in _stations:
		var station_id := str(station.get("id", ""))
		var node := Node3D.new()
		node.name = "Station_" + station_id.replace("-", "")
		node.position = Vector3(float(station["x"]), 0.0, float(station["z"]))
		add_child(node)
		station_nodes[station_id] = node
		_build_station_shell(node, station, world_data)
	_build_southern_bridge_portal()


func _build_southern_bridge_portal() -> void:
	if _bridge_range.y < 0 or _bridge_range.y + 1 >= main_route_points.size():
		return
	var position := main_route_points[_bridge_range.y]
	var forward := _route_direction(_bridge_range.y)
	var portal := Node3D.new()
	portal.name = "WynyardRailTunnelPortal"
	portal.position = position
	portal.rotation.y = atan2(-forward.x, -forward.z)
	add_child(portal)
	# Twin heavy-rail mouths emerge from the Rocks approach. This is authored
	# entrance dressing; the tunnel alignment itself remains below the surface.
	ART.box(portal, Vector3(0.0, 3.0, 0.55), Vector3(8.2, 6.2, 1.1), Color("77736a"))
	for side in [-1.0, 1.0]:
		ART.box(
			portal, Vector3(side * 1.9, 2.0, -0.08),
			Vector3(2.2, 4.0, 0.08), Color("101820")
		)
		ART.box(
			portal, Vector3(side * 3.25, 2.1, 0.0),
			Vector3(0.45, 4.3, 1.25), Color("a59a82")
		)
	ART.box(portal, Vector3(0.0, 5.3, 0.0), Vector3(7.2, 0.48, 1.35), Color("b8ac91"))
	ART.label(portal, Vector3(0.0, 6.0, 0.0), "CITY RAIL TUNNEL", 24)


func _build_station_shell(
	parent: Node3D,
	station: Dictionary,
	world_data: Dictionary
) -> void:
	var station_id := str(station.get("id", ""))
	var underground := str(station.get("level", "")) == "underground"
	var platform_y := -10.0 if underground else 0.25
	var route_index := int(station_route_indices.get(station_id, 0))
	var forward := _route_direction(route_index)
	var yaw := atan2(-forward.x, -forward.z)
	var platform_length := 104.0 if station_id in ["central", "redfern"] else 86.0

	var interior := Node3D.new()
	interior.name = "PlatformLevel"
	var platform_anchor: Vector3 = main_route_points[route_index]
	interior.position = Vector3(
		platform_anchor.x - parent.position.x,
		platform_y,
		platform_anchor.z - parent.position.z
	)
	interior.rotation.y = yaw
	parent.add_child(interior)
	ART.box(
		interior, Vector3(0.0, 0.12, 0.0),
		Vector3(8.0, 0.24, platform_length), Color("72716b")
	)
	for side in [-1.0, 1.0]:
		ART.box(
			interior, Vector3(side * 3.0, 0.08, 0.0),
			Vector3(1.0, 0.12, platform_length - 4.0), Color("b3aa98")
		)
		ART.box(
			interior, Vector3(side * 3.0, 0.2, -platform_length * 0.5 + 1.8),
			Vector3(1.0, 0.12, 2.8), Color("e2c64d")
		)
	if underground:
		ART.box(
			interior, Vector3(0.0, 4.0, 0.0),
			Vector3(14.0, 0.55, platform_length + 8.0), Color("555c60")
		)
		for column_z in range(-40, 41, 20):
			for side in [-1.0, 1.0]:
				ART.box(
					interior, Vector3(side * 5.0, 2.0, float(column_z)),
					Vector3(0.45, 4.0, 0.45), Color("9a978c")
				)
		ART.label(interior, Vector3(0.0, 2.1, -platform_length * 0.5 + 4.0),
			str(station.get("name", "")).to_upper(), 36)
	else:
		for column_z in range(-40, 41, 20):
			for side in [-1.0, 1.0]:
				ART.box(
					interior, Vector3(side * 4.8, 3.0, float(column_z)),
					Vector3(0.45, 6.0, 0.45), Color("555d62")
				)
		ART.box(
			interior, Vector3(0.0, 6.2, 0.0),
			Vector3(12.0, 0.45, platform_length), Color("4a555d")
		)
		ART.label(interior, Vector3(0.0, 7.2, -platform_length * 0.5 + 4.0),
			str(station.get("name", "")).to_upper(), 36)

	_build_station_entrances(parent, station, world_data)


func _build_station_entrances(
	parent: Node3D,
	station: Dictionary,
	world_data: Dictionary
) -> void:
	var station_id := str(station.get("id", ""))
	var entrance_positions: Array[Vector2] = []
	if station_id in ["wynyard", "town-hall"]:
		var station_name := str(station.get("name", ""))
		for stop: Dictionary in world_data.get("transit", []):
			if str(stop.get("kind", "")) != "subway_entrance" \
			or str(stop.get("name", "")) != station_name:
				continue
			entrance_positions.append(Vector2(float(stop["x"]), float(stop["z"])))
		var station_position := Vector2(float(station["x"]), float(station["z"]))
		entrance_positions.sort_custom(
			func(a: Vector2, b: Vector2) -> bool:
				return a.distance_squared_to(station_position) \
					< b.distance_squared_to(station_position)
		)
	if entrance_positions.is_empty():
		entrance_positions.append(Vector2(float(station["x"]), float(station["z"])))
	for index in mini(entrance_positions.size(), 2):
		var point := entrance_positions[index]
		var entrance := Node3D.new()
		entrance.name = "SurfaceEntrance%d" % index
		entrance.position = Vector3(point.x - parent.position.x, 0.0, point.y - parent.position.z)
		parent.add_child(entrance)
		# A compact stairwell marker leaves the sidewalk open. The dark inset
		# reads as a descending stair rather than a freestanding station box.
		ART.box(entrance, Vector3(0.0, 0.015, 0.0), Vector3(2.4, 0.04, 3.7), Color("101820"))
		for side in [-1.0, 1.0]:
			ART.box(
				entrance, Vector3(side * 1.38, 0.42, 0.0),
				Vector3(0.18, 0.82, 3.8), Color("b8ac91")
			)
			ART.box(
				entrance, Vector3(side * 1.05, 0.72, 0.0),
				Vector3(0.07, 1.2, 0.07), Color("58636a")
			)
		ART.box(entrance, Vector3(0.0, 1.28, 0.0), Vector3(2.6, 0.09, 3.8), Color("58636a"))
		ART.box(entrance, Vector3(0.0, 2.55, -1.35), Vector3(3.6, 0.16, 1.25), Color("4a555d"))
		ART.box(entrance, Vector3(0.0, 3.18, -1.22), Vector3(3.5, 0.72, 0.16), Color("1c3e54"))
		var label := ART.label(
			entrance, Vector3(0.0, 3.2, -1.1),
			str(station.get("name", "")).to_upper(), 32
		)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = Color("fff4d8")


func _route_direction(index: int) -> Vector3:
	if main_route_points.size() < 2:
		return Vector3(0.0, 0.0, -1.0)
	var before := maxi(index - 1, 0)
	var after := mini(index + 1, main_route_points.size() - 1)
	var direction := main_route_points[after] - main_route_points[before]
	direction.y = 0.0
	return direction.normalized() if direction.length_squared() > 0.001 else Vector3(0.0, 0.0, -1.0)


func _route_length(points: Array[Vector3]) -> float:
	var total := 0.0
	for index in range(points.size() - 1):
		total += points[index].distance_to(points[index + 1])
	return total


func _count_way_tag(tag_name: String, expected: String) -> int:
	var count := 0
	for way: Dictionary in source.get("ways", []):
		if str(way.get(tag_name, "")) == expected:
			count += 1
	return count


func get_station_route_index(station_id: String) -> int:
	return int(station_route_indices.get(station_id, -1))
