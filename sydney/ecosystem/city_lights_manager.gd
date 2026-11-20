class_name CityLightsManager
extends Node3D

## Builds static Sydney lamp meshes once, then lights only the nearby road
## fixtures. Distant lamps remain inexpensive emissive geometry; the renderer
## never has to process thousands of dynamic light nodes.

const ART := preload("res://scripts/art.gd")
const MAX_STREETLIGHTS := 6500
const ACTIVE_STREETLIGHTS := 18
const ACTIVE_LANDMARK_LIGHTS := 6
const STREETLIGHT_RANGE := 30.0
const BUILDING_GRID_SIZE := 40.0
const WINDOW_EMISSION_LEVELS := [3.2, 2.4, 2.0]

var streetlights: Array[Node3D] = []
var street_spotlights: Array[SpotLight3D] = []
var landmark_lights: Array[Light3D] = []

var is_night: bool = false
var sydney_world: SydneyWorld

var _player_ref: Node3D
var _lighting_factor: float = 0.0
var _street_records: Array[Dictionary] = []
var _landmark_records: Array[Dictionary] = []
var _window_materials: Array[StandardMaterial3D] = []
var _landmark_materials: Array[Dictionary] = []
var _vehicle_lights: Array[Dictionary] = []
var _lamp_head_material: StandardMaterial3D
var _facade_materials: Array[ShaderMaterial] = []
var _street_base_energies: Array[float] = []
var _update_timer: float = 0.0
var _building_grid: Dictionary = {}
var _occupied_light_cells: Dictionary = {}


func _ready() -> void:
	add_to_group("city_lights")
	var time_manager := get_tree().get_first_node_in_group("time_managers") as WorldTimeManager
	if time_manager != null:
		is_night = time_manager.is_night
		_lighting_factor = time_manager.lighting_factor
		time_manager.night_mode_changed.connect(_on_night_mode_changed)
		time_manager.lighting_factor_changed.connect(_on_lighting_factor_changed)


func setup(world: SydneyWorld, player: Node3D, vehicles: Array = []) -> void:
	sydney_world = world
	_player_ref = player
	_build_building_grid(world.data.get("buildings", []))
	_generate_streetlights()
	_setup_window_illumination()
	_setup_landmark_illumination()
	_cache_facade_materials()
	for vehicle in vehicles:
		if vehicle is Node3D:
			_attach_player_vehicle_lights(vehicle as Node3D)
	_select_nearby_streetlights()
	_select_landmark_lights()
	_apply_lighting_factor(_lighting_factor)


func _cache_facade_materials() -> void:
	_facade_materials.clear()
	for node in get_tree().get_nodes_in_group("facade_surfaces"):
		var surface := node as MeshInstance3D
		if surface != null and surface.material_override is ShaderMaterial:
			_facade_materials.append(surface.material_override as ShaderMaterial)


func _process(delta: float) -> void:
	_update_timer += delta
	if _update_timer < 0.25:
		return
	_update_timer = 0.0
	_select_nearby_streetlights()
	_select_landmark_lights()
	_apply_streetlight_energies()
	_apply_landmark_energies()
	_update_player_vehicle_visibility()


func _on_night_mode_changed(night: bool) -> void:
	is_night = night


func _on_lighting_factor_changed(factor: float) -> void:
	_apply_lighting_factor(factor)


func _apply_lighting_factor(factor: float) -> void:
	_lighting_factor = clampf(factor, 0.0, 1.0)
	# Facade windows share one shader parameter instead of thousands of light
	# nodes. Setting it here keeps day/night, dusk and dawn in one place.
	if _facade_materials.is_empty():
		_cache_facade_materials()
	for material in _facade_materials:
		material.set_shader_parameter("night_factor", _lighting_factor)
	if _lamp_head_material != null:
		_lamp_head_material.emission_energy_multiplier = _lighting_factor * 3.2
	for index in _window_materials.size():
		_window_materials[index].emission_energy_multiplier = (
			float(WINDOW_EMISSION_LEVELS[index]) * _lighting_factor
		)
	for record: Dictionary in _landmark_materials:
		var landmark_material := record["material"] as StandardMaterial3D
		landmark_material.emission_energy_multiplier = float(record["energy"]) * _lighting_factor
	for attachment: Dictionary in _vehicle_lights:
		var spot := attachment["spot"] as SpotLight3D
		var rear := attachment["rear"] as OmniLight3D
		spot.light_energy = float(attachment["spot_energy"]) * _lighting_factor
		rear.light_energy = 0.8 * _lighting_factor
		for material: StandardMaterial3D in attachment["head_materials"]:
			material.emission_energy_multiplier = 2.4 * _lighting_factor
		for material: StandardMaterial3D in attachment["tail_materials"]:
			material.emission_energy_multiplier = 1.8 * _lighting_factor
	_apply_streetlight_energies()
	_apply_landmark_energies()
	_update_player_vehicle_visibility()


