class_name TrainManager
extends Node3D

## Runs sourced K Set rolling stock along the Milsons Point–Redfern rail
## corridor. The mesh is the supplied K Set car (original 1:1 model), centred
## and scaled to the game's metre world. No train physics touches roads, cars
## or pedestrians: trains stay on their own elevated/underground corridor.

const KSET_MESH := preload("res://sydney/railway/models/kset/model_0.obj")

enum TrainType { KSET }

var trains: Array[Dictionary] = []
var stats: Dictionary = {}
var _player_ref: Node3D
var _railway: Node3D
var _route: Array[Vector3] = []
var _station_stops: Array[Dictionary] = []
## Derived from the imported model's real bounds. The old fixed +0.9 lift put
## the wheels ~1.26 m below the rail head, so trains visibly sank into the
## bridge deck and the ground. Nothing about this is an arbitrary visual offset.
var _car_half_height: float = 2.158
var _rail_head_cbd: float = 0.155
var _rail_head_bridge: float = 0.24


func setup(railway: Node3D, player: Node3D) -> void:
	_railway = railway
	_player_ref = player
	if railway == null:
		push_warning("TrainManager: no SydneyRailNetwork to follow")
		return
	_route = railway.get("main_route_points")
	if _route.size() < 4:
		push_warning("TrainManager: rail route is too short")
		return
	if KSET_MESH != null:
		var aabb: AABB = KSET_MESH.get_aabb()
		var scale := 20.3 / maxf(aabb.size.z, 0.001)
		_car_half_height = aabb.size.y * scale * 0.5
	_build_station_stops()
	_spawn_trains()
	stats = {
		"trains": trains.size(),
		"cars": _total_cars(),
		"routeLengthM": float(railway.get("stats").get("mainRouteLengthM", 0.0)),
		"rollingStock": "Sydney Trains K Set (C3564)",
		"stationStops": _station_stops.size(),
	}


func _build_station_stops() -> void:
	_station_stops.clear()
	if _railway == null:
		return
	var indices: Dictionary = _railway.get("station_route_indices")
	if typeof(indices) != TYPE_DICTIONARY:
		return
	for station_id in indices.keys():
		var idx := int(indices[station_id])
		if idx >= 0 and idx < _route.size():
			_station_stops.append({"id": str(station_id), "index": idx})
	_station_stops.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["index"]) < int(b["index"])
	)


func _total_cars() -> int:
	var count := 0
	for train: Dictionary in trains:
		count += int(train["cars"].size())
	return count


func _spawn_trains() -> void:
	# Two K Set consists in opposite directions, each four cars long.
	_add_train(0.06, 1.0, 4)
	_add_train(0.58, -1.0, 4)


func _add_train(start_fraction: float, direction: float, car_count: int) -> void:
	var consist := Node3D.new()
	consist.name = "KSetConsist_%d" % trains.size()
	add_child(consist)
	var cars: Array[Node3D] = []
	for index in car_count:
		var car := _make_car()
		consist.add_child(car)
		cars.append(car)
	var car_spacing := 20.3
	var start_index := int(start_fraction * float(_route.size() - 1))
	trains.append({
		"consist": consist,
		"cars": cars,
		"index": float(start_index),
		"direction": direction,
		"speed": 18.0,
		"spacing": car_spacing,
		"dwell_time": 0.0,
		"last_stop_index": -1,
	})
	_update_consist(trains[-1], true)


func _make_car() -> Node3D:
	var root := Node3D.new()
	root.name = "KSetCar"
	var mesh: Mesh = KSET_MESH
	if mesh != null:
		var instance := MeshInstance3D.new()
		instance.name = "CarBody"
		instance.mesh = mesh
		# The sourced OBJ is huge and offset from origin; centre and scale it.
		var aabb: AABB = mesh.get_aabb()
		var scale_factor := 20.3 / maxf(aabb.size.z, 0.001)
		instance.scale = Vector3.ONE * scale_factor
		instance.position = -(aabb.position + aabb.size * 0.5) * scale_factor
		root.add_child(instance)
	# Cab marker lights so the consist reads at night.
	for side in [-1.0, 1.0]:
		var lamp := MeshInstance3D.new()
		lamp.name = "MarkerLight"
		var sphere := SphereMesh.new()
		sphere.radius = 0.12
		sphere.height = 0.24
		lamp.mesh = sphere
		var mat := StandardMaterial3D.new()
		mat.emission_enabled = true
		mat.emission = Color("fff0c4")
		mat.emission_energy_multiplier = 2.0
		lamp.material_override = mat
		lamp.position = Vector3(side * 0.7, _car_half_height - 0.5, -10.0)
		root.add_child(lamp)
	return root


