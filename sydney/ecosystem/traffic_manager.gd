class_name TrafficManager
extends Node3D

## Manages city-wide Sydney road traffic.
## Handles left-hand driving, following distance, traffic light signals,
## pedestrian crossings, time-of-day density profiles, and Australian vehicle fleets.

@export var max_active_vehicles: int = 40
@export var spawn_radius: float = 240.0
@export var despawn_radius: float = 300.0

var sydney_world: SydneyWorld
var player_ref: Node3D
var road_data: Array = []
var active_vehicles: Array[VehicleTrafficController] = []

# Traffic signals & junctions
var junctions: Array[Dictionary] = []
var crossings: Array[Dictionary] = []
var _signal_cycle_time: float = 0.0

# Time-of-day profile
var current_period: String = "morning"
var activity_period: String = "morning"
var is_night: bool = false
var _spawn_timer: float = 0.0

## District density multiplier owned by WorldSimulationDirector.
var density_multiplier: float = 1.0
var _base_cap: int = 40

## Temporary road obstructions (incidents, roadworks, collisions). Cars slow
## and, where possible, change lanes instead of driving through them.
var obstructions: Array[Dictionary] = []
var _emergency_dispatch_cooldown: float = 0.0


func _ready() -> void:
	add_to_group("traffic_managers")
	_base_cap = max_active_vehicles
	_connect_time_manager()


func set_density_multiplier(value: float) -> void:
	density_multiplier = clampf(value, 0.35, 1.5)
	_apply_time_profile()


func add_obstruction(position: Vector3, radius: float = 6.0, ttl: float = 40.0) -> void:
	obstructions.append({"pos": position, "radius": maxf(radius, 2.0), "ttl": maxf(ttl, 1.0)})
	if obstructions.size() > 8:
		obstructions.remove_at(0)


func is_road_blocked(position: Vector3) -> bool:
	for obstruction in obstructions:
		if position.distance_to(obstruction["pos"]) < float(obstruction["radius"]):
			return true
	return false


## Crossings are indexed from the world export. Cars slow within 12 m of a
## zebra they are heading toward, whether or not a signal is installed.
func should_slow_for_crossing(position: Vector3, heading: Vector3) -> bool:
	for crossing in crossings:
		var offset: Vector3 = crossing["pos"] - position
		var dist := offset.length()
		if dist > 1.0 and dist < 12.0 and heading.dot(offset / dist) > 0.55:
			return true
	return false


func warn_nearby(position: Vector3, radius: float) -> void:
	for vehicle in active_vehicles:
		if is_instance_valid(vehicle) and vehicle.global_position.distance_to(position) < radius:
			if vehicle.has_method("notice_player_threat"):
				vehicle.call("notice_player_threat", position)


