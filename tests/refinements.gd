extends SceneTree

var failures: int = 0
var checks: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	checks += 1
	print("PASS: " if condition else "FAIL: ",label)
	if not condition:
		failures += 1

func frames(count: int) -> void:
	for i in count:
		await physics_frame

func run() -> void:
	var world: Node3D = load("res://scenes/district.tscn").instantiate()
	root.add_child(world)
	var p: BoomPlayer = world.player
	var foe: BoomEnemy = world.enemy
	foe.set_physics_process(false)
	foe.position = Vector3(85,0,85)
	p.position = Vector3(0,0.1,45)
	await frames(40)
	Input.action_press("aim")
	Input.action_press("forward")
	await frames(40)
	check(p.aiming and p.velocity.length() < 3.6,"aim limits movement speed")
	check(world.rig.camera.fov < 58 and world.rig.arm.spring_length < 3.5,"aim tightens camera smoothly")
	Input.action_release("forward")
	Input.action_release("aim")
	await frames(40)
	check(world.rig.camera.fov > 69,"releasing aim restores field of view")
	# Walk-off jump forgiveness, using real ground contact followed by leaving a ledge.
	var platform := Art.box(world,Vector3(0,1.3,45),Vector3(4,2.6,4),Color.GRAY,true)
	p.position = Vector3(0,2.7,45)
	p.velocity = Vector3.ZERO
	await frames(20)
	check(p.is_on_floor(),"ledge fixture provides ground contact")
	p.position.x = 3
	await frames(3)
	Input.action_press("jump")
	await frames(2)
	Input.action_release("jump")
	check(p.velocity.y > 6,"jump works shortly after leaving ledge")
	platform.queue_free()
	await frames(80)
	# Buffer a jump shortly before touching the floor.
	p.position = Vector3(0,0.18,45)
	p.velocity = Vector3(0,-4,0)
	p.coyote_time = 0
	await frames(1)
	Input.action_press("jump")
	await frames(2)
	Input.action_release("jump")
	await frames(4)
	check(p.velocity.y > 5,"buffered jump fires on landing")
	await frames(70)
	for car: ArcadeCar in world.vehicles:
		car.position = Vector3(0,0.1,35)
		car.rotation = Vector3.ZERO
		car.enter(p)
		car.speed = 18
		car.velocity = Vector3(0,0,-18)
		Input.action_press("forward")
		Input.action_press("jump")
		await frames(60)
		check(absf(car.speed)<0.1,"handbrake overrides accelerator: "+car.vehicle_name)
		Input.action_release("forward")
		Input.action_release("jump")
		car.exit_vehicle()
		car.position = car.home
		car.velocity = Vector3.ZERO
	var car: ArcadeCar = world.vehicles[0]
	car.position = Vector3(0,0.1,35)
	car.enter(p)
	car.set_physics_process(false)
	car.rotation.y = 1
	car.speed = 15
	world.rig.yaw = 0
	world.rig.manual_look_time = 0
	await frames(60)
	check(world.rig.yaw > 0.8,"driving camera recentres behind car")
	check(car.engine_audio.playing and car.engine_audio.pitch_scale > 1.3,"engine pitch responds to speed")
	world.rig.apply_look(Vector2(100,0))
	var manual_yaw: float = world.rig.yaw
	await frames(40)
	check(is_equal_approx(world.rig.yaw,manual_yaw),"manual camera input delays auto recenter")
	car.speed = 0
	car.exit_vehicle()
	p.position = Vector3(0,0.1,45)
	p.velocity = Vector3.ZERO
	p.model.rotation.y = 0
	foe.position = Vector3(0,0.1,43)
	foe.health = 100
	var wall := Art.box(world,Vector3(0,1,44),Vector3(3,2,0.2),Color.GRAY,true)
	await frames(5)
	p.melee_time = 0
	p.melee()
	check(foe.health == 100,"melee cannot hit through walls")
	wall.queue_free()
	await frames(5)
	foe.position = Vector3(0,0.1,47)
	p.melee_time = 0
	p.melee()
	check(foe.health == 100,"melee cannot hit behind player")
	foe.position = Vector3(0,0.1,43)
	await frames(2)
	p.melee_time = 0
	p.melee()
	check(foe.health == 60 and world.hit_time > 0,"frontal melee damages and confirms hit")
	print("REFINEMENTS: %d checks, %d failures" % [checks,failures])
	world.queue_free()
	await process_frame
	await process_frame
	quit(1 if failures > 0 else 0)
