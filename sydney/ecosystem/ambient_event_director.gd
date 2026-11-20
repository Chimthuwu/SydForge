class_name AmbientEventDirector
extends Node3D

## Director for random, emergent Sydney ambient events.
## Selects believable micro-events based on district, time of day, weather,
## and player proximity. Gracefully manages event lifecycles.

signal ambient_event_occurred(event_type: String, district: String)

enum EventType {
	BUSKER,
	TOURIST_PHOTO,
	DELIVERY_UNLOAD,
	BUS_BOARDING,
	FRIENDS_GREETING,
	DOG_WALKER,
	TAXI_DROPOFF,
	NIGHTLIFE_EXIT
}

const EVENT_NAMES := [
	"Street Performer",
	"Tourists Taking Photos",
	"Delivery Unloading",
	"Bus Passenger Boarding",
	"Friends Greeting",
	"Dog Walker",
	"Taxi Drop-Off",
	"Nightlife Crowd Leaving"
]

@export var max_active_events: int = 2
@export var event_cooldown: float = 45.0 # Infrequent, organic encounters

var active_events: Array[Dictionary] = []
var player_ref: Node3D
var sydney_world: SydneyWorld
var time_manager: Node
var weather_manager: Node

var _cooldown_timer: float = 20.0 # First check delay


func _ready() -> void:
	add_to_group("ambient_event_directors")


func setup(world: SydneyWorld, player: Node3D) -> void:
	sydney_world = world
	player_ref = player
	time_manager = get_tree().get_first_node_in_group("time_managers")
	weather_manager = get_tree().get_first_node_in_group("weather_managers")


func _process(delta: float) -> void:
	if player_ref == null:
		return

	_cooldown_timer -= delta
	if _cooldown_timer <= 0.0:
		_cooldown_timer = event_cooldown + randf_range(0.0, 30.0)
		_cull_finished_events()
		if active_events.size() < max_active_events:
			_attempt_trigger_event()


func _cull_finished_events() -> void:
	var p_pos := player_ref.global_position
	var i := active_events.size() - 1
	while i >= 0:
		var ev: Dictionary = active_events[i]
		var root: Node3D = ev["root"]
		var elapsed: float = float(ev.get("elapsed", 0.0)) + 1.0
		ev["elapsed"] = elapsed
		var duration: float = float(ev.get("duration", 40.0))
		var dist := p_pos.distance_to(ev["pos"])

		if elapsed >= duration or dist > 140.0:
			if is_instance_valid(root):
				root.queue_free()
			active_events.remove_at(i)
		i -= 1


func _attempt_trigger_event() -> void:
	var p_pos := player_ref.global_position
	var district_id := _get_player_district()
	var time_period := _get_time_period()
	var is_raining := _is_raining()

	# Select event type suitable for current conditions
	var candidate_types: Array[int] = []

	if is_raining:
		# In rain, only sheltered or quick vehicle events occur
		candidate_types = [EventType.TAXI_DROPOFF, EventType.BUS_BOARDING, EventType.DELIVERY_UNLOAD]
	else:
		if district_id in ["circular-quay", "the-rocks", "darling-quarter"]:
			candidate_types.append(EventType.BUSKER)
			candidate_types.append(EventType.TOURIST_PHOTO)
			candidate_types.append(EventType.TAXI_DROPOFF)
			if time_period in ["evening", "night"]:
				candidate_types.append(EventType.NIGHTLIFE_EXIT)
		elif district_id in ["hyde-park", "the-domain", "botanic-garden"]:
			candidate_types.append(EventType.DOG_WALKER)
			candidate_types.append(EventType.FRIENDS_GREETING)
			candidate_types.append(EventType.TOURIST_PHOTO)
		elif district_id in ["kings-cross"]:
			if time_period in ["evening", "night"]:
				candidate_types.append(EventType.NIGHTLIFE_EXIT)
				candidate_types.append(EventType.TAXI_DROPOFF)
			else:
				candidate_types.append(EventType.FRIENDS_GREETING)
		else: # CBD Core, Town Hall, Surry Hills
			candidate_types.append(EventType.DELIVERY_UNLOAD)
			candidate_types.append(EventType.BUS_BOARDING)
			candidate_types.append(EventType.FRIENDS_GREETING)
			candidate_types.append(EventType.TAXI_DROPOFF)

	if candidate_types.is_empty():
		return

	var chosen_type: int = candidate_types[randi() % candidate_types.size()]
	
	# Spawn position: 28m to 55m away, on a reasonable offset from player
	var angle := randf() * TAU
	var dist := randf_range(28.0, 52.0)
	var spawn_pos := p_pos + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
	
	_spawn_event(chosen_type, spawn_pos, district_id)


