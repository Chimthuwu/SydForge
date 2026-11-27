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
const HarbourBoatsScript := preload("res://sydney/harbour/harbour_boats.gd")
const TrainManagerScript := preload("res://sydney/railway/train_manager.gd")
const WantedSystemScript := preload("res://scripts/wanted_system.gd")
const WeatherManagerScript := preload("res://sydney/ecosystem/weather_manager.gd")
const BusinessManagerScript := preload("res://sydney/ecosystem/business_manager.gd")
const AmbientEventDirectorScript := preload("res://sydney/ecosystem/ambient_event_director.gd")
const EmergencyIncidentManagerScript := preload("res://sydney/ecosystem/emergency_incident_manager.gd")
const AmbientAudioDirectorScript := preload("res://sydney/ecosystem/ambient_audio_director.gd")
const WorldSimulationDirectorScript := preload("res://sydney/ecosystem/world_simulation_director.gd")
const MainMenuScript := preload("res://scripts/main_menu.gd")
const PauseMenuScript := preload("res://scripts/pause_menu.gd")
const VehicleTrafficControllerScript := preload("res://sydney/ecosystem/vehicle_traffic_controller.gd")
const VehicleVisualBuilderScript := preload("res://sydney/ecosystem/vehicle_visual_builder.gd")

const BRIDGE_OPERA_XZ := Vector2(658.72, -1763.81)

## Menu spawn ids mapped to exported viewpoints. The bridge keeps its canonical
## sports-car opening; every other choice drops the player on a walkable road
## point with its authored heading.
const MENU_VIEWPOINTS := {
	"central": "central",
	"town_hall": "town_hall",
	"circular_quay": "circular_quay",
	"the_rocks": "the_rocks",
	"barangaroo": "barangaroo",
}
const MENU_MESSAGES := {
	"central": "CENTRAL STATION · George Street and Railway Square",
	"town_hall": "TOWN HALL · George Street civic centre",
	"circular_quay": "CIRCULAR QUAY · ferries, promenade and the Opera House",
	"the_rocks": "THE ROCKS · historic waterfront lanes",
	"barangaroo": "BARANGAROO · waterfront towers and the reserve",
}

## Exotics parked at landmark kerbs so they can be found on foot instead of
## waiting for one to drive past. Each sits at the nearest kerb lane to the
## named menu viewpoint, facing along the road.
const SHOWCASE_CARS := [
	{"id": "ParkedRoadster", "viewpoint": "central", "class": VehicleVisualBuilderScript.VehicleClass.ROADSTER, "paint": Color("ffd23f")},
	{"id": "ParkedHypercar", "viewpoint": "circular_quay", "class": VehicleVisualBuilderScript.VehicleClass.HYPERCAR, "paint": Color("2ec4b6")},
	{"id": "ParkedTrackCar", "viewpoint": "the_rocks", "class": VehicleVisualBuilderScript.VehicleClass.TRACK_CAR, "paint": Color("b5179e")},
]

var cbd_world
var world_sim
var pause_menu: CanvasLayer
var _return_to_menu_pending := false


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
		# 320 m of shadows over ~2,000 casters doubled the draw-call count for
		# very little visible gain in this dense, mostly night-time city.
		sun.directional_shadow_max_distance = 150.0
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
	if _menu_allowed():
		GameSettingsScript.load_settings()
		GameSettingsScript.apply()
	_maybe_show_main_menu()


## Esc pauses the real game. Headless suites and capture tools keep the base
## district behaviour (mouse capture toggle) so they do not freeze on a frame.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _menu_allowed() and pause_menu == null:
		if get_node_or_null("MainMenu") != null:
			return
		_open_pause_menu()
		get_viewport().set_input_as_handled()
		return
	super._unhandled_input(event)


func _open_pause_menu() -> void:
	pause_menu = PauseMenuScript.new()
	pause_menu.name = "PauseMenu"
	add_child(pause_menu)
	pause_menu.connect("closed", Callable(self, "_on_pause_closed"))
	pause_menu.connect("return_requested", Callable(self, "_on_pause_return"))
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_pause_closed() -> void:
	pause_menu = null
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if _return_to_menu_pending:
		_return_to_menu_pending = false
		call_deferred("_reload_to_menu")


func _on_pause_return() -> void:
	_return_to_menu_pending = true


## Reloading the canonical scene returns to the opening time/spawn menu; the
## menu is presented by `_maybe_show_main_menu()` on the fresh scene.
func _reload_to_menu() -> void:
	get_tree().reload_current_scene()