func _generate_streetlights() -> void:
	if sydney_world == null:
		return
	_street_records.clear()
	_occupied_light_cells.clear()
	_add_road_fixtures()
	_add_bridge_fixtures()
	_add_waterfront_fixtures()
	if _street_records.is_empty():
		return

	var body_material := StandardMaterial3D.new()
	body_material.albedo_color = Color("303940")
	body_material.metallic = 0.62
	body_material.roughness = 0.52
	var body_instance := _create_lamp_multimesh(
		"StreetlightPoles", _make_lamp_body_mesh(), body_material
	)
	var head_material := StandardMaterial3D.new()
	head_material.albedo_color = Color("ded8c8")
	head_material.roughness = 0.42
	head_material.emission_enabled = true
	head_material.emission = Color("ffe2b0")
	head_material.emission_energy_multiplier = 0.0
	_lamp_head_material = head_material
	var head_instance := _create_lamp_multimesh(
		"StreetlightHeads", _make_lamp_head_mesh(), head_material
	)
	if body_instance != null:
		streetlights.append(body_instance)
	if head_instance != null:
		streetlights.append(head_instance)

	_street_base_energies.clear()
	for index in ACTIVE_STREETLIGHTS:
		var spot := SpotLight3D.new()
		spot.name = "ActiveStreetlight%02d" % index
		spot.spot_range = STREETLIGHT_RANGE
		spot.spot_angle = 68.0
		spot.light_color = Color("ffe2bf")
		spot.light_energy = 0.0
		spot.shadow_enabled = false
		spot.spot_attenuation = 1.35
		spot.visible = false
		add_child(spot)
		street_spotlights.append(spot)
		_street_base_energies.append(0.0)


func _add_road_fixtures() -> void:
	var roads: Array = sydney_world.data.get("roads", [])
	for road: Dictionary in roads:
		if _street_records.size() >= MAX_STREETLIGHTS:
			return
		if bool(road.get("tunnel", false)):
			continue
		var road_type := String(road.get("highway", ""))
		var spacing := 0.0
		var both_sides := false
		match road_type:
			"trunk", "primary", "primary_link", "trunk_link":
				spacing = 36.0
				both_sides = true
			"secondary", "secondary_link":
				spacing = 48.0
			"tertiary", "tertiary_link":
				spacing = 58.0
			"residential", "living_street", "unclassified":
				spacing = 78.0
			"pedestrian":
				spacing = 48.0
			"motorway_link":
				spacing = 58.0
			_:
				continue
		var raw_points: Array = road.get("points", [])
		if raw_points.size() < 2:
			continue
		_sample_road_for_lights(
			raw_points,
			float(road.get("widthM", 8.0)),
			spacing,
			both_sides,
			1.0 if both_sides else 0.0
		)


func _sample_road_for_lights(
	raw_points: Array,
	road_width: float,
	spacing: float,
	both_sides: bool,
	priority: float
) -> void:
	var distance_to_next := spacing
	var sample_index := 0
	for segment_index in range(raw_points.size() - 1):
		var a := Vector2(float(raw_points[segment_index][0]), float(raw_points[segment_index][1]))
		var b := Vector2(float(raw_points[segment_index + 1][0]), float(raw_points[segment_index + 1][1]))
		var segment := b - a
		var segment_length := segment.length()
		if segment_length < 0.01:
			continue
		var direction := segment / segment_length
		var perpendicular := Vector2(-direction.y, direction.x)
		while distance_to_next <= segment_length:
			var center := a + direction * distance_to_next
			var sides: Array = [-1.0, 1.0] if both_sides else [
				1.0 if sample_index % 2 == 0 else -1.0
			]
			for side: float in sides:
				var offset := road_width * 0.5 + (1.5 if road_width < 18.0 else 2.5)
				var candidate := center + perpendicular * offset * side
				var position := Vector3(candidate.x, 0.05, candidate.y)
				var aim := Vector3(-perpendicular.x * side, 0.0, -perpendicular.y * side)
				_add_street_fixture(position, aim, priority)
			sample_index += 1
			distance_to_next += spacing
		distance_to_next -= segment_length


