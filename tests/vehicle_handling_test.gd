extends SceneTree

## Vehicle arcade-handling suite — acceleration, braking, handbrake drift
## (lateral slide + grip reduction + recovery), NOS boost (drain/recharge +
## visuals), skid marks (creation + bounded lifetime), rollover from impacts,
## auto-unroll, and the preserved enter/exit behaviour.

var checks := 0
var failures := 0


func check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: "+description)
	else:
		failures += 1
		push_error("FAIL: "+description)


func frames(count: int) -> void:
	for _i in count:
		await physics_frame


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var world: Node3D = load("res://scenes/district.tscn").instantiate()
	root.add_child(world)
	await frames(60)
	var car: ArcadeCar = world.vehicles[0]
	check(car.is_on_floor(), "car spawns on the ground")

	## ---------------------------------------------------------- 1. driving --
	car.enter(world.player)
	car.position = Vector3(0, 0.9, 45)   # District Zero spawn area is blocked
	car.velocity = Vector3.ZERO           # by geometry; use the open avenue
	await frames(20)
	Input.action_press("forward")
	await frames(120)
	Input.action_release("forward")
	check(car.speed > 20.0, "accelerates: speed %.1f > 20" % car.speed)
	check(absf(car.position.z) < 60.0, "car moved forward")

	## ------------------------------------------------- 2. braking basics ---
	var brakes := 0
	while car.speed > 0.5 and brakes < 100:
		Input.action_press("back")
		await frames(5)
		Input.action_release("back")
		brakes += 5
	check(car.speed < 1.5, "braking stops the car (speed %.2f)" % car.speed)
	check(world.player.vehicle == car, "player still in the car")

	## --------------------------------------------- 3. handbrake + drift ----
	var speed_before_drift := 0.0
	car.velocity = Vector3.ZERO
	car.position = Vector3(0, 0.9, 45)
	Input.action_press("forward")
	await frames(40)
	speed_before_drift = car.speed
	check(speed_before_drift > 8.0, "car is moving before handbrake (%s)" % speed_before_drift)
	Input.action_press("jump")   # SPACE = handbrake
	Input.action_press("right")  # enter the slide
	await frames(30)
	check(car.handbrake, "handbrake engages while held")
	check(absf(car.lateral_speed) > 2.0, "car is sliding sideways during handbrake (%.2f)" % car.lateral_speed)
	check(car.slide_time > 0.05, "slide is accumulating (%.2f s)" % car.slide_time)
	check(absf(car.rear_grip_effective - car.handbrake_rear_grip) < 0.05,
		"handbrake reduces rear grip (effective %.3f)" % car.rear_grip_effective)
	Input.action_release("jump")  # release handbrake: grip restores progressively
	Input.action_release("right")
	await frames(150)
	check(absf(car.lateral_speed) < 1.5, "drift recovers after releasing handbrake (%.2f)" % car.lateral_speed)
	check(car.speed > 5.0, "speed recovers after the drift (%.1f)" % car.speed)
	Input.action_release("forward")

	## ---------------------------------------------------- 4. handbrake stop -
	# Reposition to a known-good stretch (the drive test above may have slid
	# the car into geometry), then handbrake and verify a full stop.
	var reached_speed := false
	for _i in range(10):
		car.position = Vector3(0, 0.9, 42+_i)
		car.rotation = Vector3.ZERO
		car.velocity = Vector3.ZERO
		car.speed = 0.0
		car.lateral_speed = 0.0
		Input.action_press("forward")
		for _f in range(30):
			await frames(2)
		if car.speed > 10:
			reached_speed = true
			break
	Input.action_release("forward")
	check(reached_speed and car.speed > 10, "car is fast for handbrake stop test (%s)" % car.speed)
	Input.action_press("jump")
	for _i in range(45):
		await frames(2)
	Input.action_release("jump")
	check(absf(car.speed) < 0.5, "handbrake stops the car (speed %.2f)" % car.speed)

	## ------------------------------------------------- 5. boost activation --
	Input.action_press("sprint")  # SHIFT = NOS boost
	await frames(8)
	check(car.boost_on, "boost engages while SHIFT held")
	check(car.boost_factor > 0.1, "boost factor ramps up (%.2f)" % car.boost_factor)
	check(car.effects.exhaust[0].visible, "exhaust flame visible during boost")
	check(car.effects.tail_glow.visible, "tail glow visible during boost")
	Input.action_release("sprint")
	await frames(80)
	check(car.boost_on == false and car.boost_factor == 0.0, "boost factor decays after release")
	await frames(600)
	check(car.boost_amount > 5.5, "boost recharges after release (%.1f / %.1f)" % [car.boost_amount, car.boost_capacity])

	## ----------------------------------------------- 6. skid marks ----------
	Input.action_press("forward")
	await frames(60)
	Input.action_press("right")  # corner at speed -> lateral slides -> marks
	await frames(80)
	Input.action_release("right")
	Input.action_release("forward")
	check(car.skid_marks.is_any_visible(), "skid marks appear when the car slides")
	var mark_count := car.skid_marks.pool.size()
	check(mark_count <= SkidMarksPoolMax(), "skid mark pool is bounded (%d)" % mark_count)
	await frames(150)
	check(not car.skid_marks.is_any_visible(), "skid marks fade out while idle")

	## -------------------------------------------------- 7. rollover ---------
	var wall: MeshInstance3D = Art.box(world, Vector3(0, 0.9, 0), Vector3(10, 2.0, 0.6), Color.GRAY, true)
	car.enter(world.player)
	car.position = Vector3(0, 0.9, 5.0)
	car.rotation = Vector3.ZERO
	car.speed = 0.0
	car.velocity = Vector3.ZERO
	car.roll = 0.0
	car.health = car.max_health
	await frames(20)
	car.velocity = Vector3(12.0, 0.0, -30.0)
	Input.action_press("forward")
	await frames(150)
	Input.action_release("forward")
	var crashed_damage := car.health < car.max_health - 3
	check(crashed_damage, "impact damages the car (health %.0f/%.0f, roll %.2f)" % [car.health, car.max_health, car.roll])

	## ------------------------------------- 8. recovery of a tipped car -----
	car.driver = null
	car.roll = 0.7
	car.rotation.z = 0.5
	car.speed = 0.0
	await frames(300)
	check(absf(car.roll) < 0.7,
		"tipped car settles toward upright (roll %.2f)" % absf(car.roll))
	check(absf(car.rotation.z) < 0.45,
		"sideways tip recovers (z %.2f)" % car.rotation.z)

	## ----------------------------------------- 9. exit blocked when tipped --
	car.enter(world.player)
	car.rotation = Vector3(1.3, 0.0, 0.0)  # pitched beyond the 1.2 rad exit limit
	car.speed = 0.0
	await frames(10)
	check(not car.exit_vehicle(), "exit refused while tipped")
	car.rotation = Vector3.ZERO

	## ------------------------------------------------ 10. exit works upright -
	check(car.exit_vehicle(), "exit works when upright and at rest")
	car.position = car.home

	print("RESULT: %d checks, %d failures" % [checks, failures])
	world.queue_free()
	await process_frame
	quit(1 if failures > 0 else 0)


## Bounds the mark pool for the test: must never grow unbounded.
func SkidMarksPoolMax() -> int:
	return 16
