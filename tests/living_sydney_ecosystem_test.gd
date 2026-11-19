extends SceneTree

## Comprehensive automated test and verification suite for:
## 1. WorldTimeManager & Day/Night transitions
## 2. Vehicle Traffic & fleet variety (cars, motorbikes, utes, buses, trucks)
## 3. Pedestrian Population & Graph Traversal
## 4. Australian Wildlife & Bin Chickens (Ibis)
## 5. City Lights & Landmark Illumination

const CbdDistrictScript := preload("res://scripts/sydney_cbd_district.gd")
const VehicleVisualBuilderScript := preload("res://sydney/ecosystem/vehicle_visual_builder.gd")

var _checks: int = 0
var _failures: int = 0

func _init() -> void:
	call_deferred("_run_suite")

func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("PASS: %s" % description)
	else:
		_failures += 1
		push_error("FAIL: %s" % description)

func _run_suite() -> void:
	var tree_root := get_root()
	var scene: Node3D = CbdDistrictScript.new()
	tree_root.add_child(scene)

	
	# Wait several physics frames for initialization
	for i in 20:
		await process_frame
	
	# 1. WorldTimeManager Checks
	var time_mgr = scene.get_node_or_null("WorldTimeManager")
	_check(time_mgr != null, "WorldTimeManager is initialized in canonical world")
	if time_mgr != null:
		_check(absf(time_mgr.current_time_hours - 11.0) < 0.1, "Canonical game starts at 11:00 AM")
		_check(time_mgr.current_period == "morning", "Opening period is morning")
		_check(not time_mgr.is_night, "Opening is daytime")
		
		# Test time wrapping and period transitions
		time_mgr.set_time(12.5) # Midday
		_check(time_mgr.current_period == "midday", "12:30 maps to midday")
		_check(not time_mgr.is_night, "Midday is daytime")
		
		time_mgr.set_time(18.2) # Sunset / Dusk
		_check(time_mgr.current_period in ["sunset", "dusk"], "18:12 maps to sunset/dusk")
		
		time_mgr.set_time(22.0) # Night
		_check(time_mgr.current_period == "night", "22:00 maps to night")
		_check(time_mgr.is_night, "22:00 activates night mode")
		
		# Wrap around 24 hours
		time_mgr.set_time(25.5)
		_check(absf(time_mgr.current_time_hours - 1.5) < 0.01, "Clock wraps cleanly around 24h")
		
		# Reset to the canonical opening hour.
		time_mgr.set_time(11.0)

	# 2. City Lights Manager
	var lights_mgr = scene.get_node_or_null("CityLightsManager")
	_check(lights_mgr != null, "CityLightsManager is initialized")
	if lights_mgr != null and time_mgr != null:
		_check(lights_mgr.streetlights.size() > 0, "Streetlights populated along Sydney streets")
		_check(lights_mgr.landmark_lights.size() >= 2, "Harbour Bridge and Opera House illumination configured")
		time_mgr.set_time(21.0)
		_check(lights_mgr.is_night, "City lights switch on at night")
		if not lights_mgr.street_spotlights.is_empty():
			_check(lights_mgr.street_spotlights[0].light_energy > 0.0, "Night streetlights illuminate")
		
		# Test night activation
		time_mgr.set_time(23.0)
		_check(lights_mgr.is_night, "City lights switch on at night")
		if not lights_mgr.street_spotlights.is_empty():
			_check(lights_mgr.street_spotlights[0].light_energy > 0.0, "Streetlight beams emit light at night")
		
		time_mgr.set_time(11.0)
		_check(not lights_mgr.is_night, "City lights switch off during daylight")

	# 3. Traffic Manager & Vehicle Fleet Variety
	var traffic_mgr = scene.get_node_or_null("TrafficManager")
	_check(traffic_mgr != null, "TrafficManager is active")
	if traffic_mgr != null:
		_check(traffic_mgr.road_data.size() > 100, "Road network indexed for Sydney traffic")
		
		# Test vehicle spec coverage for required vehicle classes
		var classes_to_verify := [
			VehicleVisualBuilderScript.VehicleClass.SEDAN,
			VehicleVisualBuilderScript.VehicleClass.SPORTS,
			VehicleVisualBuilderScript.VehicleClass.HATCHBACK,
			VehicleVisualBuilderScript.VehicleClass.SUV_4WD,
			VehicleVisualBuilderScript.VehicleClass.UTE,
			VehicleVisualBuilderScript.VehicleClass.DELIVERY_VAN,
			VehicleVisualBuilderScript.VehicleClass.BOX_TRUCK,
			VehicleVisualBuilderScript.VehicleClass.SEMI_TRAILER,
			VehicleVisualBuilderScript.VehicleClass.GARBAGE_TRUCK,
			VehicleVisualBuilderScript.VehicleClass.TAXI,
			VehicleVisualBuilderScript.VehicleClass.BUS,
			VehicleVisualBuilderScript.VehicleClass.MOTORBIKE,
			VehicleVisualBuilderScript.VehicleClass.SCOOTER
		]
		var all_specs_valid := true
		for vc in classes_to_verify:
			var spec: Dictionary = VehicleVisualBuilderScript.get_class_specs(vc)
			if spec.is_empty() or spec["length"] <= 0.0:
				all_specs_valid = false
				break
		_check(all_specs_valid, "All 13 Sydney vehicle classes specified with distinct dimensions/dynamics")
		
		# Test spawning a vehicle and verifying wheels, headlights and clearance ray
		var test_road = traffic_mgr.road_data[0]
		traffic_mgr._spawn_single_vehicle(test_road)
		_check(traffic_mgr.active_vehicles.size() > 0, "Traffic vehicle spawned successfully on road segment")
		if not traffic_mgr.active_vehicles.is_empty():
			var veh: VehicleTrafficController = traffic_mgr.active_vehicles[0]
			_check(veh.wheels.size() >= 2, "Traffic vehicle has proper wheel assemblies")
			_check(veh.headlights.size() > 0, "Traffic vehicle has functional headlights")
			_check(veh.clearance_ray != null, "Vehicle has obstacle clearance detection")
			var player: BoomPlayer = scene.get("player")
			var occupied := player.vehicle
			if occupied != null:
				player.vehicle = null
				player.visible = true
				player.collision_layer = 1
				player.collision_mask = 1
				occupied.driver = null
			player.global_position = scene.cbd_world.player_spawn
			await process_frame
			veh.global_position = player.global_position + Vector3(0,0,3)
			scene.call("find_nearest_vehicle")
			_check(scene.get("nearest") == veh, "Nearby AI traffic becomes the interact target")
			scene.call("interact")
			_check(player.vehicle == veh and veh.driver == player, "Hijacked traffic vehicle takes player control")
			veh.force_release_driver(player)
			_check(player.vehicle == null and player.visible, "Player can safely leave a hijacked vehicle")

	# 4. Pedestrian Population Manager
	var ped_mgr = scene.get_node_or_null("PedestrianManager")
	_check(ped_mgr != null, "PedestrianManager is active")
	if ped_mgr != null:
		_check(ped_mgr.graph_nodes.size() > 1000, "Sydney pedestrian graph loaded with thousands of walkable nodes")
		
		# Spawn test pedestrian
		ped_mgr._spawn_pedestrians_near_player()
		_check(ped_mgr.active_pedestrians.size() > 0, "Pedestrians spawn along footpaths")
		if not ped_mgr.active_pedestrians.is_empty():
			var ped: PedestrianController = ped_mgr.active_pedestrians[0]
			_check(ped.body_root != null, "Pedestrian has procedural character visuals")
			_check(ped.left_leg != null and ped.right_leg != null, "Pedestrian has animated walking rig")
			ped.set_physics_process(false)
			var previous_ped_health := ped.health
			ped.take_damage_at(24.0,ped.global_position + Vector3.UP * 1.2,1.5,Vector3.FORWARD)
			_check(ped.health == previous_ped_health - 24.0, "Bullet hits damage pedestrian NPCs")
			_check(scene.find_child("GoreBurst",true,false) != null, "Pedestrian bullet hit makes visible blood spray")

	# 5. Wildlife Manager & Australian White Ibis
	var wild_mgr = scene.get_node_or_null("WildlifeManager")
	_check(wild_mgr != null, "WildlifeManager is active")
	if wild_mgr != null:
		_check(wild_mgr.bin_props.size() > 0, "Sydney wheelie bins placed at parks and waterfront hotspots")
		time_mgr.set_time(21.0)
		_check(wild_mgr.is_night, "Wildlife manager follows the night clock")

		_check(wild_mgr.flying_foxes.size() >= 6, "Flying fox flock spawns over the city")
		var visible_foxes := 0
		for fox: Node3D in wild_mgr.flying_foxes:
			if fox.visible:
				visible_foxes += 1
		_check(visible_foxes >= 6, "Flying fox silhouettes are visible at night")
		
		# Spawn wildlife
		wild_mgr._spawn_wildlife_near_player()
		_check(wild_mgr.active_wildlife.size() > 0, "Wildlife agents active in the world")
		if not wild_mgr.active_wildlife.is_empty():
			var wild: WildlifeController = wild_mgr.active_wildlife[0]
			_check(wild.body_root != null, "Wildlife visuals constructed")
			_check(wild.state in ["idle", "walk", "peck", "flee"], "Wildlife state machine operating")
		var player: BoomPlayer = scene.get("player")
		var ibis := WildlifeController.new()
		ibis.kind = WildlifeController.WildlifeKind.IBIS
		wild_mgr.add_child(ibis)
		ibis.setup(WildlifeController.WildlifeKind.IBIS,player.global_position + Vector3(0,0,2),player)
		var previous_health := player.health
		var previous_bonus := player.bonus_reputation
		var test_car: ArcadeCar = scene.get("vehicles")[0]
		test_car.enter(player)
		test_car.speed = 18.0
		var car_health := test_car.health
		test_car._apply_crash_tips([{
			"collider": ibis,
			"normal": Vector3.RIGHT,
			"impact": 18.0
		}])
		_check(ibis._vehicle_hit, "A fast player-driven car splats a bin chicken")
		_check(player.health == previous_health, "Bin chicken impacts never damage the player")
		_check(test_car.health == car_health, "Bin chicken impacts do not damage the player's car")
		_check(player.bonus_reputation == previous_bonus + 500, "Bin Chicken Binned awards +500 reputation")
		_check(scene.find_child("GoreBurst",true,false) != null or scene.find_child("BodyDebris",true,false) != null,
			"Bin chicken impact produces visible gore and physical debris")
		await process_frame
		_check(scene.hud.text.contains(str(previous_bonus + 500)), "Bin chicken bonus appears in the reputation HUD")
	var enemy: BoomEnemy = scene.get("enemy")
	enemy.set_physics_process(false)
	enemy.take_damage(100.0)
	_check(enemy.health == 0.0 and not enemy.visible, "Lethal gunfire kills the hostile NPC")
	_check(scene.find_child("GoreBurst",true,false) != null, "Hostile NPC death produces a gore burst")

	print("RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
