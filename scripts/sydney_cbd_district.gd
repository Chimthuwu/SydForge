extends "res://scripts/sydney_district.gd"

## Integrated Sydney main-world entry point. The expanded CBD export supplies the
## geography; the shared SydneyWorld importer adds the Opera House, Harbour
## Bridge and Phase 6A harbour water, while DistrictZero owns gameplay.
##
## This is the canonical gameplay scene with the expanded CBD world loaded.
## It reuses the shared player, vehicle, camera, combat and HUD systems; only the
## world source, opening spawn and heading are specialized:
##
##   1. `build_city()` loads `CbdWorld` (the Stage B importer).
##   2. The player starts on the Harbour Bridge eastern walkway. The first car
##      is at the connected southern road entrance.
##   3. The opening heading looks along the bridge.
##
## Test scenes remain available as alternate authoring/playtest entry points.

## Preloaded rather than referenced by `class_name`: a `class_name` only resolves
## after the project's global class cache is rebuilt, and the CBD scene must run
## from a fresh checkout without opening the editor first.
const CbdWorldScript := preload("res://sydney/cbd/cbd_world.gd")
const WorldTimeManagerScript := preload("res://sydney/ecosystem/world_time_manager.gd")
const CityLightsManagerScript := preload("res://sydney/ecosystem/city_lights_manager.gd")
const TrafficManagerScript := preload("res://sydney/ecosystem/traffic_manager.gd")
const PedestrianManagerScript := preload("res://sydney/ecosystem/pedestrian_manager.gd")
const WildlifeManagerScript := preload("res://sydney/ecosystem/wildlife_manager.gd")

const BRIDGE_OPERA_XZ := Vector2(658.72, -1763.81)

var cbd_world


func _sydney_requested() -> bool:
	return true


func build_city() -> void:
	build_environment()
	var world: SydneyWorld = CbdWorldScript.new()
	if world.load_world():
		cbd_world = world
		sydney_world = world
		using_sydney = true
		add_child(world)
	else:
		push_warning("Sydney Stage B failed to load (%s); using District Zero" % world.load_error)
	if not using_sydney:
		build_district_zero()


## The shared environment is tuned for District Zero's 220 m courtyard. Across a
## 5 km city the same sun and 0.32 ambient energy leave entire streets (and the
## cove in front of them) in near-black shadow. This raises ambient light and
## extends the shadow range in this scene only; the sky, sun direction and every
## other scene keep the shared values.
func build_environment() -> void:
	super()
	for node in find_children("*", "WorldEnvironment", true, false):
		var environment := (node as WorldEnvironment).environment
		if environment != null:
			environment.ambient_light_energy = 0.62
			environment.ambient_light_color = Color("cfe0ea")
			# Distance haze gives the harbour and the skyline depth instead of a
			# crisp toy-town horizon. Very light by day, stronger at night.
			environment.fog_enabled = true
			environment.fog_light_color = Color("7d8b94")
			environment.fog_light_energy = 0.7
			environment.fog_density = 0.0011
			environment.fog_aerial_perspective = 0.35
			environment.fog_sky_affect = 0.15
	for node in find_children("*", "DirectionalLight3D", true, false):
		var sun := node as DirectionalLight3D
		sun.directional_shadow_max_distance = 320.0
		sun.shadow_bias = 0.04


func _playtest_spawn() -> Vector3:
	var bridge := _harbour_bridge()
	if bridge != null and bridge.route.size() > 5:
		var index := _opera_view_route_index(bridge)
		return bridge.route[index] + bridge.route_east[index] * 7.5 + Vector3.UP * 0.4
	return super()


func _playtest_look_target() -> Vector3:
	# Look a little above the roofline to clear the bridge's 2.4 m safety rail
	# and keep the Opera House sails visible from the elevated road shoulder.
	return Vector3(BRIDGE_OPERA_XZ.x, 110.0, BRIDGE_OPERA_XZ.y)


func _playtest_message() -> String:
	return "SYDNEY HARBOUR BRIDGE · E: enter the sports car at the overlook"


func _harbour_bridge() -> Node3D:
	if cbd_world == null:
		return null
	return cbd_world.get_node_or_null("HarbourBridge")


