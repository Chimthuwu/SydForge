class_name WantedSystem
extends Node

## GTA-style wanted level (0-5 stars), tuned to be a proportionate part of the
## open-world sandbox rather than a constant police simulator. Minor incidents
## draw local attention; serious crime escalates gradually with a sensible cap.

signal wanted_changed(stars: int)

const MAX_STARS := 5
const POLICE_SCENE := "res://scenes/vehicles/police.tscn"
## Per-star simultaneous pursuit cap (local response, not a city-wide swarm).
const UNITS_BY_STAR := [0, 1, 2, 3, 4, 4]
## Gradual escalation thresholds: one minor incident should not trigger absurd
## responses, while sustained serious crime still becomes challenging.
const STAR_THRESHOLDS := [0.0, 18.0, 38.0, 60.0, 82.0, 96.0]

var stars: int = 0
var heat: float = 0.0
var cooldown: float = 0.0
var player_ref: Node3D
var police: Array[Node3D] = []
var stats: Dictionary = {}

var _spawn_timer: float = 0.0
var _last_seen_time: float = 0.0


func setup(player: Node3D) -> void:
	player_ref = player
	_last_seen_time = 0.0


## Called when a foot officer is killed. Escalates heat and alerts nearby units.
func officer_killed(position: Vector3) -> void:
	add_crime(22.0, "OFFICER DOWN · police alerted")
	_alert_nearby_units(position)
	var incidents := get_tree().get_nodes_in_group("incident_managers")
	for mgr in incidents:
		if mgr.has_method("request_police_response"):
			mgr.call("request_police_response", position, 1.2)
			break


## Called when a police VEHICLE is destroyed. Heavier than a foot officer
## death: losing a unit brings a serious response (escalation plan scenario 3,
## heat +75 with immediate backup).
func police_car_destroyed(position: Vector3) -> void:
	add_crime(75.0, "POLICE UNIT DOWN · heavy response")
	_alert_nearby_units(position)
	var incidents := get_tree().get_nodes_in_group("incident_managers")
	for mgr in incidents:
		if mgr.has_method("request_police_response"):
			mgr.call("request_police_response", position, 2.0)
			break


func _alert_nearby_units(position: Vector3) -> void:
	for car in police:
		if is_instance_valid(car) and car.global_position.distance_to(position) < 240.0:
			if car.has_method("set_alert"):
				car.call("set_alert", position)


func add_crime(amount: float, reason: String = "") -> void:
	if amount <= 0.0:
		return
	heat = minf(heat + amount, 100.0)
	# Cooldown before heat can decay; longer at higher heat but not endless.
	cooldown = maxf(cooldown, 5.0 + float(stars) * 3.0)
	_update_stars()
	if player_ref != null and not reason.is_empty():
		var world: Variant = player_ref.get("world")
		if world != null and world is Object:
			world.set("message", reason)


func _update_stars() -> void:
	var next_stars := 0
	for i in range(MAX_STARS + 1):
		if heat >= STAR_THRESHOLDS[i]:
			next_stars = i
	if next_stars != stars:
		var increased := next_stars > stars
		stars = next_stars
		if increased and stars > 0:
			# Local response: schedule a unit, but do not instantly flood.
			_spawn_timer = minf(_spawn_timer, 2.5)
		elif stars <= 0:
			# Stand down: clear active pursuit so police presence does not linger.
			_cleanup_police_units()
			_spawn_timer = 0.0
		wanted_changed.emit(stars)


func _cleanup_police_units() -> void:
	for car: Node3D in police:
		if is_instance_valid(car):
			car.queue_free()
	police.clear()


func _process(dt: float) -> void:
	if player_ref == null or not is_instance_valid(player_ref):
		return
	police = police.filter(func(c: Node3D) -> bool: return is_instance_valid(c))
	_last_seen_time += dt
	if cooldown > 0.0:
		cooldown = maxf(0.0, cooldown - dt)
	_update_police_awareness(dt)
	_spawn_timer -= dt
	var wanted_units: int = UNITS_BY_STAR[clampi(stars, 0, MAX_STARS)]
	if stars > 0 and _spawn_timer <= 0.0 and police.size() < wanted_units:
		_spawn_police()
		# Backup arrives gradually; higher stars bring support sooner but capped.
		_spawn_timer = randf_range(10.0, 16.0) - float(stars) * 1.2
		_spawn_timer = maxf(_spawn_timer, 6.0)
	for car: Node3D in police:
		if car.has_method("set_pursuit_target"):
			car.call("set_pursuit_target", player_ref)


