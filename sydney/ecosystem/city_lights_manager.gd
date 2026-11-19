class_name CityLightsManager
extends Node3D

## Controls city night lighting:
## - Streetlights along major Sydney avenues and footpaths
## - Harbour Bridge architectural floodlights
## - Opera House monumental illumination
## - Building window and shopfront emissives

var streetlights: Array[Node3D] = []
var street_spotlights: Array[SpotLight3D] = []
var landmark_lights: Array[OmniLight3D] = []

var is_night: bool = false
var sydney_world: SydneyWorld

func _ready() -> void:
	add_to_group("city_lights")
	var time_mgrs := get_tree().get_nodes_in_group("time_managers")
	if not time_mgrs.is_empty():
		var tm = time_mgrs[0]
		is_night = tm.is_night
		tm.night_mode_changed.connect(_on_night_mode_changed)

func setup(world: SydneyWorld) -> void:
	sydney_world = world
	_generate_streetlights()
	_setup_landmark_illumination()
	_apply_night_state(is_night)

func _on_night_mode_changed(night: bool) -> void:
	is_night = night
	_apply_night_state(night)

func _generate_streetlights() -> void:
	if sydney_world == null or not ("data" in sydney_world):
		return
	
	# Sample primary and secondary roads to place streetlights every ~40m
	var roads: Array = sydney_world.data.get("roads", [])
	var lamp_count := 0
	for r in roads:
		var hw: String = r.get("highway", "")
		if hw in ["primary", "secondary", "tertiary", "trunk"]:
			var pts: Array = r.get("points", [])
			if pts.size() >= 2:
				var p1 := Vector3(float(pts[0][0]), 0.0, float(pts[0][1]))
				var p2 := Vector3(float(pts[-1][0]), 0.0, float(pts[-1][1]))
				if p1.distance_to(p2) > 30.0:
					_create_street_lamp(p1 + Vector3(4.0, 0, 0))
					_create_street_lamp(p2 + Vector3(-4.0, 0, 0))
					lamp_count += 2
					if lamp_count > 120: # Cap for optimal performance
						break

func _create_street_lamp(pos: Vector3) -> void:
	var lamp_node := Node3D.new()
	lamp_node.position = pos
	add_child(lamp_node)
	
	# Pole (dark metal)
	Art.cylinder(lamp_node, Vector3(0, 3.2, 0), 0.08, 6.4, Color("2d3748"))
	# Arm extending over road
	Art.box(lamp_node, Vector3(0.6, 6.3, 0), Vector3(1.4, 0.1, 0.1), Color("2d3748"))
	# Lantern head
	var bulb := Art.box(lamp_node, Vector3(1.2, 6.15, 0), Vector3(0.4, 0.15, 0.25), Color("fff3cf"))
	streetlights.append(bulb)
	
	# Lightweight SpotLight down towards the asphalt
	var spot := SpotLight3D.new()
	spot.position = Vector3(1.2, 6.0, 0)
	spot.rotation_degrees = Vector3(-90, 0, 0)
	spot.spot_range = 16.0
	spot.spot_angle = 45.0
	spot.light_color = Color("ffe0b2") # Warm high-pressure sodium street glow
	spot.light_energy = 0.0 # Toggled dynamically at night
	spot.shadow_enabled = false
	lamp_node.add_child(spot)
	street_spotlights.append(spot)

func _setup_landmark_illumination() -> void:
	# Sydney Harbour Bridge arch floodlights
	var bridge_pos := Vector3(290.0, 18.0, -1880.0)
	var bl := OmniLight3D.new()
	bl.position = bridge_pos
	bl.omni_range = 140.0
	bl.light_color = Color("fff3e0")
	bl.light_energy = 0.0
	add_child(bl)
	landmark_lights.append(bl)
	
	# Sydney Opera House architectural illumination (golden/warm white wash)
	var opera_pos := Vector3(658.7, 12.0, -1763.8)
	var ol := OmniLight3D.new()
	ol.position = opera_pos
	ol.omni_range = 160.0
	ol.light_color = Color("fff5e0")
	ol.light_energy = 0.0
	add_child(ol)
	landmark_lights.append(ol)

func _apply_night_state(night: bool) -> void:
	# Toggle streetlight bulbs emissive material
	for bulb in streetlights:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color("fff3cf")
		mat.emission_enabled = night
		mat.emission = Color("ffcc66")
		mat.emission_energy_multiplier = 3.0 if night else 0.0
		bulb.material_override = mat
	
	# Toggle spotlights
	for spot in street_spotlights:
		spot.light_energy = 1.6 if night else 0.0
	
	# Toggle landmark floodlights
	for ll in landmark_lights:
		ll.light_energy = 2.2 if night else 0.0
