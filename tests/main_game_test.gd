extends SceneTree

var checks := 0
var failures := 0
var game: Variant


func check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + description)
	else:
		failures += 1
		push_error("FAIL: " + description)


func frames(count: int) -> void:
	for i in count:
		await physics_frame


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await frames(90)

	var player: BoomPlayer = game.player
	var camera: BoomCamera = game.rig
	var bridge: Variant = game.cbd_world.get_node_or_null("HarbourBridge")
	check(game.using_sydney, "canonical main scene loads Sydney instead of District Zero")
	check(game.cbd_world.loaded_path.ends_with("stage_b/world.json"), "expanded CBD export is the integrated world source")
	check(bridge != null, "Harbour Bridge is present in the canonical world")
	check(game.cbd_world.has_node("OperaHouse"), "Opera House is present in the canonical world")
	check(game.cbd_world.has_node("HarbourWater"), "Phase 6A harbour water is present in the canonical world")
	var city_landmarks: Node = game.cbd_world.get_node_or_null("SydneyCBDLandmarks")
	check(city_landmarks != null, "authored CBD landmark details are integrated into the main world")
	# Town Hall, Hyde Park, Circular Quay and Darling Harbour live under the
	# civic group since the civic split; QVB/St Mary's/Central/Sydney Tower
	# are direct children of the landmark root.
	for landmark_name in [
		"QueenVictoriaBuilding", "StMarysCathedral",
		"CentralStationLandmark", "SydneyTowerLandmark",
	]:
		check(city_landmarks.has_node(landmark_name), landmark_name + " landmark treatment is present")
	var civic_landmarks: Node = game.cbd_world.get_node_or_null("SydneyCBDLandmarks/SydneyCivicLandmarks")
	check(civic_landmarks != null, "civic landmark group is integrated")
	for landmark_name in ["SydneyTownHall", "HydeParkLandmarks", "CircularQuayLandmarks", "DarlingHarbourLandmarks"]:
		if civic_landmarks != null:
			check(civic_landmarks.has_node(landmark_name), landmark_name + " landmark treatment is present")
	# The landmark root batches by material per parent; the civic detail layer
	# alone contributes ~2.9k batched meshes. Budget documented 2026-11-29
	# (renderMeshNodes 347 + civicDetailMeshes 2918); tighten after the
	# perf audit's draw-call pass, not by assertion guesswork.
	check(int(game.cbd_world.geometry_counts.CBDLandmarks.get("renderMeshNodes", 99999)) < 400,
		"authored landmark detail is batched into a bounded number of meshes")
	check(int(game.cbd_world.building_stats.get("operaHouseSiteOverlapsRemoved", 0)) == 6,
		"remaining generated Opera House podium overlaps are removed")
	check(int(game.cbd_world.building_stats.get("authoredLandmarkMasses", 0)) == 3,
		"QVB, Town Hall, and St Mary’s use bespoke OSM-footprint masses")
	var opera_shells := game.cbd_world.get_node("OperaHouse/OperaShells") as MeshInstance3D
	check(opera_shells.mesh.get_aabb().size.y > 60.0, "Opera House sails are enlarged for long-distance visibility")
	check(player.is_on_floor(), "bridge spawn settles on a walkable surface")
	check(player.position.distance_to(player.spawn) < 0.5, "player starts at the authored bridge spawn")
	check(player.global_position.y > 45.0, "player starts on the elevated Harbour Bridge deck")
	check(camera.weapon_mount.visible, "first-person pistol is visible on foot")
	check(is_zero_approx(camera.arm.spring_length), "on-foot camera starts in first person")
	var opera_direction := Vector3(658.72, 0.0, -1763.81) - player.global_position
	opera_direction.y = 0.0
	var view_forward := Vector3(-sin(camera.yaw), 0.0, -cos(camera.yaw))
	check(view_forward.normalized().dot(opera_direction.normalized()) > 0.98,
		"opening first-person view frames the Opera House")
	check(absf(camera.pitch) < 0.15, "opening camera uses a level landmark framing angle")
	check(game.vehicles[0].global_position.distance_to(bridge.route[3]) < 10.0, "first usable car is at the southern bridge road entrance")
	check(game.vehicles[1].vehicle_name.contains("SPORT")
		and game.vehicles[1].global_position.distance_to(player.global_position) < 5.0,
		"sports car is parked beside the Opera-facing bridge overlook")
	var view_pylon_clearance := INF
	for pylon: Array in bridge.reference.get("pylonCenters", []):
		var pylon_point := Vector3(float(pylon[0]), 0.0, float(pylon[1]))
		view_pylon_clearance = minf(view_pylon_clearance,
			Vector2(player.global_position.x - pylon_point.x,
				player.global_position.z - pylon_point.z).length())
	check(view_pylon_clearance > 20.0, "bridge spawn no longer sits beside an obstructing pylon")

	# Prove a camera-aimed shot reaches a real enemy collider on the walkway.
	var enemy: BoomEnemy = game.enemy
	enemy.set_physics_process(false)
	var route_forward: Vector3 = bridge.route[78] - bridge.route[76]
	route_forward.y = 0.0
	camera.yaw = atan2(-route_forward.x, -route_forward.z)
	camera.pitch = 0.0
	await frames(2)
	var shot_origin: Vector3 = camera.camera.global_position
	var shot_forward: Vector3 = -camera.camera.global_basis.z
	enemy.global_position = shot_origin + shot_forward * 2.2 - Vector3.UP * 0.85
	enemy.health = 100.0
	await frames(2)
	var target_query := PhysicsRayQueryParameters3D.create(
		shot_origin, shot_origin + shot_forward * 150.0, 1, [player.get_rid()]
	)
	var target_hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(target_query)
	check(not target_hit.is_empty() and target_hit.get("collider") == enemy,
		"first-person aim ray reaches the target")
	player.fire_time = 0.0
	player.shoot()
	check(player.ammo == 11, "first-person fire consumes one round")
	check(enemy.health < 100.0, "first-person hitscan damages a target")
	check(camera.muzzle_flash.visible, "shot shows a muzzle flash")

	# Enter the nearby sports car from the actual overlook spawn.
	var car: ArcadeCar = game.vehicles[1]
	check(player.global_position.distance_to(car.global_position) < 4.0,
		"player can reach the sports car from the bridge spawn")
	game.interact()
	check(player.vehicle == car and car.driver == player, "interaction enters the bridge sports car")
	await frames(35)
	check(not camera.weapon_mount.visible and camera.arm.spring_length > 5.0, "driving switches to third-person chase camera")
	var before := car.global_position
	Input.action_press("forward")
	await frames(45)
	Input.action_release("forward")
	check(car.global_position.distance_to(before) > 2.0, "possessed car responds to forward input")
	var wheels_grounded := true
	for wheel: MeshInstance3D in car.wheels:
		wheels_grounded = wheels_grounded and absf(wheel.position.y - 0.46) < 0.01
	check(wheels_grounded, "front and rear wheels keep fixed ride height under throttle")
	Input.action_press("jump")
	await frames(45)
	Input.action_release("jump")
	check(car.exit_vehicle(), "vehicle exits at a safe, clear position")
	await frames(65)
	check(player.vehicle == null and player.visible, "on-foot player state is restored after exit")
	check(camera.weapon_mount.visible and camera.arm.spring_length < 0.1, "exit restores first-person camera and weapon")

	print("RESULT: %d checks, %d failures" % [checks, failures])
	game.queue_free()
	await process_frame
	quit(1 if failures > 0 else 0)
