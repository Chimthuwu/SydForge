extends SceneTree

var world: Node3D
var failures: int = 0
var checks: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: "+description)
	else:
		failures += 1
		push_error("FAIL: "+description)

func frames(count: int) -> void:
	for i in count:
		await physics_frame

func run() -> void:
	world = load("res://scenes/district.tscn").instantiate()
	root.add_child(world)
	await frames(40)
	var p: BoomPlayer = world.player
	var foe: BoomEnemy = world.enemy
	foe.set_physics_process(false)
	check(world.vehicles.size() == 4,"four vehicle scenes instantiated")
	check(p.is_on_floor(),"player settles on collision floor")
	var start := p.position
	Input.action_press("forward")
	await frames(60)
	Input.action_release("forward")
	var walk_distance := start.distance_to(p.position)
	check(walk_distance > 4.5,"W input moves player forward")
	await frames(20)
	start = p.position
	Input.action_press("forward")
	Input.action_press("sprint")
	await frames(60)
	Input.action_release("forward")
	Input.action_release("sprint")
	check(start.distance_to(p.position) > walk_distance+2,"sprint is faster than walking")
	await frames(20)
	var ground_y := p.position.y
	Input.action_press("jump")
	await frames(2)
	Input.action_release("jump")
	await frames(14)
	check(p.position.y > ground_y+0.6,"jump gains height")
	await frames(65)
	check(p.is_on_floor(),"jump lands")
	# Test mouse handler with the same event type delivered by the viewport.
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(80,20)
	var old_yaw: float = world.rig.yaw
	world.rig.apply_look(motion.relative)
	check(world.rig.yaw != old_yaw,"orbit calculation changes yaw (event capture tested separately)")
	world.rig.apply_look(Vector2(0,10000))
	check(is_equal_approx(world.rig.pitch,-1.05),"camera pitch is clamped")
	check(world.rig.arm.shape is SphereShape3D,"camera uses sphere obstruction sweep")
	world.rig.yaw = 0
	world.rig.pitch = -0.18
	for car: ArcadeCar in world.vehicles:
		car.position = Vector3(0,0.1,45)
		car.rotation = Vector3.ZERO
		car.speed = 0
		car.velocity = Vector3.ZERO
		p.position = Vector3(2.5,0.1,45)
		await frames(5)
		world.interact()
		check(p.vehicle == car,"E interaction enters "+car.vehicle_name)
		check(p.vehicle == car and not p.visible and p.collision_layer == 0,"driver hidden and collision disabled")
		Input.action_press("forward")
		await frames(90)
		Input.action_release("forward")
		check(car.speed > 10 and car.position.z < 37,"accelerates and drives "+car.vehicle_name)
		check(absf(car.wheels[0].global_basis.y.dot(car.global_basis.x)) > 0.99,"wheel axle stays aligned while spinning")
		check(not car.exit_vehicle(),"moving exit refused")
		Input.action_press("right")
		Input.action_press("forward")
		await frames(15)
		Input.action_release("right")
		Input.action_release("forward")
		check(car.rotation.y < -0.1,"steering turns vehicle")
		Input.action_press("jump")
		await frames(90)
		Input.action_release("jump")
		check(absf(car.speed)<0.1,"handbrake stops vehicle")
		check(car.exit_vehicle(),"safe exit "+car.vehicle_name)
		check(p.visible and p.collision_layer == 1 and p.vehicle == null,"on-foot state restored")
		car.position = car.home
		car.rotation = Vector3.ZERO
		car.velocity = Vector3.ZERO
	# Pistol ray: park enemy in an open avenue in line with camera centre.
	p.position = Vector3(0,0.2,40)
	p.velocity = Vector3.ZERO
	# The production camera is now first person rather than offset to the right
	# of the character; keep this target centred on the reticle.
	foe.position = Vector3(0,0.2,25)
	foe.health = 100
	world.rig.yaw = 0
	world.rig.pitch = 0
	await frames(30)
	p.fire_time = 0
	p.shoot()
	check(p.ammo == 11,"pistol consumes one round")
	check(foe.health == 75,"pistol ray damages enemy")
	p.ammo = 0
	p.reload()
	await frames(90)
	check(p.ammo == 12 and p.reload_time <= 0,"reload refills magazine after delay")
	foe.position = p.position+Vector3(0,0,-1.5)
	p.melee()
	check(foe.health == 35,"melee damages nearby enemy")
	foe.take_damage(40)
	check(not foe.visible and p.kills == 1,"enemy defeat grants reputation")
	foe.respawn_time = 0.05
	foe.set_physics_process(true)
	await frames(10)
	check(foe.health == 100 and foe.visible,"enemy respawns")
	foe.position = p.position+Vector3(0,0,-8)
	p.invulnerable = 0
	foe.cooldown = 0
	await frames(10)
	check(p.health < 100,"enemy line-of-sight attack damages player")
	foe.set_physics_process(false)
	p.take_damage(200)
	check(p.health == 100 and p.position.distance_to(p.spawn)<0.1,"player death restores spawn and health")
	var car: ArcadeCar = world.vehicles[0]
	car.take_damage(25)
	check(car.health == car.max_health-25,"vehicle takes damage")
	car.enter(p)
	car.take_damage(999)
	check(car.health == 0 and car.driver == null and p.vehicle == null,"destroyed vehicle releases and respawns driver")
	car.repair_time = 0.05
	await frames(10)
	check(car.health == car.max_health and car.body_art.visible,"destroyed vehicle recovers")
	check(world.hud.text.contains("HEALTH"),"HUD updates live health")
	foe.position = Vector3(85,0.1,85)
	# Camera sweep must actually shorten against geometry.
	p.position = Vector3(0,0.1,45)
	p.velocity = Vector3.ZERO
	world.rig.yaw = 0
	world.rig.pitch = 0
	var wall := Art.box(world,Vector3(0,2,48),Vector3(8,4,0.5),Color.GRAY,true)
	await frames(45)
	check(world.rig.arm.get_hit_length() < 4.0,"camera obstruction retracts spring arm")
	wall.queue_free()
	await frames(5)
	# All exit candidates blocked: remain driving rather than clipping into geometry.
	car.position = Vector3(0,0.1,30)
	car.rotation = Vector3.ZERO
	car.speed = 0
	car.velocity = Vector3.ZERO
	car.enter(p)
	var barriers: Array[Node3D] = []
	for offset in [Vector3(2.2,1,0),Vector3(-2.2,1,0),Vector3(0,1,3.3)]:
		barriers.append(Art.box(world,car.position+offset,Vector3(1.4,2.5,1.4),Color.GRAY,true))
	await frames(5)
	check(not car.exit_vehicle() and p.vehicle == car,"blocked exits preserve occupied vehicle")
	for barrier in barriers:
		barrier.queue_free()
	await frames(5)
	check(car.exit_vehicle(),"exit succeeds when clearance restored")
	car.enter(p)
	Input.action_press("back")
	var before_z := car.position.z
	await frames(70)
	Input.action_release("back")
	check(car.speed < -5 and car.position.z > before_z+3,"reverse input drives backward")
	car.speed = 0
	car.velocity = Vector3.ZERO
	car.position = Vector3(0,0.1,30)
	wall = Art.box(world,Vector3(0,2,20),Vector3(8,4,0.5),Color.GRAY,true)
	var prior_health := car.health
	Input.action_press("forward")
	await frames(100)
	Input.action_release("forward")
	check(car.health < prior_health,"physical crash inflicts vehicle damage")
	car.speed = 0
	car.exit_vehicle()
	wall.queue_free()
	await frames(5)
	p.position = Vector3(0,0.1,45)
	p.velocity = Vector3.ZERO
	p.health = 100
	p.invulnerable = 0
	foe.position = Vector3(0,0.1,35)
	foe.velocity = Vector3.ZERO
	foe.cooldown = 0
	wall = Art.box(world,Vector3(0,2,40),Vector3(8,4,0.5),Color.GRAY,true)
	foe.set_physics_process(true)
	await frames(100)
	check(p.health == 100,"wall blocks enemy line-of-sight attacks")
	wall.queue_free()
	print("RESULT: %d checks, %d failures" % [checks,failures])
	world.queue_free()
	await process_frame
	quit(1 if failures > 0 else 0)
