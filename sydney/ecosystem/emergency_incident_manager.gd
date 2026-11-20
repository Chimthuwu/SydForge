class_name EmergencyIncidentManager
extends Node3D

## Coordinates Sydney emergency service activities and ambient city incidents:
## police patrols, police foot patrols, ambulances, fire trucks,
## traffic collisions, vehicle breakdowns, roadworks, and public disturbances.

signal incident_started(incident_type: String, world_pos: Vector3)
signal incident_ended(incident_type: String)

enum IncidentType {
	COLLISION,
	BREAKDOWN,
	POLICE_ATTENDING,
	AMBULANCE_CALL,
	ROADWORKS,
	DISTURBANCE
}

const INCIDENT_NAMES := [
	"Minor Collision",
	"Vehicle Breakdown",
	"Police Incident",
	"Ambulance Responding",
	"Roadworks Obstruction",
	"Public Disturbance"
]

@export var max_active_incidents: int = 1
@export var incident_check_interval: float = 75.0

var active_incidents: Array[Dictionary] = []
var player_ref: Node3D
var sydney_world: SydneyWorld
var foot_patrol_officers: Array[Node3D] = []

var _timer: float = 15.0 # Initial incident delay
var _foot_patrol_timer: float = 0.0
var _patrol_intensity: float = 0.0
var _world_sim: Node = null


func _ready() -> void:
	add_to_group("incident_managers")


func setup(world: SydneyWorld, player: Node3D) -> void:
	sydney_world = world
	player_ref = player
	var sims := get_tree().get_nodes_in_group("world_simulation")
	_world_sim = sims[0] if not sims.is_empty() else null
	_spawn_police_foot_patrols()


## Requested by WorldSimulationDirector for gunfire, crimes and disturbances.
## A real AI police car is dispatched through TrafficManager; it joins the
## existing traffic simulation instead of being teleported to the scene.
func request_police_response(position: Vector3, severity: float = 1.0) -> void:
	var traffic_mgrs := get_tree().get_nodes_in_group("traffic_managers")
	if not traffic_mgrs.is_empty() and traffic_mgrs[0].has_method("request_emergency_response"):
		traffic_mgrs[0].call("request_emergency_response", position, "police")
	_spawn_foot_officers_near(position, 1 if severity < 1.5 else 2)


func set_patrol_intensity(value: float) -> void:
	_patrol_intensity = clampf(value, 0.0, 1.0)


func _spawn_foot_officers_near(position: Vector3, count: int) -> void:
	for i in count:
		var cop := Art.person(self, Color("152238"))
		cop.name = "RespondingOfficer"
		cop.position = position + Vector3(1.8 + i * 0.8, 0.2, -1.4 - i * 0.5)
		cop.add_to_group("police_foot_patrol")
		Art.box(cop, Vector3(0, 1.68, 0), Vector3(0.28, 0.12, 0.28), Color("101820"))
		foot_patrol_officers.append(cop)


func _process(delta: float) -> void:
	if player_ref == null:
		return

	_timer -= delta
	if _timer <= 0.0:
		_timer = incident_check_interval + randf_range(20.0, 70.0)
		_cull_distant_incidents()
		if active_incidents.size() < max_active_incidents and randf() < 0.6:
			_attempt_spawn_incident()

	_foot_patrol_timer += delta
	if _foot_patrol_timer >= 2.0:
		_foot_patrol_timer = 0.0
		_update_foot_patrols()


func _cull_distant_incidents() -> void:
	var p_pos := player_ref.global_position
	var i := active_incidents.size() - 1
	while i >= 0:
		var inc := active_incidents[i]
		var root: Node3D = inc["root"]
		var lifetime: float = inc.get("lifetime", 0.0) + 1.0
		inc["lifetime"] = lifetime
		
		# Despawn if older than 3 minutes or beyond 200m
		var dist := p_pos.distance_to(inc["pos"])
		if dist > 220.0 or lifetime > 180.0:
			if is_instance_valid(root):
				root.queue_free()
			active_incidents.remove_at(i)
			incident_ended.emit(str(inc["name"]))
		i -= 1