## Dispatch a real AI emergency vehicle from the existing fleet. It is created
## on a road segment at least 70 m from the player and drives toward the incident
## rather than teleporting into place.
func request_emergency_response(incident_pos: Vector3, kind: String = "police") -> bool:
	if _emergency_dispatch_cooldown > 0.0 or road_data.is_empty() or player_ref == null:
		return false
	var responders := 0
	for vehicle in active_vehicles:
		if is_instance_valid(vehicle) and vehicle.has_method("is_responding_emergency") and vehicle.call("is_responding_emergency"):
			responders += 1
	if responders >= 2:
		return false

	var destination := incident_pos
	var best_road: Dictionary = {}
	var best_spawn := Vector3.ZERO
	var best_score := INF
	for road in road_data:
		var pts: Array[Vector3] = road["points"]
		if pts.size() < 3:
			continue
		for i in range(1, pts.size() - 1):
			var pt := pts[i]
			var from_player := player_ref.global_position.distance_to(pt)
			var to_incident := pt.distance_to(destination)
			if from_player < 70.0 or to_incident > 160.0 or to_incident < 20.0:
				continue
			var score := to_incident + absf(from_player - 110.0) * 0.2
			if score < best_score:
				best_score = score
				best_road = road
				best_spawn = pt
	if best_road.is_empty():
		return false

	var vclass := VehicleVisualBuilder.VehicleClass.POLICE
	if kind == "ambulance":
		vclass = VehicleVisualBuilder.VehicleClass.AMBULANCE
	elif kind == "fire" or kind == "fire_truck":
		vclass = VehicleVisualBuilder.VehicleClass.FIRE_TRUCK

	var controller := VehicleTrafficController.new()
	controller.vehicle_class = vclass
	add_child(controller)
	# Choose the route direction whose end sits closest to the incident.
	var pts: Array[Vector3] = best_road["points"]
	var forward := pts[pts.size() - 1].distance_to(destination) < pts[0].distance_to(destination)
	var nearest_idx := 0
	var nearest_dist := INF
	for i in pts.size():
		var d := pts[i].distance_to(best_spawn)
		if d < nearest_dist:
			nearest_dist = d
			nearest_idx = i
	controller.setup_route(pts, 2.4, forward)
	# setup_route begins at the road end; shift onto the chosen segment and let
	# the controller pick the nearest waypoint from there.
	controller.global_position = pts[nearest_idx] + Vector3.UP * 0.2
	controller.current_point_idx = nearest_idx if forward else nearest_idx
	controller.road_forward_dir = 1 if forward else -1
	controller.set_emergency_responding(true)
	if controller.has_method("set_destination"):
		controller.call("set_destination", destination)
	active_vehicles.append(controller)
	_emergency_dispatch_cooldown = 25.0
	return true


func setup(world: SydneyWorld, player: Node3D) -> void:
	sydney_world = world
	player_ref = player
	_index_roads()
	_index_junctions_and_crossings()


func _connect_time_manager() -> void:
	var time_mgrs := get_tree().get_nodes_in_group("time_managers")
	if not time_mgrs.is_empty():
		var tm = time_mgrs[0]
		current_period = str(tm.get("current_period"))
		is_night = bool(tm.get("is_night"))
		if tm.has_signal("period_changed"):
			tm.period_changed.connect(_on_period_changed)
		if tm.has_signal("activity_period_changed"):
			tm.activity_period_changed.connect(_on_activity_period_changed)
		if tm.has_signal("night_mode_changed"):
			tm.night_mode_changed.connect(_on_night_mode_changed)
		_apply_time_profile()


func _on_period_changed(period_name: String) -> void:
	current_period = period_name
	_apply_time_profile()


func _on_activity_period_changed(period_name: String) -> void:
	activity_period = period_name
	_apply_time_profile()


func _on_night_mode_changed(night: bool) -> void:
	is_night = night
	_apply_time_profile()


func _apply_time_profile() -> void:
	var period := activity_period
	if not period in ["morning", "daytime", "afternoon", "evening", "night"]:
		# Backwards compatibility for callers that only set the detailed period.
		match current_period:
			"morning", "dawn": period = "morning"
			"midday": period = "daytime"
			"afternoon": period = "afternoon"
			"sunset", "dusk": period = "evening"
			"night", "pre-dawn": period = "night"
	var cap: int
	# Reduced from 46/38/46/34/22 after the renderer audit showed ~4,500 draw
	# calls at the old caps. The city still reads as populated at street level
	# because spawns are player-centric and districts add local multipliers.
	match period:
		"morning": cap = 32 # Commuter peak
		"daytime": cap = 26 # Commercial / shopping
		"afternoon": cap = 32 # Afternoon peak
		"evening": cap = 24 # Dining & entertainment
		"night": cap = 16 # Quiet residential, busy nightlife hubs
		_: cap = 26
	max_active_vehicles = maxi(6, int(float(cap) * density_multiplier))