func _spawn_event(type: int, pos: Vector3, district_id: String) -> void:
	var root := Node3D.new()
	root.name = "AmbientEvent_" + str(type) + "_" + str(Time.get_ticks_msec())
	root.position = pos
	add_child(root)

	var ev_data := {
		"root": root,
		"type": type,
		"name": EVENT_NAMES[type],
		"pos": pos,
		"elapsed": 0.0,
		"duration": 45.0
	}

	match type:
		EventType.BUSKER:
			_build_busker_event(root)
			ev_data["duration"] = 55.0
		EventType.TOURIST_PHOTO:
			_build_tourist_photo_event(root)
			ev_data["duration"] = 35.0
		EventType.DELIVERY_UNLOAD:
			_build_delivery_event(root)
			ev_data["duration"] = 45.0
		EventType.BUS_BOARDING:
			_build_bus_boarding_event(root)
			ev_data["duration"] = 30.0
		EventType.FRIENDS_GREETING:
			_build_friends_greeting_event(root)
			ev_data["duration"] = 25.0
		EventType.DOG_WALKER:
			_build_dog_walker_event(root)
			ev_data["duration"] = 40.0
		EventType.TAXI_DROPOFF:
			_build_taxi_dropoff_event(root)
			ev_data["duration"] = 30.0
		EventType.NIGHTLIFE_EXIT:
			_build_nightlife_exit_event(root)
			ev_data["duration"] = 40.0

	active_events.append(ev_data)
	ambient_event_occurred.emit(EVENT_NAMES[type], district_id)


func _build_busker_event(root: Node3D) -> void:
	# Musician with acoustic guitar
	var busker := Art.person(root, Color("4a2810"))
	busker.position = Vector3(0, 0.15, 0)
	# Acoustic guitar body & neck
	var guitar_body := Art.box(busker, Vector3(0.12, 1.05, -0.22), Vector3(0.38, 0.45, 0.15), Color("c78a3b"))
	guitar_body.rotation.z = -0.3
	Art.cylinder(busker, Vector3(0.28, 1.35, -0.22), 0.03, 0.45, Color("4a2810")) # Neck
	
	# Open guitar case on footpath with coins
	Art.box(root, Vector3(0, 0.06, -0.8), Vector3(0.45, 0.12, 0.95), Color("151515"))
	# Coins in case
	for c in 3:
		Art.cylinder(root, Vector3(randf_range(-0.1, 0.1), 0.13, -0.8 + randf_range(-0.2, 0.2)), 0.03, 0.01, Color("f1c40f"))

	# Small crowd of 2-3 spectators watching
	for i in 2:
		var spec := Art.person(root, Color("34495e") if i == 0 else Color("27ae60"))
		var offset_x := -1.8 if i == 0 else 1.8
		spec.position = Vector3(offset_x, 0.15, -1.2)
		spec.rotation.y = atan2(-spec.position.x, -spec.position.z)

	Art.label(root, Vector3(0, 2.3, 0), "STREET BUSKER · LIVE ACOUSTIC", 14)


func _build_tourist_photo_event(root: Node3D) -> void:
	# Tourist 1: Posing for photo
	var poser := Art.person(root, Color("e67e22"))
	poser.position = Vector3(0, 0.15, -2.5)
	poser.rotation.y = PI
	# Sunhat
	Art.cylinder(poser, Vector3(0, 1.72, 0), 0.32, 0.06, Color("f5e6cb"))
	
	# Tourist 2: Holding camera aiming at poser
	var photographer := Art.person(root, Color("2980b9"))
	photographer.position = Vector3(0, 0.15, 2.0)
	# Camera in hands
	Art.box(photographer, Vector3(0, 1.45, -0.32), Vector3(0.18, 0.12, 0.1), Color("111111"))
	
	# Camera flash light
	var flash_light := OmniLight3D.new()
	flash_light.position = Vector3(0, 1.5, 1.6)
	flash_light.light_color = Color("ffffff")
	flash_light.light_energy = 0.0
	flash_light.omni_range = 10.0
	root.add_child(flash_light)

	# Flash tween trigger every 6 seconds
	var tween := create_tween().set_loops()
	tween.tween_interval(4.5)
	tween.tween_property(flash_light, "light_energy", 6.0, 0.05)
	tween.tween_property(flash_light, "light_energy", 0.0, 0.12)

	Art.label(root, Vector3(0, 2.2, 0), "TOURISTS · SNAPSHOT MOMENT", 14)


func _build_delivery_event(root: Node3D) -> void:
	# Parked delivery van (Toyota HiAce style)
	var van := Art.box(root, Vector3(0, 0.9, 0), Vector3(2.0, 1.9, 4.8), Color("f5f5f5"))
	# Courier in high-vis vest
	var courier := Art.person(root, Color("d35400")) # High-vis orange
	courier.position = Vector3(1.6, 0.15, 1.2)
	# Hand trolley with parcels
	var trolley := Art.box(root, Vector3(1.6, 0.35, 2.0), Vector3(0.6, 0.7, 0.8), Color("34495e"))
	Art.box(trolley, Vector3(0, 0.45, 0), Vector3(0.5, 0.4, 0.6), Color("bcaaa4")) # Parcel box
	
	Art.label(root, Vector3(0, 2.8, 0), "COURIER DELIVERY IN PROGRESS", 14)


