class_name RaceAIDriver
extends Node

## Drives an ArcadeCar along a fixed route of waypoints for AI street races.
## Writes to the car's ai_forward/ai_turn/ai_handbrake/ai_boost fields each
## physics frame instead of touching global Input, so the race rival uses the
## exact same drivetrain/physics as the player.

const REACH_RADIUS := 9.0
const TURN_GAIN := 1.6

var car: ArcadeCar
var route: Array[Vector3] = []
var waypoint_index: int = 0
var finished: bool = false


func setup(target_car: ArcadeCar, race_route: Array[Vector3]) -> void:
	car = target_car
	route = race_route
	waypoint_index = 0
	finished = false
	car.ai_controlled = true


func _physics_process(_dt: float) -> void:
	if car == null or not is_instance_valid(car) or route.size() < 2:
		return
	if car.destroyed or car.health <= 0:
		car.ai_forward = 0.0
		car.ai_turn = 0.0
		car.ai_handbrake = false
		car.ai_boost = false
		return
	if finished:
		car.ai_forward = 0.0
		car.ai_turn = 0.0
		car.ai_handbrake = true
		car.ai_boost = false
		return

	var target: Vector3 = route[waypoint_index]
	var to_target := target - car.global_position
	to_target.y = 0.0
	if to_target.length() < REACH_RADIUS:
		waypoint_index += 1
		if waypoint_index >= route.size():
			finished = true
			return
		target = route[waypoint_index]
		to_target = target - car.global_position
		to_target.y = 0.0

	# Same forward() convention as ArcadeCar._forward()/CbdRailNetwork's route
	# yaw: forward(y) = (-sin(y), 0, -cos(y)).
	var desired_yaw := atan2(-to_target.x, -to_target.z)
	var angle_diff := wrapf(desired_yaw - car.rotation.y, -PI, PI)
	car.ai_turn = clampf(-angle_diff * TURN_GAIN, -1.0, 1.0)
	car.ai_forward = clampf(1.0 - absf(angle_diff) * 0.55, 0.25, 1.0)
	car.ai_handbrake = absf(angle_diff) > 1.1 and absf(car.speed) > 10.0
	car.ai_boost = absf(angle_diff) < 0.3 and car.boost_amount > car.boost_capacity * 0.3


func progress() -> float:
	if route.size() < 2:
		return 0.0
	return float(waypoint_index) / float(route.size() - 1)