## Stage B exports lanes as a list per direction; earlier exports used a scalar.
func _lane_count(value: Variant) -> int:
	if value == null:
		return 2
	if typeof(value) == TYPE_ARRAY:
		var count := 0
		for item in value:
			if item != null:
				count += maxi(int(item), 0)
		return maxi(count, 1)
	if value is int or value is float:
		return maxi(int(value), 1)
	return 2


func _index_roads() -> void:
	road_data.clear()
	if sydney_world == null or not ("data" in sydney_world):
		return
	var raw_roads: Array = sydney_world.data.get("roads", [])
	for r in raw_roads:
		var pts: Array = r.get("points", [])
		if pts.size() >= 2:
			var pts3d: Array[Vector3] = []
			for p in pts:
				pts3d.append(Vector3(float(p[0]), 0.2, float(p[1])))
			road_data.append({
				"id": r.get("id"),
				"name": r.get("name", ""),
				"highway": r.get("highway", "secondary"),
				"lanes": _lane_count(r.get("lanes", 2)),
				"points": pts3d
			})


func _index_junctions_and_crossings() -> void:
	junctions.clear()
	crossings.clear()
	if sydney_world == null or not ("data" in sydney_world):
		return
	
	# Index major intersections
	var raw_junctions: Array = sydney_world.data.get("junctions", [])
	for j in raw_junctions:
		var road_count: int = int(j.get("roadCount", 0))
		if road_count >= 3: # 3-way or 4-way intersections
			junctions.append({
				"id": j.get("id"),
				"pos": Vector3(float(j.get("x", 0.0)), 0.2, float(j.get("z", 0.0))),
				"road_count": road_count,
				"district": str(j.get("district", ""))
			})

	# Index pedestrian crossings
	var raw_crossings: Array = sydney_world.data.get("crossings", [])
	for c in raw_crossings:
		crossings.append({
			"id": c.get("id"),
			"pos": Vector3(float(c.get("x", 0.0)), 0.2, float(c.get("z", 0.0))),
			"length": float(c.get("lengthM", 12.0)),
			"road_id": str(c.get("roadId", ""))
		})


func _process(delta: float) -> void:
	_emergency_dispatch_cooldown = maxf(0.0, _emergency_dispatch_cooldown - delta)
	var i := obstructions.size() - 1
	while i >= 0:
		obstructions[i]["ttl"] = float(obstructions[i]["ttl"]) - delta
		if float(obstructions[i]["ttl"]) <= 0.0:
			obstructions.remove_at(i)
		i -= 1

	# Update traffic signal cycle: 40s full cycle
	# 0-17s: North-South Green (East-West Red)
	# 17-20s: North-South Amber
	# 20-37s: East-West Green (North-South Red)
	# 37-40s: East-West Amber
	_signal_cycle_time = fmod(_signal_cycle_time + delta, 40.0)

	if player_ref == null or road_data.is_empty():
		return
	
	_spawn_timer += delta
	if _spawn_timer >= 1.0:
		_spawn_timer = 0.0
		_cull_distant_vehicles()
		_spawn_traffic_near_player()
		_update_audio_focus()


func is_signal_red_for_position(car_pos: Vector3, car_heading: Vector3) -> bool:
	if junctions.is_empty():
		return false
	
	# Check if vehicle is approaching a junction
	for j in junctions:
		var j_pos: Vector3 = j["pos"]
		var d := car_pos.distance_to(j_pos)
		if d > 6.0 and d < 24.0:
			var to_junc := (j_pos - car_pos).normalized()
			if car_heading.dot(to_junc) > 0.65: # Heading into this intersection
				# Determine if car is moving roughly North-South or East-West
				var is_north_south := absf(car_heading.z) > absf(car_heading.x)
				if is_north_south:
					# North-South is RED during 20-40s
					return _signal_cycle_time >= 17.0
				else:
					# East-West is RED during 0-20s
					return _signal_cycle_time < 17.0 or _signal_cycle_time >= 37.0
	return false