func _attempt_spawn_incident() -> void:
	if sydney_world == null or not ("data" in sydney_world):
		return
	
	var p_pos := player_ref.global_position
	var roads: Array = sydney_world.data.get("roads", [])
	if roads.is_empty():
		return

	# Find road segment 60m to 140m from player
	var candidates: Array = []
	for r in roads:
		var pts: Array = r.get("points", [])
		if pts.size() >= 2:
			var mid: Array = pts[pts.size() / 2]
			var pt_vec := Vector3(float(mid[0]), 0.2, float(mid[1]))
			var d := p_pos.distance_to(pt_vec)
			if d > 60.0 and d < 140.0:
				candidates.append({"road": r, "pos": pt_vec})
				if candidates.size() >= 20:
					break

	if candidates.is_empty():
		return

	var choice: Dictionary = candidates[randi() % candidates.size()]
	var inc_type := randi() % 6
	_create_incident(inc_type, choice["pos"], choice["road"])


func _create_incident(type: int, pos: Vector3, road_info: Dictionary) -> void:
	var root := Node3D.new()
	root.name = "Incident_" + str(type) + "_" + str(Time.get_ticks_msec())
	root.position = pos
	add_child(root)

	var inc_data := {
		"root": root,
		"type": type,
		"name": INCIDENT_NAMES[type],
		"pos": pos,
		"lifetime": 0.0
	}

	match type:
		IncidentType.COLLISION:
			_build_collision_incident(root)
		IncidentType.BREAKDOWN:
			_build_breakdown_incident(root)
		IncidentType.POLICE_ATTENDING:
			_build_police_incident(root)
		IncidentType.AMBULANCE_CALL:
			_build_ambulance_incident(root)
		IncidentType.ROADWORKS:
			_build_roadworks_incident(root)
		IncidentType.DISTURBANCE:
			_build_disturbance_incident(root)

	# Emergency scenes get a real responding vehicle from the traffic fleet.
	# It is created on a distant road segment and drives here through traffic.
	if type == IncidentType.POLICE_ATTENDING or type == IncidentType.DISTURBANCE:
		_request_responder(pos, "police")
	elif type == IncidentType.AMBULANCE_CALL:
		_request_responder(pos, "ambulance")
	elif type == IncidentType.COLLISION and randf() < 0.5:
		_request_responder(pos, "ambulance")

	active_incidents.append(inc_data)
	incident_started.emit(INCIDENT_NAMES[type], pos)


func _request_responder(position: Vector3, kind: String) -> void:
	var traffic_mgrs := get_tree().get_nodes_in_group("traffic_managers")
	if not traffic_mgrs.is_empty() and traffic_mgrs[0].has_method("request_emergency_response"):
		traffic_mgrs[0].call("request_emergency_response", position, kind)


func _build_collision_incident(root: Node3D) -> void:
	# Two vehicles stopped bumper-to-bumper with hazard lights
	var car1 := Art.box(root, Vector3(-1.2, 0.6, -1.8), Vector3(1.9, 1.2, 4.4), Color("34495e"))
	var car2 := Art.box(root, Vector3(-0.9, 0.6, 2.4), Vector3(1.85, 1.3, 4.2), Color("c0392b"))
	car2.rotation.y = 0.2
	
	# Hazard lights blinking
	_add_hazard_lights(root, Vector3(-1.2, 0.6, -1.8), 1.9, 4.4)
	_add_hazard_lights(root, Vector3(-0.9, 0.6, 2.4), 1.85, 4.2)

	# Drivers standing outside talking/gesturing
	var driver1 := Art.person(root, Color("2980b9"))
	driver1.position = Vector3(1.4, 0.15, 0.2)
	driver1.rotation.y = PI * 0.5
	
	var driver2 := Art.person(root, Color("8e44ad"))
	driver2.position = Vector3(1.4, 0.15, 1.6)
	driver2.rotation.y = -PI * 0.5
	


