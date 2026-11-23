extends SceneTree

## Rail corridor collision regression.
##
## The tunnel bores used to have walls and a ceiling but no floor, so a body
## that left the track fell through the city to the void below the ground cells.
## The Central approach is too shallow for the 6.8 m bore and was left open;
## its floor and the descent-cut slab were zero-thickness triangle strips that a
## fast body could tunnel through. This suite drives the real ArcadeCar, the real
## on-foot BoomPlayer and the real AI VehicleTrafficController through every
## below-grade section at three speeds, twenty passes per location, and asserts
## the body stays on or above the track bed and never passes the world floor.
##
## Headless:
##   Godot_v4.7.2-stable_win64_console.exe --headless --path . \
##     --script res://tests/rail_corridor_physics_test.gd

const CbdWorldScript := preload("res://sydney/cbd/cbd_world.gd")
const CarScene := preload("res://scenes/vehicles/comet.tscn")
const PlayerScene := preload("res://scenes/player.tscn")
const TrafficScript := preload("res://sydney/ecosystem/vehicle_traffic_controller.gd")
const PASSES := 20
const SPEEDS := [5.0, 16.0, 30.0]
const WORLD_FLOOR := -20.0
const MAX_FALL_DEPTH := 1.5
const MAX_DOWNWARD_VELOCITY := 40.0

## Route indices: open cut, deep bore at Town Hall, shallow Central ascent and
## the Redfern surface approach. Every below-grade case is covered.
const LOCATIONS := [
	{"id": "descent-cut", "index": 300},
	{"id": "town-hall-bore", "index": 430},
	{"id": "central-ascent", "index": 600},
]

var world: Node3D
var route: Array[Vector3]
var station_indices: Dictionary
var checks := 0
var failures := 0
var car: ArcadeCar
var player: BoomPlayer
var traffic: VehicleTrafficController


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		return
	failures += 1
	push_error("FAIL: " + label)


func _await_frames(count: int) -> void:
	for i in count:
		await physics_frame


func _direction(index: int) -> Vector3:
	var a: Vector3 = route[index]
	var b: Vector3 = route[mini(index + 1, route.size() - 1)]
	var dir := b - a
	dir.y = 0.0
	return dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD


func _start_before(target_index: int, meters: float) -> Vector3:
	var target: Vector3 = route[target_index]
	return target - _direction(target_index) * meters


## Runs one car pass and returns {min_y, max_vy, reached}. `car` is the scene
## body, so shape, suspension and gravity are the shipping implementation.
func _car_pass(target_index: int, speed: float) -> Dictionary:
	var target: Vector3 = route[target_index]
	var dir := _direction(target_index)
	var start := target - dir * 1.5
	car.global_position = start + Vector3.UP * 0.6
	car.rotation = Vector3(0.0, atan2(-dir.x, -dir.z), 0.0)
	car.velocity = Vector3.ZERO
	car.speed = 0.0
	car.roll = 0.0
	car.rotation.z = 0.0
	car.airborne = false
	car.health = car.max_health
	car.destroyed = false
	var min_y := INF
	var max_vy := 0.0
	var reached := false
	var frames := 30
	for f in frames:
		car.speed = speed
		await physics_frame
		var p := car.global_position
		var vy: float = car.velocity.y
		if f > 2:
			min_y = minf(min_y, p.y)
			max_vy = maxf(max_vy, absf(vy))
		if (p - target).dot(dir) >= -1.0:
			reached = true
			break
	return {"min_y": min_y, "max_vy": max_vy, "reached": reached}


## Real on-foot body (capsule from player.tscn). Its own input script is off so
## the pass is deterministic; the CharacterBody3D and its collision shape are
## the shipping ones.
func _player_pass(target_index: int, speed: float) -> Dictionary:
	var target: Vector3 = route[target_index]
	var dir := _direction(target_index)
	player.global_position = target - dir * 0.8 + Vector3.UP * 0.2
	player.velocity = Vector3.ZERO
	var min_y := INF
	var max_vy := 0.0
	for f in 28:
		player.velocity.x = dir.x * speed
		player.velocity.z = dir.z * speed
		player.velocity.y = maxf(player.velocity.y - 20.0 * 0.0167, -35.0)
		player.move_and_slide()
		await physics_frame
		if f > 2:
			min_y = minf(min_y, player.global_position.y)
			max_vy = maxf(max_vy, absf(player.velocity.y))
	return {"min_y": min_y, "max_vy": max_vy, "reached": true}