func _update_audio_focus() -> void:
	var p_pos := player_ref.global_position
	var candidates: Array = []
	for vehicle in active_vehicles:
		if not is_instance_valid(vehicle):
			continue
		var distance := p_pos.distance_to(vehicle.global_position)
		if distance < 70.0:
			candidates.append({"vehicle": vehicle, "distance": distance})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["distance"]) < float(b["distance"]))
	for vehicle in active_vehicles:
		if is_instance_valid(vehicle):
			vehicle.set_audio_focus(false)
	for index in mini(6, candidates.size()):
		var candidate: Dictionary = candidates[index]
		if float(candidate["distance"]) < 55.0:
			(candidate["vehicle"] as VehicleTrafficController).set_audio_focus(true)


func _cull_distant_vehicles() -> void:
	var p_pos := player_ref.global_position
	var i := active_vehicles.size() - 1
	while i >= 0:
		var v := active_vehicles[i]
		if is_instance_valid(v):
			var dist := p_pos.distance_to(v.global_position)
			if dist > despawn_radius:
				active_vehicles.remove_at(i)
				v.queue_free()
		else:
			active_vehicles.remove_at(i)
		i -= 1


func _spawn_traffic_near_player() -> void:
	if active_vehicles.size() >= max_active_vehicles:
		return
	
	var p_pos := player_ref.global_position
	var candidates: Array = []
	for r in road_data:
		var pts: Array[Vector3] = r["points"]
		var mid := pts[pts.size() / 2]
		var dist := p_pos.distance_to(mid)
		if dist > 45.0 and dist < spawn_radius and not is_road_blocked(mid):
			candidates.append(r)
	
	if candidates.is_empty():
		return
	
	var spawns_to_attempt := mini(3, max_active_vehicles - active_vehicles.size())
	for s in spawns_to_attempt:
		var road = candidates[randi() % candidates.size()]
		_spawn_single_vehicle(road)


func _spawn_single_vehicle(road: Dictionary) -> void:
	var pts: Array[Vector3] = road["points"]
	if pts.size() < 2:
		return
	
	var highway: String = road.get("highway", "secondary")
	var is_arterial: bool = highway in ["primary", "trunk", "motorway", "primary_link", "trunk_link"]
	var lanes: int = int(road.get("lanes", 2))
	
	# Determine vehicle class based on road type and time of day
	var vclass: int = _pick_vehicle_class(is_arterial)
	
	var controller := VehicleTrafficController.new()
	controller.vehicle_class = vclass
	add_child(controller)
	
	# Australian Left-Hand Traffic:
	# Direction: forward along points (forward = true) or backward (forward = false)
	var forward := (randf() > 0.5)
	
	# Base lateral lane offset (e.g. 1.9m for single lane, 4.2m for outer curb lane on multi-lane)
	var base_offset := 1.9
	if lanes >= 4:
		base_offset = 3.6 if randf() < 0.6 else 1.6 # curb lane or inner lane
	if vclass == VehicleVisualBuilder.VehicleClass.MOTORBIKE or vclass == VehicleVisualBuilder.VehicleClass.SCOOTER:
		base_offset *= (0.6 + randf() * 0.4)
	
	controller.setup_route(pts, base_offset, forward)
	active_vehicles.append(controller)


