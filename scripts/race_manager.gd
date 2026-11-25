class_name RaceManager
extends Node

## Point-to-point AI street race against the player. Builds a route by
## chaining real road centrelines (the same `road_data` TrafficManager drives
## AI traffic on) starting from the player's current road, spawns a rival
## sports car driven by RaceAIDriver, and reports progress/finish through the
## district's HUD `message` string.

const AIDriverScript := preload("res://scripts/race_ai_driver.gd")
const RIVAL_SCENE := preload("res://scenes/vehicles/viper.tscn")
const ROUTE_TARGET_LENGTH := 900.0
const FINISH_RADIUS := 12.0
const CHAIN_TOLERANCE := 18.0
const MAX_CHAIN_LINKS := 40

var world: Node3D
var active: bool = false
var rival: ArcadeCar
var rival_driver: RaceAIDriver
var route: Array[Vector3] = []
var countdown: float = 0.0


func _ready() -> void:
	world = get_parent()


## Called from district.gd on the "start_race" key. Toggles off if a race is
## already running, so the same key cancels.
func try_start_race(player: Node) -> void:
	if active:
		_end_race("RACE ABORTED")
		return
	var car: ArcadeCar = player.get("vehicle")
	if car == null:
		world.message = "Get in a car to start a race (Y)"
		return
	var traffic := get_tree().get_first_node_in_group("traffic_managers")
	if traffic == null or not ("road_data" in traffic) or traffic.road_data.is_empty():
		world.message = "No road data available for a race here"
		return
	route = _build_route(car.global_position, traffic.road_data)
	if route.size() < 2:
		world.message = "Couldn't find a clear stretch of road to race on"
		return
	_spawn_rival()
	active = true
	countdown = 3.0
	world.message = "GET READY · 3"


func _physics_process(dt: float) -> void:
	if not active:
		return
	if rival == null or not is_instance_valid(rival) or rival_driver == null:
		_end_race("Race cancelled")
		return
	if countdown > 0.0:
		countdown -= dt
		rival.ai_forward = 0.0
		rival.ai_turn = 0.0
		world.message = "GET READY · %d" % maxi(int(ceil(countdown)), 1)
		return

	var player: Node = world.get("player")
	var player_car: ArcadeCar = player.get("vehicle") if player != null else null
	if player_car == null:
		_end_race("You left the car · race abandoned")
		return
	var finish: Vector3 = route[route.size() - 1]
	if player_car.global_position.distance_to(finish) < FINISH_RADIUS:
		_end_race("YOU WIN THE RACE!")
		return
	if rival_driver.finished:
		_end_race("%s WINS THE RACE" % str(rival.vehicle_name))
		return
	world.message = "RACE · you %d%%  ·  %s %d%%" % [
		int(_player_progress(player_car) * 100.0),
		str(rival.vehicle_name),
		int(rival_driver.progress() * 100.0),
	]


func _player_progress(player_car: ArcadeCar) -> float:
	if route.size() < 2:
		return 0.0
	var best_i := 0
	var best_d := INF
	for i in route.size():
		var d: float = player_car.global_position.distance_squared_to(route[i])
		if d < best_d:
			best_d = d
			best_i = i
	return float(best_i) / float(route.size() - 1)


func _spawn_rival() -> void:
	rival = RIVAL_SCENE.instantiate()
	rival.vehicle_name = "RIVAL"
	rival.paint = Color("1f6fd1")
	world.add_child(rival)
	rival.global_position = route[0] + Vector3.UP * 0.3
	var dir := route[1] - route[0]
	dir.y = 0.0
	if dir.length() > 0.01:
		dir = dir.normalized()
		rival.rotation.y = atan2(-dir.x, -dir.z)
	rival_driver = AIDriverScript.new()
	rival.add_child(rival_driver)
	rival_driver.setup(rival, route)


func _end_race(text: String) -> void:
	active = false
	world.message = text
	if rival != null and is_instance_valid(rival):
		rival.queue_free()
	rival = null
	rival_driver = null
	route.clear()


## Chains road centrelines end-to-end starting at the point nearest `start_pos`,
## continuing onto whichever unused road's endpoint meets the current tail
## within CHAIN_TOLERANCE, until the route covers roughly ROUTE_TARGET_LENGTH
## metres (or no connecting road is found). Reusing surveyed centrelines keeps
## the race on drivable streets instead of projecting blindly into buildings.
func _build_route(start_pos: Vector3, road_data: Array) -> Array[Vector3]:
	var result: Array[Vector3] = []
	if road_data.is_empty():
		return result
	var used: Dictionary = {}
	var best_idx := -1
	var best_point_i := 0
	var best_d := INF
	for idx in road_data.size():
		var pts: Array = road_data[idx].get("points", [])
		for i in pts.size():
			var d: float = start_pos.distance_squared_to(pts[i])
			if d < best_d:
				best_d = d
				best_idx = idx
				best_point_i = i
	if best_idx < 0:
		return result
	used[best_idx] = true
	var pts: Array = road_data[best_idx]["points"]
	for i in range(best_point_i, pts.size()):
		result.append(pts[i])

	var length := 0.0
	var links := 0
	while length < ROUTE_TARGET_LENGTH and links < MAX_CHAIN_LINKS and result.size() >= 2:
		links += 1
		var tail: Vector3 = result[result.size() - 1]
		var next_idx := -1
		var next_forward := true
		var next_d := CHAIN_TOLERANCE
		for idx in road_data.size():
			if used.has(idx):
				continue
			var rpts: Array = road_data[idx].get("points", [])
			if rpts.size() < 2:
				continue
			var d0: float = tail.distance_to(rpts[0])
			var d1: float = tail.distance_to(rpts[rpts.size() - 1])
			if d0 < next_d:
				next_d = d0
				next_idx = idx
				next_forward = true
			if d1 < next_d:
				next_d = d1
				next_idx = idx
				next_forward = false
		if next_idx < 0:
			break
		used[next_idx] = true
		var rpts: Array = road_data[next_idx]["points"]
		var ordered: Array = rpts.duplicate()
		if not next_forward:
			ordered.reverse()
		for p in ordered:
			result.append(p)
		length = 0.0
		for i in range(1, result.size()):
			length += float(result[i - 1].distance_to(result[i]))
	return result