func _add_bridge_fixtures() -> void:
	var bridge := sydney_world.get_node_or_null("HarbourBridge")
	if bridge == null:
		return
	var route: Array = bridge.get("route")
	var route_east: Array = bridge.get("route_east")
	for index in range(0, route.size(), 7):
		var point: Vector3 = route[index]
		var east: Vector3 = route_east[index]
		# Keep poles beside the separated pedestrian path, clear of the carriageway
		# and its rail-corridor structures.
		var position := point + east * 18.7 + Vector3.UP * 0.16
		_add_street_fixture(position, -east, 0.65)


func _add_waterfront_fixtures() -> void:
	# Short runs on public waterfront paths that are not represented as road
	# centre-lines. These are sparse accents; the road sampler does the city-wide
	# coverage.
	var paths := [
		[Vector3(180.0, 0.0, -1510.0), Vector3(340.0, 0.0, -1575.0)],
		[Vector3(-520.0, 0.0, -780.0), Vector3(-390.0, 0.0, -1040.0)],
		[Vector3(-700.0, 0.0, -540.0), Vector3(-510.0, 0.0, -500.0)],
		[Vector3(300.0, 0.0, -330.0), Vector3(342.0, 0.0, -70.0)],
		[Vector3(450.0, 0.0, -570.0), Vector3(590.0, 0.0, -760.0)],
	]
	for path: Array in paths:
		var a: Vector3 = path[0]
		var b: Vector3 = path[1]
		var direction := Vector2(b.x - a.x, b.z - a.z).normalized()
		var perpendicular := Vector2(-direction.y, direction.x)
		var length := Vector2(b.x - a.x, b.z - a.z).length()
		var count := maxi(1, int(length / 46.0))
		for index in range(1, count):
			var t := float(index) / float(count)
			var center := a.lerp(b, t)
			var position := center + Vector3(perpendicular.x * 1.5, 0.05, perpendicular.y * 1.5)
			_add_street_fixture(position, Vector3(-perpendicular.x, 0.0, -perpendicular.y), 0.25)


func _add_street_fixture(position: Vector3, aim: Vector3, priority: float) -> void:
	if _street_records.size() >= MAX_STREETLIGHTS or _inside_building(position):
		return
	var cell := Vector2i(roundi(position.x / 10.0), roundi(position.z / 10.0))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var key := cell + Vector2i(dx, dz)
			for existing: Vector3 in _occupied_light_cells.get(key, []):
				if Vector2(position.x - existing.x, position.z - existing.z).length_squared() < 64.0:
					return
	if not _occupied_light_cells.has(cell):
		_occupied_light_cells[cell] = []
	_occupied_light_cells[cell].append(position)
	var flat_aim := Vector3(aim.x, 0.0, aim.z).normalized()
	if flat_aim.length_squared() < 0.9:
		flat_aim = Vector3.FORWARD
	_street_records.append({
		"position": position,
		"aim": flat_aim,
		"priority": priority,
		"energy": 4.4 if priority > 0.8 else 3.8,
		"range": STREETLIGHT_RANGE,
	})


func _build_building_grid(rows: Array) -> void:
	_building_grid.clear()
	for row: Dictionary in rows:
		var ring: Array = row.get("ring", [])
		if ring.size() < 3:
			continue
		var min_x := INF
		var max_x := -INF
		var min_z := INF
		var max_z := -INF
		for point: Array in ring:
			min_x = minf(min_x, float(point[0]))
			max_x = maxf(max_x, float(point[0]))
			min_z = minf(min_z, float(point[1]))
			max_z = maxf(max_z, float(point[1]))
		var min_cell := Vector2i(
			int(floor(min_x / BUILDING_GRID_SIZE)),
			int(floor(min_z / BUILDING_GRID_SIZE))
		)
		var max_cell := Vector2i(
			int(floor(max_x / BUILDING_GRID_SIZE)),
			int(floor(max_z / BUILDING_GRID_SIZE))
		)
		for x in range(min_cell.x, max_cell.x + 1):
			for z in range(min_cell.y, max_cell.y + 1):
				var key := Vector2i(x, z)
				if not _building_grid.has(key):
					_building_grid[key] = []
				_building_grid[key].append(ring)