func _pick_vehicle_class(is_arterial: bool) -> int:
	var roll := randf()
	
	# Time-adjusted weights
	if is_night:
		# Night: performance cars are common alongside taxis and police.
		if roll < 0.20:
			return VehicleVisualBuilder.VehicleClass.TAXI
		elif roll < 0.34:
			return VehicleVisualBuilder.VehicleClass.SEDAN
		elif roll < 0.42:
			return VehicleVisualBuilder.VehicleClass.UTE
		elif roll < 0.54:
			return VehicleVisualBuilder.VehicleClass.SPORTS
		elif roll < 0.64:
			return VehicleVisualBuilder.VehicleClass.SUPERCAR
		elif roll < 0.72:
			return VehicleVisualBuilder.VehicleClass.MUSCLE
		elif roll < 0.80:
			return VehicleVisualBuilder.VehicleClass.COUPE
		elif roll < 0.88:
			return VehicleVisualBuilder.VehicleClass.POLICE
		elif roll < 0.94:
			return VehicleVisualBuilder.VehicleClass.HATCHBACK
		elif roll < 0.97:
			return VehicleVisualBuilder.VehicleClass.MOTORBIKE
		else:
			return VehicleVisualBuilder.VehicleClass.PERFORMANCE_SEDAN
	elif is_arterial:
		# Arterials carry a visible mix of performance cars and ordinary traffic.
		if roll < 0.10:
			return VehicleVisualBuilder.VehicleClass.BUS
		elif roll < 0.18:
			return VehicleVisualBuilder.VehicleClass.UTE
		elif roll < 0.26:
			return VehicleVisualBuilder.VehicleClass.SEMI_TRAILER
		elif roll < 0.32:
			return VehicleVisualBuilder.VehicleClass.BOX_TRUCK
		elif roll < 0.40:
			return VehicleVisualBuilder.VehicleClass.DELIVERY_VAN
		elif roll < 0.48:
			return VehicleVisualBuilder.VehicleClass.SUV_4WD
		elif roll < 0.58:
			return VehicleVisualBuilder.VehicleClass.SEDAN
		elif roll < 0.64:
			return VehicleVisualBuilder.VehicleClass.TAXI
		elif roll < 0.70:
			return VehicleVisualBuilder.VehicleClass.POLICE
		elif roll < 0.76:
			return VehicleVisualBuilder.VehicleClass.SPORTS
		elif roll < 0.82:
			return VehicleVisualBuilder.VehicleClass.SUPERCAR
		elif roll < 0.88:
			return VehicleVisualBuilder.VehicleClass.MUSCLE
		elif roll < 0.93:
			return VehicleVisualBuilder.VehicleClass.PERFORMANCE_SEDAN
		elif roll < 0.97:
			return VehicleVisualBuilder.VehicleClass.COUPE
		else:
			return VehicleVisualBuilder.VehicleClass.MOTORBIKE
	else:
		# City streets: a broad, varied pool with common sports/performance cars.
		if roll < 0.13:
			return VehicleVisualBuilder.VehicleClass.SEDAN
		elif roll < 0.23:
			return VehicleVisualBuilder.VehicleClass.HATCHBACK
		elif roll < 0.31:
			return VehicleVisualBuilder.VehicleClass.TAXI
		elif roll < 0.39:
			return VehicleVisualBuilder.VehicleClass.UTE
		elif roll < 0.46:
			return VehicleVisualBuilder.VehicleClass.SUV_4WD
		elif roll < 0.52:
			return VehicleVisualBuilder.VehicleClass.DELIVERY_VAN
		elif roll < 0.58:
			return VehicleVisualBuilder.VehicleClass.MOTORBIKE
		elif roll < 0.62:
			return VehicleVisualBuilder.VehicleClass.SCOOTER
		elif roll < 0.70:
			return VehicleVisualBuilder.VehicleClass.SPORTS
		elif roll < 0.77:
			return VehicleVisualBuilder.VehicleClass.SUPERCAR
		elif roll < 0.83:
			return VehicleVisualBuilder.VehicleClass.MUSCLE
		elif roll < 0.89:
			return VehicleVisualBuilder.VehicleClass.PERFORMANCE_SEDAN
		elif roll < 0.94:
			return VehicleVisualBuilder.VehicleClass.COUPE
		elif roll < 0.97:
			return VehicleVisualBuilder.VehicleClass.POLICE
		else:
			return VehicleVisualBuilder.VehicleClass.BUS