func _process(delta: float) -> void:
	if _route.size() < 4:
		return
	for train: Dictionary in trains:
		# Distance LOD: distant consists still advance, but dwell/service timing
		# remains simple and stable rather than physically simulated.
		var step := delta
		var pos: Vector3 = train["consist"].global_position
		if _player_ref != null:
			var distance := _player_ref.global_position.distance_to(pos)
			if distance > 250.0:
				step = delta * 4.0

		var dwell: float = float(train.get("dwell_time", 0.0))
		if dwell > 0.0:
			train["dwell_time"] = maxf(0.0, dwell - step)
			_update_consist(train, false)
			continue

		var route_length := float(_route.size() - 1)
		var current_index: float = float(train["index"])
		var direction: float = float(train["direction"])
		var speed: float = float(train.get("speed", 18.0))
		var advanced: float = current_index + direction * speed * step / 8.0
		if advanced > route_length:
			advanced = 0.0
			train["last_stop_index"] = -1
		elif advanced < 0.0:
			advanced = route_length
			train["last_stop_index"] = -1

		# Basic station service: pause briefly at station stops in travel direction.
		# This is presentation/service polish, not a signaling or timetable system.
		var stop_idx := _next_stop_index(current_index, advanced, direction)
		if stop_idx >= 0 and stop_idx != int(train.get("last_stop_index", -1)):
			train["index"] = float(stop_idx)
			train["dwell_time"] = _station_dwell_seconds(stop_idx)
			train["last_stop_index"] = stop_idx
		else:
			train["index"] = advanced
		_update_consist(train, false)


func _next_stop_index(from_index: float, to_index: float, direction: float) -> int:
	if _station_stops.is_empty():
		return -1
	if direction >= 0.0:
		# Wrapped around to route start.
		if to_index < from_index:
			return -1
		for stop in _station_stops:
			var idx := float(int(stop["index"]))
			# Strict lower bound prevents immediately re-triggering the same stop
			# when resuming from a dwell exactly at idx.
			if idx > from_index and idx <= to_index:
				return int(idx)
	else:
		# Wrapped around to route end.
		if to_index > from_index:
			return -1
		for i in range(_station_stops.size() - 1, -1, -1):
			var idx := float(int(_station_stops[i]["index"]))
			if idx < from_index and idx >= to_index:
				return int(idx)
	return -1


func _station_dwell_seconds(stop_index: int) -> float:
	# Slightly longer dwells at major stations.
	if _railway != null:
		for station_id in ["central", "town-hall", "wynyard", "redfern"]:
			if int(_railway.call("get_station_route_index", station_id)) == stop_index:
				return 14.0
	return 9.0


func _update_consist(train: Dictionary, immediate: bool) -> void:
	var route_length := float(_route.size() - 1)
	var cars: Array = train["cars"]
	var spacing: float = train["spacing"]
	for index in cars.size():
		var offset: float = -float(index) * spacing / 8.0 * train["direction"]
		var point_index := clampf(float(train["index"]) + offset, 0.0, route_length)
		var i0 := int(floor(point_index))
		var i1 := mini(i0 + 1, _route.size() - 1)
		var point: Vector3 = _route[i0].lerp(_route[i1], point_index - float(i0))
		var ahead: Vector3 = _route[i1] - _route[i0]
		ahead.y = 0.0
		if ahead.length_squared() < 0.001:
			ahead = Vector3.FORWARD
		var rail_head := _rail_head_cbd
		var bridge_range: Variant = _railway.get("_bridge_range") if _railway != null else null
		if bridge_range is Vector2i and (bridge_range as Vector2i).x >= 0:
			var span: Vector2i = bridge_range
			if i0 >= span.x and i0 <= span.y:
				rail_head = _rail_head_bridge
		var car: Node3D = cars[index]
		car.global_position = point + Vector3.UP * (_car_half_height + rail_head)
		car.rotation.y = atan2(-ahead.x * train["direction"], -ahead.z * train["direction"])
