extends SceneTree

var checks := 0
var failures := 0
var world: Node3D


func check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + description)
	else:
		failures += 1
		push_error("FAIL: " + description)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	# The exported JSON must load through the importer on its own.
	var loader := SydneyWorld.new()
	check(loader.load_world(), "Stage A export loads: " + loader.load_error)
	check(int(loader.stats.get("roads", 0)) > 500, "importer sees the road network")
	check(int(loader.stats.get("buildings", 0)) > 100, "importer sees buildings")
	check(loader.vehicle_spawns.size() >= 4, "importer provides four vehicle spawns")
	check(loader.player_spawn.distance_to(Vector3.ZERO) > 1.0, "player spawn is in the city, not the origin")

	root.add_child(loader)
	await process_frame
	check(loader.get_node_or_null("Roads") != null, "road mesh node created")
	check(loader.get_node_or_null("Footpaths") != null, "footpath mesh node created")
	check(loader.get_node_or_null("Buildings") != null, "building mesh node created")
	check(loader.get_node_or_null("BuildingCollision") != null, "building collision created")
	check(loader.get_node_or_null("GroundCollision") != null, "ground collision created")
	loader.queue_free()

	var missing := SydneyWorld.new()
	check(not missing.load_world("res://sydney/world/stage_a/does_not_exist.json"), "missing file fails safely")
	missing.free()

	# Full game adapter: requires SPLOOGE_SYDNEY=1 so district.gd takes the
	# Sydney path while keeping every gameplay script untouched.
	world = load("res://scenes/district.tscn").instantiate()
	root.add_child(world)
	for i in 45:
		await physics_frame
	check(world.using_sydney, "district uses the Sydney world when requested")
	check(world.sydney_world != null, "SydneyWorld is attached to the game")
	check(world.player != null and world.player.is_on_floor(), "player settles on Sydney ground")
	check(world.player.position.distance_to(world.player.spawn) < 2.0, "player starts at the Sydney spawn")
	check(world.vehicles.size() == 4, "four vehicles still spawn")
	check(world.enemy != null and world.enemy.visible, "enemy still spawns")
	check(world.hud.text.contains("HEALTH"), "existing HUD still updates")

	# Existing gameplay must still work on the Sydney geography, not just load.
	var start: Vector3 = world.player.position
	Input.action_press("forward")
	for i in 40:
		await physics_frame
	Input.action_release("forward")
	check(start.distance_to(world.player.position) > 1.0, "player walks on Sydney ground")

	world.enemy.set_physics_process(false)
	var spawn_yaw: float = world.sydney_world.player_yaw
	var forward := Vector3(-sin(spawn_yaw), 0.0, -cos(spawn_yaw))
	world.enemy.global_position = world.player.global_position + forward * 7.0 + Vector3(0, 0.2, 0)
	world.enemy.health = 100
	world.enemy.visible = true
	world.enemy.collision_layer = 1
	world.player.fire_time = 0.0
	world.player.ammo = 12
	world.rig.yaw = spawn_yaw
	world.rig.pitch = 0
	for i in 10:
		await physics_frame
	world.player.shoot()
	check(world.player.ammo == 11, "pistol still consumes ammunition in Sydney")
	check(world.enemy.health < 100, "pistol still damages an enemy in Sydney")

	var car: ArcadeCar = world.vehicles[0]
	car.position = world.player.spawn
	car.rotation.y = world.sydney_world.player_yaw
	car.speed = 0.0
	car.velocity = Vector3.ZERO
	world.player.position = car.position + Vector3(2.2, 0.1, 0)
	world.player.velocity = Vector3.ZERO
	for i in 10:
		await physics_frame
	world.interact()
	check(world.player.vehicle == car, "vehicle entry still works in Sydney")
	Input.action_press("forward")
	for i in 45:
		await physics_frame
	Input.action_release("forward")
	check(car.speed > 1.0, "vehicle accelerates in Sydney")

	print("RESULT: %d checks, %d failures" % [checks, failures])
	world.queue_free()
	await process_frame
	quit(1 if failures > 0 else 0)