func _update_police_awareness(_dt: float) -> void:
	if stars <= 0:
		if heat > 0.0 and cooldown <= 0.0:
			heat = maxf(0.0, heat - 3.0 * _dt)
			_update_stars()
		return
	var nearest := INF
	var can_see := false
	var target_point := _player_target_point()
	for car: Node3D in police:
		if not is_instance_valid(car):
			continue
		var distance := car.global_position.distance_to(player_ref.global_position)
		nearest = minf(nearest, distance)
		if _has_line_of_sight(car, target_point, distance):
			can_see = true
	if can_see and nearest <= 130.0:
		_last_seen_time = 0.0
		# Maintain pressure while clearly observed, but do not auto-escalate heat.
		cooldown = maxf(cooldown, 2.0)
	else:
		# Escapable: break contact and heat/stars decay over time.
		if cooldown <= 0.0:
			var decay := 2.2
			if nearest > 140.0:
				decay = 4.5
			if _last_seen_time > 12.0:
				decay += 2.0
			heat = maxf(0.0, heat - decay * _dt)
			_update_stars()
	# Lose the whole response if contact is clearly broken for long enough.
	if stars > 0 and _last_seen_time > 28.0 and nearest > 180.0 and cooldown <= 0.0:
		clear()


func _player_target_point() -> Vector3:
	var vehicle = player_ref.get("vehicle") if "vehicle" in player_ref else null
	if vehicle is Node3D and is_instance_valid(vehicle):
		return vehicle.global_position + Vector3.UP * 0.8
	return player_ref.global_position + Vector3.UP * 1.0


## Collision RIDs for the player and their vehicle, for raycast exclusion.
## The player may be a plain Node3D in headless harnesses, which has no RID.
func _player_rids() -> Array:
	var rids: Array = []
	if player_ref != null and is_instance_valid(player_ref) and player_ref is CollisionObject3D:
		rids.append(player_ref.get_rid())
		var vehicle = player_ref.get("vehicle") if "vehicle" in player_ref else null
		if vehicle is Node3D and is_instance_valid(vehicle):
			rids.append(vehicle.get_rid())
	return rids


func _has_line_of_sight(from_node: Node3D, target_point: Vector3, distance: float) -> bool:
	if distance > 160.0:
		return false
	if distance <= 18.0:
		return true
	var space := from_node.get_world_3d().direct_space_state
	if space == null:
		return distance <= 90.0
	var from_point := from_node.global_position + Vector3.UP * 1.4
	var query := PhysicsRayQueryParameters3D.create(from_point, target_point)
	var exclude: Array = [from_node.get_rid()]
	exclude.append_array(_player_rids())
	query.exclude = exclude
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return true
	# If the ray hits very close to the target, treat as visible.
	var hit_pos: Vector3 = hit.get("position", from_point)
	return hit_pos.distance_to(target_point) < 4.0


func _spawn_police() -> void:
	if not ResourceLoader.exists(POLICE_SCENE):
		return
	var packed: PackedScene = load(POLICE_SCENE)
	if packed == null:
		return
	var car: Node3D = packed.instantiate()
	add_child(car)
	var angle := randf() * TAU
	var distance := randf_range(110.0, 180.0)
	var spawn_pos := player_ref.global_position + Vector3(cos(angle) * distance, 1.0, sin(angle) * distance)
	# Prefer spawning out of immediate sight where possible (no teleporting behind).
	if _last_seen_time < 6.0 and _is_point_visible_to_player(spawn_pos):
		angle += PI * 0.75
		spawn_pos = player_ref.global_position + Vector3(cos(angle) * distance, 1.0, sin(angle) * distance)
	car.global_position = spawn_pos
	if car.has_method("set_pursuit_target"):
		car.call("set_pursuit_target", player_ref)
	police.append(car)
	stats["spawned"] = int(stats.get("spawned", 0)) + 1
	stats["max_active"] = maxi(int(stats.get("max_active", 0)), police.size())


func _is_point_visible_to_player(point: Vector3) -> bool:
	if player_ref == null or not is_instance_valid(player_ref):
		return false
	var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
	var origin := cam.global_position if cam != null else player_ref.global_position + Vector3.UP * 1.6
	if origin.distance_to(point) > 180.0:
		return false
	var space := player_ref.get_world_3d().direct_space_state
	if space == null:
		return false
	var query := PhysicsRayQueryParameters3D.create(origin, point + Vector3.UP * 0.8)
	query.exclude = _player_rids()
	var hit := space.intersect_ray(query)
	return hit.is_empty()


func clear() -> void:
	heat = 0.0
	stars = 0
	cooldown = 0.0
	_last_seen_time = 0.0
	_spawn_timer = 0.0
	_cleanup_police_units()
	wanted_changed.emit(0)


func stars_text() -> String:
	if stars <= 0:
		return ""
	return "WANTED  " + "★".repeat(stars)