func _inside_building(position: Vector3) -> bool:
	var cell := Vector2i(
		int(floor(position.x / BUILDING_GRID_SIZE)),
		int(floor(position.z / BUILDING_GRID_SIZE))
	)
	for ring: Array in _building_grid.get(cell, []):
		var polygon := PackedVector2Array()
		for point: Array in ring:
			polygon.append(Vector2(float(point[0]), float(point[1])))
		if Geometry2D.is_point_in_polygon(Vector2(position.x, position.z), polygon):
			return true
	return false


func _create_lamp_multimesh(node_name: String, mesh: ArrayMesh, material: Material) -> MultiMeshInstance3D:
	if mesh == null or _street_records.is_empty():
		return null
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = _street_records.size()
	for index in _street_records.size():
		var record: Dictionary = _street_records[index]
		var aim: Vector3 = record["aim"]
		var x_axis := aim.normalized()
		var z_axis := x_axis.cross(Vector3.UP).normalized()
		var transform := Transform3D(
			Basis(x_axis, Vector3.UP, z_axis),
			record["position"]
		)
		multimesh.set_instance_transform(index, transform)
	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multimesh
	instance.material_override = material
	add_child(instance)
	return instance


func _make_lamp_body_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pole := CylinderMesh.new()
	pole.top_radius = 0.045
	pole.bottom_radius = 0.09
	pole.height = 6.25
	pole.radial_segments = 8
	surface.append_from(pole, 0, Transform3D(Basis.IDENTITY, Vector3(0.0, 3.125, 0.0)))
	var arm := BoxMesh.new()
	arm.size = Vector3(1.3, 0.085, 0.085)
	surface.append_from(arm, 0, Transform3D(Basis.IDENTITY, Vector3(0.56, 6.05, 0.0)))
	var housing := BoxMesh.new()
	housing.size = Vector3(0.55, 0.17, 0.29)
	surface.append_from(housing, 0, Transform3D(Basis.IDENTITY, Vector3(1.17, 5.91, 0.0)))
	return surface.commit()


func _make_lamp_head_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lens := BoxMesh.new()
	lens.size = Vector3(0.38, 0.045, 0.21)
	surface.append_from(lens, 0, Transform3D(Basis.IDENTITY, Vector3(1.17, 5.81, 0.0)))
	return surface.commit()


func _fixture_basis(aim: Vector3) -> Basis:
	var x_axis := Vector3(aim.x, 0.0, aim.z).normalized()
	if x_axis.length_squared() < 0.9:
		x_axis = Vector3.RIGHT
	return Basis(x_axis, Vector3.UP, x_axis.cross(Vector3.UP).normalized())


func _select_nearby_streetlights() -> void:
	if _player_ref == null or street_spotlights.is_empty():
		return
	var player_position := _player_ref.global_position
	var candidates: Array[Dictionary] = []
	for record: Dictionary in _street_records:
		var position: Vector3 = record["position"]
		var distance_sq := Vector2(
			position.x - player_position.x,
			position.z - player_position.z
		).length_squared()
		if distance_sq > 125.0 * 125.0:
			continue
		var candidate := record.duplicate()
		candidate["distance_sq"] = distance_sq
		candidate["score"] = sqrt(distance_sq) - float(record["priority"]) * 18.0
		candidates.append(candidate)
	candidates.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return float(a["score"]) < float(b["score"])
	)
	for index in street_spotlights.size():
		var light := street_spotlights[index]
		if index >= candidates.size():
			light.visible = false
			_street_base_energies[index] = 0.0
			continue
		var record: Dictionary = candidates[index]
		var position: Vector3 = record["position"]
		var aim: Vector3 = record["aim"]
		var head_position := position + Vector3.UP * 5.83 + aim * 1.16
		light.global_position = head_position
		light.look_at(position + aim * 4.0 + Vector3.UP * 0.1, Vector3.UP)
		light.spot_range = float(record["range"])
		_street_base_energies[index] = float(record["energy"])
		light.visible = true