func _opera_view_route_index(bridge: Node3D) -> int:
	var route: Array = bridge.get("route")
	var route_east: Array = bridge.get("route_east")
	var reference: Dictionary = bridge.get("reference")
	var pylon_centres: Array = reference.get("pylonCenters", [])
	var best_index := 0
	var best_distance := INF
	for index in route.size():
		var point: Vector3 = route[index]
		var east: Vector3 = route_east[index]
		var view_start := Vector2(point.x + east.x * 11.0, point.z + east.z * 11.0)
		var blocked_by_pylon := false
		for pylon: Array in pylon_centres:
			var pylon_point := Vector2(float(pylon[0]), float(pylon[1]))
			if _distance_to_segment(pylon_point, view_start, BRIDGE_OPERA_XZ) < 28.0:
				blocked_by_pylon = true
				break
		if blocked_by_pylon:
			continue
		var distance := Vector2(point.x - BRIDGE_OPERA_XZ.x, point.z - BRIDGE_OPERA_XZ.y).length_squared()
		if distance < best_distance:
			best_distance = distance
			best_index = index
	return best_index


func _distance_to_segment(point: Vector2, start: Vector2, finish: Vector2) -> float:
	var segment := finish - start
	var length_squared := segment.length_squared()
	if length_squared <= 0.0001:
		return point.distance_to(start)
	var t := clampf((point - start).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(start + segment * t)


func _place_vehicle_at_bridge(car: ArcadeCar, bridge: Node3D, route_index: int, lane: float) -> void:
	var route: Array = bridge.get("route")
	var route_east: Array = bridge.get("route_east")
	var point: Vector3 = route[route_index]
	var east: Vector3 = route_east[route_index]
	var next: Vector3 = route[mini(route_index + 1, route.size() - 1)]
	var forward := next - point
	car.global_position = point + east * lane + Vector3.UP * 0.5
	car.rotation.y = atan2(-forward.x, -forward.z)
	car.home = car.global_position


func _ready() -> void:
	super()
	if not using_sydney or player == null:
		return
	var bridge := _harbour_bridge()
	if bridge != null and bridge.route.size() >= 6 and vehicles.size() > 1:
		# Canonical opening: the player starts in the sports car on the bridge
		# overlook, facing along the deck in the late-afternoon light.
		var overlook_index := _opera_view_route_index(bridge)
		_place_vehicle_at_bridge(vehicles[1], bridge, overlook_index, 7.5)
		vehicles[1].enter(player)
		player.spawn = vehicles[1].global_position
		rig.yaw = vehicles[1].rotation.y
		message = "SYDNEY HARBOUR BRIDGE · drive into the city"
	_initialize_living_ecosystem()
	var time_mgr := get_node_or_null("WorldTimeManager")
	if time_mgr != null:
		time_mgr.set_time(11.0)


func _initialize_living_ecosystem() -> void:
	# 1. Day / Night World Time Manager
	var time_mgr = WorldTimeManagerScript.new()
	time_mgr.name = "WorldTimeManager"
	add_child(time_mgr)
	
	# 2. City Lights Manager (streetlights, Opera House & Bridge illumination)
	var lights_mgr = CityLightsManagerScript.new()
	lights_mgr.name = "CityLightsManager"
	add_child(lights_mgr)
	lights_mgr.setup(cbd_world, player, vehicles)
	
	# 3. Traffic Manager (varied vehicle classes, buses, trucks, utes, motorbikes)
	var traffic_mgr = TrafficManagerScript.new()
	traffic_mgr.name = "TrafficManager"
	add_child(traffic_mgr)
	traffic_mgr.setup(cbd_world, player)
	
	# 4. Pedestrian Population Manager (footpaths, promenades, crossings)
	var ped_mgr = PedestrianManagerScript.new()
	ped_mgr.name = "PedestrianManager"
	add_child(ped_mgr)
	ped_mgr.setup(cbd_world, player)
	
	# 5. Wildlife Manager (Australian White Ibis / bin chickens, seagulls, pigeons)
	var wild_mgr = WildlifeManagerScript.new()
	wild_mgr.name = "WildlifeManager"
	add_child(wild_mgr)
	wild_mgr.setup(cbd_world, player)