## The opening menu is part of the playable entry point only. Test suites,
## headless runs and the `--script` capture tools keep their canonical defaults.
func _maybe_show_main_menu() -> void:
	await get_tree().process_frame
	if not _menu_allowed():
		return
	var menu: CanvasLayer = MainMenuScript.new()
	menu.name = "MainMenu"
	add_child(menu)
	menu.connect("start_requested", Callable(self, "_on_menu_start"))
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _menu_allowed() -> bool:
	var forced := OS.get_environment("SPLOOGE_MENU")
	if forced == "0":
		return false
	if forced == "1":
		return true
	if DisplayServer.get_name() == "headless":
		return false
	# Tools that instantiate main.tscn under a custom SceneTree script leave
	# `current_scene` empty; only the real game presents the menu.
	return get_tree().current_scene == self


func _on_menu_start(hours: float, spawn_id: String, mode: String = "free_roam") -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var menu := get_node_or_null("MainMenu")
	if menu != null:
		menu.queue_free()
	var time_mgr := get_node_or_null("WorldTimeManager")
	if time_mgr != null:
		time_mgr.set_time(hours)
	if spawn_id == "bridge":
		message = "SYDNEY HARBOUR BRIDGE · drive into the city"
		_apply_menu_mode(mode)
		return
	_spawn_at_viewpoint(spawn_id)
	_apply_menu_mode(mode)


## Menu mode handling. STREET RACE seats the player in a car and starts the
## rival race; the multiplayer modes open (or join) the ENet deathmatch
## session, so neither feature needs a hidden hotkey.
func _apply_menu_mode(mode: String) -> void:
	match mode:
		"street_race":
			_start_menu_race()
		"multiplayer_host":
			if deathmatch_manager != null:
				message = "DEATHMATCH · %s" % deathmatch_manager.host()
		"multiplayer_join":
			if deathmatch_manager != null:
				message = "DEATHMATCH · %s" % deathmatch_manager.join("127.0.0.1")


## The main menu's STREET RACE mode: seat the player in the closest enterable
## car and hand the race straight to the RaceManager, no Y press required.
func _start_menu_race() -> void:
	if player == null or race_manager == null:
		return
	if player.vehicle == null:
		var car := _nearest_enterable_car(48.0)
		if car == null:
			message = "STREET RACE · no car nearby — press E to take one, then Y"
			return
		if not car.call("enter", player):
			message = "STREET RACE · couldn't get into a car — press E, then Y"
			return
	race_manager.try_start_race(player)


func _nearest_enterable_car(radius: float) -> Node3D:
	var best: Node3D = null
	var best_distance := radius
	if player == null:
		return null
	for car in vehicles:
		if not car.has_method("enter") or car.health <= 0:
			continue
		var d := player.global_position.distance_to(car.global_position)
		if d < best_distance:
			best = car
			best_distance = d
	for traffic: Node3D in get_tree().get_nodes_in_group("traffic_vehicles"):
		if not traffic.has_method("enter") or traffic.get("driver") != null:
			continue
		var d := player.global_position.distance_to(traffic.global_position)
		if d < best_distance:
			best = traffic
			best_distance = d
	return best


func _spawn_at_viewpoint(spawn_id: String) -> void:
	if cbd_world == null or player == null:
		return
	var viewpoint_id: String = str(MENU_VIEWPOINTS.get(spawn_id, ""))
	var viewpoint: Dictionary = cbd_world.viewpoints.get(viewpoint_id, {})
	if viewpoint.is_empty():
		push_warning("Main menu: no viewpoint for spawn '%s'" % spawn_id)
		return
	var spawn := Vector3(float(viewpoint.get("x", 0.0)), 0.3, float(viewpoint.get("z", 0.0)))
	player.spawn = spawn
	player.respawn()
	if rig != null:
		rig.yaw = float(viewpoint.get("yawRad", 0.0))
		rig.pitch = clampf(float(viewpoint.get("pitch", -0.04)), -1.2, 1.2)
	message = str(MENU_MESSAGES.get(spawn_id, "SYDNEY"))