func _apply_streetlight_energies() -> void:
	for index in street_spotlights.size():
		var light := street_spotlights[index]
		var base := _street_base_energies[index] if index < _street_base_energies.size() else 0.0
		if base <= 0.0 or _lighting_factor <= 0.005:
			light.visible = false
			light.light_energy = 0.0
		else:
			light.visible = true
			light.light_energy = base * _lighting_factor


func _setup_window_illumination() -> void:
	var window_node := sydney_world.get_node_or_null("NightWindows") as MeshInstance3D
	if window_node == null or window_node.mesh == null:
		return
	_window_materials.clear()
	for surface_index in window_node.mesh.get_surface_count():
		var material := window_node.mesh.surface_get_material(surface_index) as StandardMaterial3D
		if material == null:
			continue
		_window_materials.append(material)


func _setup_landmark_illumination() -> void:
	_landmark_records.clear()
	landmark_lights.clear()
	_landmark_materials.clear()
	_setup_bridge_emission()
	_setup_opera_emission()
	var locations: Array[Dictionary] = []
	for item: Dictionary in [
		{"osm_id": "way/40717424", "name": "Queen Victoria Building", "energy": 2.2},
		{"osm_id": "way/104948253", "name": "Sydney Town Hall", "energy": 2.4},
		{"osm_id": "way/16749128", "name": "St Mary's Cathedral", "energy": 1.8},
	]:
		var center: Variant = _building_center(String(item["osm_id"]))
		if center != null:
			locations.append({
				"name": item["name"],
				"center": center,
				"energy": float(item["energy"]),
			})
	for item: Dictionary in locations:
		var center: Vector3 = item["center"]
		_add_landmark_spot(
			String(item["name"]) + " west wash",
			center + Vector3(-24.0, 10.0, 16.0),
			center + Vector3(0.0, 9.0, 0.0),
			58.0, 64.0, float(item["energy"]), Color("ffe0b8")
		)
		_add_landmark_spot(
			String(item["name"]) + " east wash",
			center + Vector3(24.0, 10.0, -16.0),
			center + Vector3(0.0, 10.0, 0.0),
			58.0, 64.0, float(item["energy"]), Color("ffe0b8")
		)

	# These public-space accents supplement, rather than replace, the road lamps.
	_add_landmark_spot("Hyde Park path north", Vector3(315.0, 12.0, -140.0),
		Vector3(332.0, 0.2, -195.0), 54.0, 74.0, 1.6, Color("ffe5c6"))
	_add_landmark_spot("Hyde Park path south", Vector3(315.0, 12.0, -300.0),
		Vector3(300.0, 0.2, -325.0), 54.0, 74.0, 1.6, Color("ffe5c6"))
	_add_landmark_spot("Circular Quay promenade", Vector3(245.0, 10.0, -1490.0),
		Vector3(275.0, 0.2, -1545.0), 58.0, 72.0, 1.8, Color("ffe2bf"))
	_add_landmark_spot("Barangaroo waterfront", Vector3(-465.0, 11.0, -1000.0),
		Vector3(-435.0, 0.2, -1060.0), 64.0, 76.0, 1.9, Color("ffe2bf"))
	_add_landmark_spot("Darling Harbour promenade", Vector3(-650.0, 11.0, -610.0),
		Vector3(-625.0, 0.2, -660.0), 62.0, 76.0, 1.9, Color("ffe2bf"))
	_add_landmark_spot("Woolloomooloo wharf", Vector3(365.0, 10.0, 170.0),
		Vector3(405.0, 0.2, 140.0), 56.0, 74.0, 1.7, Color("ffe2bf"))
	_add_landmark_spot("Central Station frontage", Vector3(-220.0, 12.0, 995.0),
		Vector3(-174.0, 7.0, 1050.0), 62.0, 70.0, 2.0, Color("ffe0b8"))
	_add_bridge_lights()
	_add_opera_lights()


