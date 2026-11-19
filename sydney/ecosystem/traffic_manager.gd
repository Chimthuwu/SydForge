class_name TrafficManager
extends Node3D

## Manages city-wide Sydney road traffic.
## Spawns, despawns, and pools vehicles based on distance to player and road network topology.
## Distributes vehicle types across districts and road types (arterials, CBD, bridge, residential).

@export var max_active_vehicles: int = 40
@export var spawn_radius: float = 240.0
@export var despawn_radius: float = 300.0

var sydney_world: SydneyWorld
var player_ref: Node3D
var road_data: Array = []
var active_vehicles: Array[VehicleTrafficController] = []

var _spawn_timer: float = 0.0

func _ready() -> void:
	add_to_group("traffic_managers")

func setup(world: SydneyWorld, player: Node3D) -> void:
	sydney_world = world
	player_ref = player
	_index_roads()

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
				"lanes": r.get("lanes", 2),
				"points": pts3d
			})

func _process(delta: float) -> void:
	if player_ref == null or road_data.is_empty():
		return
	
	_spawn_timer += delta
	if _spawn_timer >= 1.0: # Check spawn/cull every 1s
		_spawn_timer = 0.0
		_cull_distant_vehicles()
		_spawn_traffic_near_player()

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
	# Find candidate road segments within spawn_radius
	var candidates: Array = []
	for r in road_data:
		var pts: Array[Vector3] = r["points"]
		var mid := pts[pts.size() / 2]
		var dist := p_pos.distance_to(mid)
		if dist > 35.0 and dist < spawn_radius:
			candidates.append(r)
	
	if candidates.is_empty():
		return
	
	# Try spawning a couple vehicles
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
	
	# Determine vehicle class based on road type
	var vclass: int = _pick_vehicle_class(is_arterial)
	
	var controller := VehicleTrafficController.new()
	controller.vehicle_class = vclass
	add_child(controller)
	
	# Choose lane offset and direction
	var forward := (randf() > 0.5)
	var offset := (1.8 if forward else -1.8)
	if vclass == VehicleVisualBuilder.VehicleClass.MOTORBIKE or vclass == VehicleVisualBuilder.VehicleClass.SCOOTER:
		offset *= (0.6 + randf() * 0.4) # motorbikes take narrower track
	
	controller.setup_route(pts, offset, forward)
	active_vehicles.append(controller)

func _pick_vehicle_class(is_arterial: bool) -> int:
	var roll := randf()
	if is_arterial:
		# Arterial roads: heavy trucks, buses, utes, delivery vans, passenger cars
		if roll < 0.15:
			return VehicleVisualBuilder.VehicleClass.BUS
		elif roll < 0.28:
			return VehicleVisualBuilder.VehicleClass.UTE
		elif roll < 0.40:
			return VehicleVisualBuilder.VehicleClass.SEMI_TRAILER
		elif roll < 0.52:
			return VehicleVisualBuilder.VehicleClass.BOX_TRUCK
		elif roll < 0.65:
			return VehicleVisualBuilder.VehicleClass.DELIVERY_VAN
		elif roll < 0.75:
			return VehicleVisualBuilder.VehicleClass.SUV_4WD
		elif roll < 0.85:
			return VehicleVisualBuilder.VehicleClass.SEDAN
		elif roll < 0.93:
			return VehicleVisualBuilder.VehicleClass.TAXI
		else:
			return VehicleVisualBuilder.VehicleClass.MOTORBIKE
	else:
		# City streets: cars, hatchbacks, taxis, utes, vans, motorbikes, scooters, garbage trucks
		if roll < 0.20:
			return VehicleVisualBuilder.VehicleClass.SEDAN
		elif roll < 0.35:
			return VehicleVisualBuilder.VehicleClass.HATCHBACK
		elif roll < 0.48:
			return VehicleVisualBuilder.VehicleClass.TAXI
		elif roll < 0.60:
			return VehicleVisualBuilder.VehicleClass.UTE
		elif roll < 0.72:
			return VehicleVisualBuilder.VehicleClass.SUV_4WD
		elif roll < 0.82:
			return VehicleVisualBuilder.VehicleClass.DELIVERY_VAN
		elif roll < 0.88:
			return VehicleVisualBuilder.VehicleClass.MOTORBIKE
		elif roll < 0.94:
			return VehicleVisualBuilder.VehicleClass.SCOOTER
		elif roll < 0.98:
			return VehicleVisualBuilder.VehicleClass.BUS
		else:
			return VehicleVisualBuilder.VehicleClass.GARBAGE_TRUCK