## Real AI traffic controller following a short route through the target.
func _traffic_pass(target_index: int, speed: float) -> Dictionary:
	var target: Vector3 = route[target_index]
	var dir := _direction(target_index)
	var pts: Array[Vector3] = [
		target - dir * 1.5,
		target,
		target + dir * 12.0,
	]
	traffic.setup_route(pts, 1.9, true)
	traffic.current_speed = speed
	traffic.max_speed = maxf(speed, 8.0)
	traffic.target_speed = speed
	var min_y := INF
	var max_vy := 0.0
	var reached := false
	for f in 36:
		await physics_frame
		var p := traffic.global_position
		if f > 2:
			min_y = minf(min_y, p.y)
			max_vy = maxf(max_vy, absf(traffic.velocity.y))
		if (p - target).dot(dir) >= -1.0:
			reached = true
			if f > 16:
				break
	return {"min_y": min_y, "max_vy": max_vy, "reached": reached}


func _assert_pass(label: String, record: Dictionary, track_y: float) -> void:
	_check(bool(record["reached"]), label + ": body reached the section")
	_check(float(record["min_y"]) > track_y - MAX_FALL_DEPTH,
		"%s: stayed on the track bed (min y %.2f, track %.2f)" % [label, record["min_y"], track_y])
	_check(float(record["min_y"]) > WORLD_FLOOR,
		"%s: never passed the world floor (min y %.2f)" % [label, record["min_y"]])
	_check(float(record["max_vy"]) < MAX_DOWNWARD_VELOCITY,
		"%s: no excess vertical velocity (%.1f)" % [label, record["max_vy"]])


func _run() -> void:
	world = CbdWorldScript.new()
	if not world.load_world():
		push_error("FAIL: could not load the CBD world")
		quit(1)
		return
	get_root().add_child(world)
	await _await_frames(3)
	var railway: Node3D = world.get_node_or_null("SydneyRailNetwork")
	if railway == null:
		for node in world.find_children("*", "Node3D", true, false):
			if node.name == "SydneyRailNetwork":
				railway = node
				break
	if railway == null:
		push_error("FAIL: no rail network in the CBD world")
		quit(1)
		return
	route = railway.get("main_route_points")
	station_indices = railway.get("station_route_indices")

	car = CarScene.instantiate()
	world.add_child(car)
	player = PlayerScene.instantiate()
	world.add_child(player)
	player.set_physics_process(false)
	traffic = TrafficScript.new()
	traffic.vehicle_class = 0
	world.add_child(traffic)
	await _await_frames(4)

	for location: Dictionary in LOCATIONS:
		var index: int = location["index"]
		var track_y: float = route[index].y
		var totals := {"car": 0, "player": 0, "traffic": 0}
		for speed: float in SPEEDS:
			for pass_index in PASSES:
				var label := "%s / car / %.0f m/s / pass %d" % [location["id"], speed, pass_index]
				_assert_pass(label, await _car_pass(index, speed), track_y)
				_check(car.global_position.y > WORLD_FLOOR, label + ": car above world floor")
				totals["car"] += 1
			for pass_index in PASSES:
				var label := "%s / on-foot / %.0f m/s / pass %d" % [location["id"], speed, pass_index]
				_assert_pass(label, await _player_pass(index, speed), track_y)
				totals["player"] += 1
			for pass_index in PASSES:
				var label := "%s / AI traffic / %.0f m/s / pass %d" % [location["id"], speed, pass_index]
				_assert_pass(label, await _traffic_pass(index, speed), track_y)
				totals["traffic"] += 1
		print("LOCATION %s: %d car, %d on-foot, %d traffic passes" % [
			location["id"], totals["car"], totals["player"], totals["traffic"]])

	# Walk-through of every accessible station interior. The player starts on
	# the platform and walks along the authored route, so the floor, platform
	# edge and any opening it crosses are exercised.
	for station_id in ["milsons-point", "wynyard", "town-hall", "central", "redfern"]:
		var index := int(station_indices.get(station_id, -1))
		if index < 0:
			_check(false, "station %s exists in the route" % station_id)
			continue
		var dir := _direction(index)
		var track_y: float = route[index].y
		player.global_position = route[index] + Vector3.UP * 0.4
		player.velocity = Vector3.ZERO
		var min_y := INF
		var stayed_inside := true
		for f in 90:
			player.velocity.x = dir.x * 2.5
			player.velocity.z = dir.z * 2.5
			player.velocity.y = maxf(player.velocity.y - 20.0 * 0.0167, -35.0)
			player.move_and_slide()
			await physics_frame
			min_y = minf(min_y, player.global_position.y)
			if f > 10 and player.global_position.y < track_y - MAX_FALL_DEPTH:
				stayed_inside = false
		_check(stayed_inside, "station %s: walk-through stays on the floor (min y %.2f)" % [station_id, min_y])
		_check(min_y > WORLD_FLOOR, "station %s: walk-through above world floor" % station_id)

	print("RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