func _setup_bridge_emission() -> void:
	var bridge := sydney_world.get_node_or_null("HarbourBridge")
	if bridge == null:
		return
	var steel := bridge.get_node_or_null("Steel") as MeshInstance3D
	_add_emission_to_mesh(steel, Color("829bb5"), 0.32)


func _setup_opera_emission() -> void:
	var opera := sydney_world.get_node_or_null("OperaHouse")
	if opera == null:
		return
	for node_name in ["OperaShells", "OperaGlazing"]:
		var mesh_instance := opera.get_node_or_null(node_name) as MeshInstance3D
		_add_emission_to_mesh(mesh_instance, Color("ffe5c8"), 0.2 if node_name == "OperaShells" else 0.12)


func _add_emission_to_mesh(
	instance: MeshInstance3D,
	color: Color,
	base_energy: float
) -> void:
	if instance == null or instance.mesh == null:
		return
	for surface_index in instance.mesh.get_surface_count():
		var original := instance.mesh.surface_get_material(surface_index) as StandardMaterial3D
		if original == null:
			continue
		var material := original.duplicate() as StandardMaterial3D
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 0.0
		instance.mesh.surface_set_material(surface_index, material)
		_landmark_materials.append({"material": material, "energy": base_energy})


func _building_center(osm_id: String) -> Variant:
	for row: Dictionary in sydney_world.data.get("buildings", []):
		if String(row.get("id", "")) != osm_id:
			continue
		var ring: Array = row.get("ring", [])
		if ring.is_empty():
			return null
		var center := Vector2.ZERO
		for point: Array in ring:
			center += Vector2(float(point[0]), float(point[1]))
		center /= float(ring.size())
		return Vector3(center.x, 0.0, center.y)
	return null


func _add_bridge_lights() -> void:
	var bridge := sydney_world.get_node_or_null("HarbourBridge")
	if bridge == null:
		return
	for s in [-190.0, -95.0, 0.0, 95.0, 190.0]:
		var target: Vector3 = bridge.call("point", s, 0.0, float(bridge.call("upper", s)) * 0.76)
		var position: Vector3 = bridge.call("point", s, -92.0, 28.0)
		_add_landmark_spot(
			"Harbour Bridge arch wash",
			position, target, 175.0, 62.0, 2.6, Color("d8e7ff")
		)
	for xy: Array in bridge.get("reference").get("pylonCenters", []):
		var pylon := Vector3(float(xy[0]), 0.0, float(xy[1]))
		_add_landmark_spot(
			"Harbour Bridge pylon wash",
			pylon + Vector3(35.0, 22.0, 42.0),
			pylon + Vector3.UP * 38.0,
			72.0, 70.0, 2.2, Color("ffe5c8")
		)


func _add_opera_lights() -> void:
	var target := Vector3(658.72, 27.0, -1763.81)
	_add_landmark_spot(
		"Opera House western sail wash",
		Vector3(520.0, 18.0, -1695.0), target + Vector3(-25.0, 12.0, 0.0),
		190.0, 58.0, 2.8, Color("fff0d7")
	)
	_add_landmark_spot(
		"Opera House eastern sail wash",
		Vector3(790.0, 18.0, -1818.0), target + Vector3(22.0, 10.0, 0.0),
		170.0, 58.0, 2.6, Color("fff0d7")
	)


func _add_landmark_spot(
	light_name: String,
	position: Vector3,
	target: Vector3,
	range_m: float,
	angle_degrees: float,
	energy: float,
	color: Color
) -> void:
	var light := SpotLight3D.new()
	light.name = light_name
	light.spot_range = range_m
	light.spot_angle = angle_degrees
	light.light_color = color
	light.light_energy = 0.0
	light.shadow_enabled = false
	light.spot_attenuation = 1.2
	light.visible = false
	add_child(light)
	light.global_position = position
	light.look_at(target, Vector3.UP)
	landmark_lights.append(light)
	_landmark_records.append({
		"light": light,
		"position": position,
		"energy": energy,
		"range": range_m,
		"base_energy": 0.0,
		"active": false,
	})