func _build_bus_boarding_event(root: Node3D) -> void:
	# Sydney bus stopped at curb
	var bus := Art.box(root, Vector3(0, 1.5, 0), Vector3(2.5, 3.0, 10.0), Color("1565c0"))
	Art.box(bus, Vector3(0, 0.7, 0), Vector3(2.52, 1.0, 9.8), Color("263238")) # Window band
	
	# 2 Commuters in queue boarding front door
	var c1 := Art.person(root, Color("2c3e50"))
	c1.position = Vector3(1.6, 0.15, -3.2)
	c1.rotation.y = -PI * 0.5
	
	var c2 := Art.person(root, Color("7f8c8d"))
	c2.position = Vector3(1.6, 0.15, -2.0)
	c2.rotation.y = -PI * 0.5
	
	Art.label(root, Vector3(0, 3.6, 0), "PASSENGERS BOARDING BUS 333", 14)


func _build_friends_greeting_event(root: Node3D) -> void:
	# Two friends stopping to greet on footpath
	var f1 := Art.person(root, Color("27ae60"))
	f1.position = Vector3(-0.9, 0.15, 0)
	f1.rotation.y = PI * 0.5
	
	var f2 := Art.person(root, Color("e74c3c"))
	f2.position = Vector3(0.9, 0.15, 0)
	f2.rotation.y = -PI * 0.5

	# Raised waving arm on f1
	Art.box(f1, Vector3(0.25, 1.55, 0), Vector3(0.1, 0.4, 0.1), Color("27ae60"))

	Art.label(root, Vector3(0, 2.2, 0), "FRIENDS CROSSING PATHS", 14)


func _build_dog_walker_event(root: Node3D) -> void:
	# Person walking dog
	var walker := Art.person(root, Color("2980b9"))
	walker.position = Vector3(0, 0.15, 0)
	
	# Australian Kelpie / dog model
	var dog := Node3D.new()
	dog.name = "Dog"
	dog.position = Vector3(0.9, 0.0, -1.2)
	# Body
	Art.box(dog, Vector3(0, 0.38, 0), Vector3(0.32, 0.32, 0.75), Color("4a2810"))
	# Head & snout
	Art.box(dog, Vector3(0, 0.52, -0.38), Vector3(0.24, 0.22, 0.28), Color("3d1f08"))
	Art.box(dog, Vector3(0, 0.46, -0.54), Vector3(0.14, 0.14, 0.18), Color("151515")) # Snout
	# 4 legs
	for sx in [-0.12, 0.12]:
		for sz in [-0.25, 0.25]:
			Art.box(dog, Vector3(sx, 0.16, sz), Vector3(0.09, 0.34, 0.09), Color("4a2810"))
	# Tail
	var tail := Art.box(dog, Vector3(0, 0.48, 0.42), Vector3(0.08, 0.08, 0.3), Color("3d1f08"))
	tail.rotation.x = -0.4
	root.add_child(dog)

	# Leash (thin cylinder connecting walker's hand to dog collar)
	var leash := Art.cylinder(root, Vector3(0.5, 0.7, -0.6), 0.015, 1.4, Color("c0392b"))
	leash.rotation.x = 0.55
	leash.rotation.z = -0.4

	Art.label(root, Vector3(0, 2.2, 0), "WALKING THE DOG IN SYDNEY", 14)


func _build_taxi_dropoff_event(root: Node3D) -> void:
	# Sydney yellow taxi pulled to curb
	var cab := Art.box(root, Vector3(0, 0.7, 0), Vector3(1.9, 1.3, 4.6), Color("ffd600"))
	Art.box(cab, Vector3(0, 1.45, 0), Vector3(0.6, 0.16, 0.24), Color("ffffff")) # Roof sign
	# Passenger stepping out onto pavement
	var passenger := Art.person(root, Color("34495e"))
	passenger.position = Vector3(1.6, 0.15, 0.2)
	passenger.rotation.y = PI * 0.5

	Art.label(root, Vector3(0, 2.5, 0), "TAXI PASSENGER ARRIVAL", 14)


func _build_nightlife_exit_event(root: Node3D) -> void:
	# Lively group of 3 friends spilling onto pavement
	var p1 := Art.person(root, Color("8e44ad"))
	p1.position = Vector3(-0.9, 0.15, -0.4)
	
	var p2 := Art.person(root, Color("d35400"))
	p2.position = Vector3(0.4, 0.15, 0.3)
	
	var p3 := Art.person(root, Color("2c3e50"))
	p3.position = Vector3(1.2, 0.15, -0.6)

	Art.label(root, Vector3(0, 2.3, 0), "NIGHTLIFE VENUE CLOSING CROWD", 14)


func _get_player_district() -> String:
	if sydney_world != null and sydney_world.has_method("district_at") and player_ref != null:
		return str(sydney_world.call("district_at", player_ref.global_position.x, player_ref.global_position.z))
	return "cbd-core"


func _get_time_period() -> String:
	if time_manager != null and "current_period" in time_manager:
		return str(time_manager.get("current_period"))
	return "midday"


func _is_raining() -> bool:
	if weather_manager != null and "rain_intensity" in weather_manager:
		return float(weather_manager.get("rain_intensity")) > 0.2
	return false