func _build_breakdown_incident(root: Node3D) -> void:
	# Broken down car at curb with open hood
	var car := Art.box(root, Vector3(0, 0.6, 0), Vector3(1.9, 1.2, 4.4), Color("7f8c8d"))
	# Raised bonnet / hood
	var hood := Art.box(root, Vector3(0, 1.35, -1.8), Vector3(1.6, 0.06, 1.2), Color("7f8c8d"))
	hood.rotation.x = 0.65
	
	# Hazard blinkers
	_add_hazard_lights(root, Vector3(0, 0.6, 0), 1.9, 4.4)

	# Driver on footpath on mobile phone
	var driver := Art.person(root, Color("d35400"))
	driver.position = Vector3(2.2, 0.15, -0.6)
	# Phone to ear
	Art.box(driver, Vector3(0.18, 1.55, -0.05), Vector3(0.08, 0.14, 0.04), Color("111111"))
	
	# Emergency hazard warning triangle on road behind car
	var tri := Art.cylinder(root, Vector3(0, 0.35, 6.0), 0.38, 0.05, Color("e74c3c"), 0.0)
	tri.rotation.x = PI * 0.5


func _build_police_incident(root: Node3D) -> void:
	# Parked police interceptor with flashing blue/red lights
	var police_car := Art.box(root, Vector3(0, 0.7, 0), Vector3(2.0, 1.3, 4.7), Color("f5f5f5"))
	Art.box(root, Vector3(-1.01, 0.7, 0), Vector3(0.02, 0.25, 4.0), Color("003399")) # Blue Battenburg
	Art.box(root, Vector3(1.01, 0.7, 0), Vector3(0.02, 0.25, 4.0), Color("003399"))
	
	# Flashing roof lightbar
	_add_flashing_emergency_lights(root, Vector3(0, 1.5, 0), true)

	# Two police officers questioning a pedestrian
	var cop1 := Art.person(root, Color("1a2530"))
	cop1.position = Vector3(2.2, 0.15, -0.8)
	cop1.rotation.y = PI * 0.4
	Art.box(cop1, Vector3(0, 1.68, 0), Vector3(0.28, 0.12, 0.28), Color("101820")) # Police cap
	
	var cop2 := Art.person(root, Color("1a2530"))
	cop2.position = Vector3(2.6, 0.15, 0.6)
	cop2.rotation.y = PI * 0.2
	
	var citizen := Art.person(root, Color("e67e22"))
	citizen.position = Vector3(3.4, 0.15, 0.0)
	citizen.rotation.y = -PI * 0.6
	


func _build_ambulance_incident(root: Node3D) -> void:
	# Ambulance parked with flashing lights
	var amb := Art.box(root, Vector3(0, 1.1, 0), Vector3(2.2, 2.2, 5.6), Color("fdfefe"))
	Art.box(root, Vector3(-1.11, 1.1, 0), Vector3(0.02, 0.35, 5.0), Color("c0392b"))
	Art.box(root, Vector3(1.11, 1.1, 0), Vector3(0.02, 0.35, 5.0), Color("c0392b"))
	_add_flashing_emergency_lights(root, Vector3(0, 2.3, -1.0), true)

	# Paramedics attending patient
	var med1 := Art.person(root, Color("27ae60")) # Paramedic green
	med1.position = Vector3(2.4, 0.15, 0.2)
	med1.rotation.y = PI * 0.5
	
	var patient := Art.box(root, Vector3(3.6, 0.25, 0.2), Vector3(0.6, 0.3, 1.8), Color("bdc3c7"))
	


func _build_roadworks_incident(root: Node3D) -> void:
	# Row of orange traffic cones and barriers blocking road lane
	for i in 6:
		var z_offset := -6.0 + i * 2.4
		var cone := Art.cylinder(root, Vector3(0, 0.45, z_offset), 0.24, 0.9, Color("e67e22"), 0.04)
		# Reflective white stripes
		Art.cylinder(cone, Vector3(0, 0.1, 0), 0.16, 0.2, Color("ffffff"), 0.1)

	# Flashing amber warning board
	var board := Art.box(root, Vector3(0, 1.6, -7.5), Vector3(2.0, 1.4, 0.15), Color("f39c12"))
	
	# Worker in high-vis
	var worker := Art.person(root, Color("f39c12"))
	worker.position = Vector3(1.6, 0.15, -2.0)
	Art.box(worker, Vector3(0, 1.72, 0), Vector3(0.3, 0.15, 0.3), Color("ffffff")) # Hard hat