func _select_landmark_lights() -> void:
	if _player_ref == null or _landmark_records.is_empty():
		return
	var candidates: Array[Dictionary] = []
	var player_position := _player_ref.global_position
	for index in _landmark_records.size():
		var record: Dictionary = _landmark_records[index]
		var position: Vector3 = record["position"]
		var distance_sq := Vector2(
			position.x - player_position.x,
			position.z - player_position.z
		).length_squared()
		if distance_sq <= 260.0 * 260.0:
			candidates.append({
				"index": index,
				"distance_sq": distance_sq,
			})
	candidates.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return float(a["distance_sq"]) < float(b["distance_sq"])
	)
	for record: Dictionary in _landmark_records:
		record["active"] = false
		record["base_energy"] = 0.0
	var active_count := 0
	for candidate: Dictionary in candidates:
		if active_count >= ACTIVE_LANDMARK_LIGHTS:
			break
		var index: int = candidate["index"]
		var distance := sqrt(float(candidate["distance_sq"]))
		var record: Dictionary = _landmark_records[index]
		record["active"] = true
		record["base_energy"] = float(record["energy"]) * clampf(1.15 - distance / 520.0, 0.15, 1.0)
		active_count += 1


func _apply_landmark_energies() -> void:
	for record: Dictionary in _landmark_records:
		var light := record["light"] as SpotLight3D
		var active := bool(record.get("active", false))
		var base := float(record.get("base_energy", 0.0))
		if not active or base <= 0.0 or _lighting_factor <= 0.005:
			light.visible = false
			light.light_energy = 0.0
		else:
			light.visible = true
			light.light_energy = base * _lighting_factor


func _attach_player_vehicle_lights(vehicle: Node3D) -> void:
	if vehicle.get_node_or_null("NightVehicleLights") != null:
		return
	var group := Node3D.new()
	group.name = "NightVehicleLights"
	vehicle.add_child(group)
	var head_materials: Array[StandardMaterial3D] = []
	var tail_materials: Array[StandardMaterial3D] = []
	for side in [-1.0, 1.0]:
		var head := ART.box(
			group, Vector3(side * 0.58, 0.68, -2.13),
			Vector3(0.32, 0.17, 0.06), Color.WHITE
		)
		var head_material := _emissive_material(Color("fff2d8"), Color("fff1d7"))
		head.material_override = head_material
		head_materials.append(head_material)
		var tail := ART.box(
			group, Vector3(side * 0.62, 0.62, 2.13),
			Vector3(0.3, 0.17, 0.06), Color("8a1018")
		)
		var tail_material := _emissive_material(Color("b41d27"), Color("ff2635"))
		tail.material_override = tail_material
		tail_materials.append(tail_material)
	var spot := SpotLight3D.new()
	spot.name = "HeadlightBeam"
	spot.position = Vector3(0.0, 0.72, -2.2)
	spot.rotation_degrees.x = -4.0
	spot.spot_range = 34.0
	spot.spot_angle = 48.0
	spot.light_color = Color("fff0d5")
	spot.light_energy = 0.0
	spot.shadow_enabled = false
	group.add_child(spot)
	var rear := OmniLight3D.new()
	rear.name = "RearGlow"
	rear.position = Vector3(0.0, 0.72, 2.17)
	rear.omni_range = 5.0
	rear.light_color = Color("ff2934")
	rear.light_energy = 0.0
	rear.shadow_enabled = false
	group.add_child(rear)
	_vehicle_lights.append({
		"root": vehicle,
		"spot": spot,
		"rear": rear,
		"spot_energy": 3.2,
		"head_materials": head_materials,
		"tail_materials": tail_materials,
	})


func _emissive_material(albedo: Color, emission: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = albedo
	material.emission_enabled = true
	material.emission = emission
	material.emission_energy_multiplier = 0.0
	material.roughness = 0.4
	return material


func _update_player_vehicle_visibility() -> void:
	if _player_ref == null:
		return
	var player_position := _player_ref.global_position
	for attachment: Dictionary in _vehicle_lights:
		var vehicle := attachment["root"] as Node3D
		if not is_instance_valid(vehicle):
			continue
		var distance_sq := player_position.distance_squared_to(vehicle.global_position)
		var active := _lighting_factor > 0.01 and distance_sq < 130.0 * 130.0
		(attachment["spot"] as SpotLight3D).visible = active
		(attachment["rear"] as OmniLight3D).visible = active