## Park the three new performance cars at fixed kerb spots near landmark spawns.
## Positions derive from the exported road network (never hard-coded metres), so
## they stay on the carriageway if the city data is ever re-spliced.
func _park_showcase_cars() -> void:
	if cbd_world == null:
		return
	var traffic := get_node_or_null("TrafficManager")
	if traffic == null or traffic.road_data.is_empty():
		return
	var parked_positions: Array[Vector3] = []
	for entry: Dictionary in SHOWCASE_CARS:
		var view: Dictionary = cbd_world.viewpoints.get(str(entry["viewpoint"]), {})
		if view.is_empty():
			push_warning("Showcase car: no viewpoint '%s'" % entry["viewpoint"])
			continue
		var anchor := Vector2(float(view.get("x", 0.0)), float(view.get("z", 0.0)))
		var best_road: Dictionary = {}
		var best_point := Vector2.ZERO
		var best_index := 0
		var best_distance := INF
		for road: Dictionary in traffic.road_data:
			# Kerbside parking must be on a real carriageway, not the pedestrian
			# way that often happens to be closest to a landmark viewpoint.
			if str(road.get("highway", "")) in ["service", "pedestrian", "footway", "path", "cycleway", "steps", "track"]:
				continue
			if float(road.get("width", 8.0)) < 7.0:
				continue
			var points: Array = road.get("points", [])
			for index in range(points.size() - 1):
				var a: Vector3 = points[index]
				var b: Vector3 = points[index + 1]
				var closest := Geometry2D.get_closest_point_to_segment(anchor, Vector2(a.x, a.z), Vector2(b.x, b.z))
				var distance := anchor.distance_squared_to(closest)
				if distance < best_distance:
					best_distance = distance
					best_point = closest
					best_road = road
					best_index = index
		if best_road.is_empty():
			continue
		var points: Array = best_road.get("points", [])
		var a: Vector3 = points[best_index]
		var b: Vector3 = points[best_index + 1]
		var forward := Vector3(b.x - a.x, 0.0, b.z - a.z)
		if forward.length_squared() < 0.0001:
			continue
		forward = forward.normalized()
		# Kerb lane on the near side of the road: offset from the centreline
		# toward the viewpoint, but never into the footpath.
		var left := Vector3(forward.z, 0.0, -forward.x)
		var to_view := Vector3(anchor.x - best_point.x, 0.0, anchor.y - best_point.y)
		var side := 1.0 if left.dot(to_view) >= 0.0 else -1.0
		# Kerb lane, not the middle of a 22 m one-way ribbon: sit roughly 2.4 m
		# inside the kerb, with 1.6 m as the narrow-street minimum.
		var lane_offset := maxf(1.6, float(best_road.get("width", 8.0)) * 0.5 - 2.4)
		# Pull the car a short way along the kerb so it does not sit under the
		# spawn's signage and read as a prop.
		var segment_length := Vector2(b.x - a.x, b.z - a.z).length()
		var along := minf(12.0, segment_length * 0.5)
		var base := best_point + Vector2(forward.x, forward.z) * along
		var parked := Vector3(base.x, 0.25, base.y) + left * side * lane_offset
		var crowded := false
		for other in parked_positions:
			if parked.distance_to(other) < 8.0:
				crowded = true
				break
		if crowded:
			continue
		var car = VehicleTrafficControllerScript.new()
		car.name = str(entry["id"])
		car.vehicle_class = int(entry["class"])
		car.paint_override = entry["paint"]
		add_child(car)
		car.global_position = parked
		car.rotation.y = atan2(-forward.x, -forward.z)
		car.add_to_group("showcase_vehicles")
		parked_positions.append(parked)
		print("Showcase %s parked on %s (%.1f m) at %.1f, %.1f" % [
			entry["id"], str(best_road.get("name", "")), float(best_road.get("width", 8.0)),
			parked.x, parked.z])


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
	_park_showcase_cars()
	
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

	# 6. Harbour boats (ferries, small craft and a tug)
	var boats := HarbourBoatsScript.new()
	boats.name = "HarbourBoats"
	add_child(boats)
	boats.setup(player)

	# 7. K Set trains on the Milsons Point–Redfern rail corridor
	var trains := TrainManagerScript.new()
	trains.name = "TrainManager"
	add_child(trains)
	trains.setup(cbd_world.get_node_or_null("SydneyRailNetwork"), player)

	# 8. Wanted level and police pursuit
	var wanted := WantedSystemScript.new()
	wanted.name = "WantedSystem"
	wanted.add_to_group("wanted_system")
	add_child(wanted)
	wanted.setup(player)

	# 9. Weather and environmental atmosphere. It supplies overcast/rain factors
	#    to the time manager, which remains the sole owner of sun and sky.
	var weather := WeatherManagerScript.new()
	weather.name = "WeatherManager"
	add_child(weather)
	weather.setup(player)

	# 10. Businesses, venues, outdoor dining and operating hours
	var business := BusinessManagerScript.new()
	business.name = "BusinessManager"
	add_child(business)
	business.setup(player)

	# 11. Shared ambient soundscape (eight crossfaded beds, not hundreds of voices)
	var amb_audio := AmbientAudioDirectorScript.new()
	amb_audio.name = "AmbientAudioDirector"
	add_child(amb_audio)
	amb_audio.setup(player)

	# 12. Controlled emergency incidents and real responding traffic
	var incidents := EmergencyIncidentManagerScript.new()
	incidents.name = "EmergencyIncidentManager"
	add_child(incidents)
	incidents.setup(cbd_world, player)

	# 13. Believable, infrequent ambient micro-events
	var events := AmbientEventDirectorScript.new()
	events.name = "AmbientEventDirector"
	add_child(events)
	events.setup(cbd_world, player)

	# 14. Central coordinator: activity profiles, district budgets and the
	#     single world-event bus used for all world reactivity.
	var sim := WorldSimulationDirectorScript.new()
	sim.name = "WorldSimulationDirector"
	add_child(sim)
	sim.setup(self, player)
	world_sim = sim