func _build_disturbance_incident(root: Node3D) -> void:
	# Verbal confrontation on footpath
	var p1 := Art.person(root, Color("c0392b"))
	p1.position = Vector3(-0.8, 0.15, 0)
	p1.rotation.y = PI * 0.5
	
	var p2 := Art.person(root, Color("2980b9"))
	p2.position = Vector3(0.8, 0.15, 0)
	p2.rotation.y = -PI * 0.5

	# Bystander observing
	var bystander := Art.person(root, Color("7f8c8d"))
	bystander.position = Vector3(0.0, 0.15, 2.5)
	bystander.rotation.y = 0.0
	


func _add_hazard_lights(parent: Node3D, pos: Vector3, width: float, length: float) -> void:
	var l_flasher := OmniLight3D.new()
	l_flasher.position = pos + Vector3(-width * 0.5, 0.2, -length * 0.5)
	l_flasher.light_color = Color("ffaa00")
	l_flasher.omni_range = 8.0
	parent.add_child(l_flasher)

	var r_flasher := OmniLight3D.new()
	r_flasher.position = pos + Vector3(width * 0.5, 0.2, length * 0.5)
	r_flasher.light_color = Color("ffaa00")
	r_flasher.omni_range = 8.0
	parent.add_child(r_flasher)

	# Tween blink loop
	var tween := create_tween().set_loops().bind_node(parent)
	tween.tween_property(l_flasher, "light_energy", 3.0, 0.35)
	tween.parallel().tween_property(r_flasher, "light_energy", 3.0, 0.35)
	tween.tween_property(l_flasher, "light_energy", 0.0, 0.35)
	tween.parallel().tween_property(r_flasher, "light_energy", 0.0, 0.35)


func _add_flashing_emergency_lights(parent: Node3D, pos: Vector3, is_police: bool) -> void:
	var red := OmniLight3D.new()
	red.position = pos + Vector3(0.6, 0.2, 0)
	red.light_color = Color("ff1111")
	red.omni_range = 10.0
	parent.add_child(red)

	var blue := OmniLight3D.new()
	blue.position = pos + Vector3(-0.6, 0.2, 0)
	blue.light_color = Color("0044ff") if is_police else Color("ff1111")
	blue.omni_range = 10.0
	parent.add_child(blue)

	var tween := create_tween().set_loops().bind_node(parent)
	tween.tween_property(red, "light_energy", 2.2, 0.14)
	tween.parallel().tween_property(blue, "light_energy", 0.1, 0.14)
	tween.tween_property(red, "light_energy", 0.1, 0.14)
	tween.parallel().tween_property(blue, "light_energy", 2.2, 0.14)


func _spawn_police_foot_patrols() -> void:
	# Occasional ambient foot patrol presence in a few key areas (not every street).
	var patrol_spots := [
		Vector3(200.0, 0.2, -1480.0), # Circular Quay
		Vector3(-120.0, 0.2, -30.0),  # Town Hall / CBD
		Vector3(1490.0, 0.2, 80.0),   # Kings Cross
	]
	
	for i in patrol_spots.size():
		var spot: Vector3 = patrol_spots[i]
		# Single officer at most spots, pair only occasionally in nightlife area.
		var count := 1
		if i == 2 and randf() < 0.35:
			count = 2
		for j in count:
			var offset := Vector3(-0.6, 0, 0) if j == 0 else Vector3(0.6, 0, 0)
			var cop := Art.person(self, Color("152238"))
			cop.position = spot + offset
			cop.add_to_group("police_foot_patrol")
			Art.box(cop, Vector3(0, 1.68, 0), Vector3(0.28, 0.12, 0.28), Color("101820"))
			# Police radio and duty belt
			Art.box(cop, Vector3(0.18, 1.1, -0.1), Vector3(0.08, 0.16, 0.06), Color("050505"))
			foot_patrol_officers.append(cop)


func _update_foot_patrols() -> void:
	# Subtle patrol patrol pace / sway
	for cop in foot_patrol_officers:
		if is_instance_valid(cop):
			cop.rotate_y(randf_range(-0.15, 0.15))
