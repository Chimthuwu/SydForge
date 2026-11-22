class_name VehicleVisualBuilder
extends RefCounted

## Builds visual meshes, cabins, wheels, headlights and tail lights for all Sydney vehicle types.

enum VehicleClass {
	SEDAN,
	SPORTS,
	HATCHBACK,
	SUV_4WD,
	UTE,
	DELIVERY_VAN,
	BOX_TRUCK,
	SEMI_TRAILER,
	GARBAGE_TRUCK,
	TAXI,
	BUS,
	MOTORBIKE,
	SCOOTER,
	POLICE,
	AMBULANCE,
	FIRE_TRUCK,
	SUPERCAR,
	MUSCLE,
	PERFORMANCE_SEDAN,
	COUPE,
	ROADSTER,
	HYPERCAR,
	TRACK_CAR
}

static func get_class_specs(vclass: int) -> Dictionary:
	match vclass:
		VehicleClass.SEDAN:
			return {
				"name": "COMMODORE · SEDAN",
				"length": 4.5, "width": 1.9, "height": 1.4,
				"wheel_radius": 0.34, "wheel_width": 0.22,
				"max_speed": 34.0, "accel": 19.0, "turn": 2.2, "mass": 1500.0,
				"lanes": ["all"]
			}
		VehicleClass.SPORTS:
			return {
				"name": "VIPER · SPORT",
				"length": 4.3, "width": 2.0, "height": 1.25,
				"wheel_radius": 0.33, "wheel_width": 0.26,
				"max_speed": 44.0, "accel": 26.0, "turn": 2.5, "mass": 1300.0,
				"lanes": ["all"]
			}
		VehicleClass.HATCHBACK:
			return {
				"name": "COROLLA · HATCH",
				"length": 3.8, "width": 1.75, "height": 1.4,
				"wheel_radius": 0.30, "wheel_width": 0.18,
				"max_speed": 30.0, "accel": 17.0, "turn": 2.4, "mass": 1200.0,
				"lanes": ["all"]
			}
		VehicleClass.SUV_4WD:
			return {
				"name": "LANDCRUISER · 4WD",
				"length": 4.8, "width": 2.05, "height": 1.85,
				"wheel_radius": 0.42, "wheel_width": 0.28,
				"max_speed": 31.0, "accel": 16.0, "turn": 1.9, "mass": 2300.0,
				"lanes": ["all"]
			}
		VehicleClass.UTE:
			return {
				"name": "FALCON · AUSSIE UTE",
				"length": 4.9, "width": 1.9, "height": 1.5,
				"wheel_radius": 0.36, "wheel_width": 0.24,
				"max_speed": 35.0, "accel": 20.0, "turn": 2.1, "mass": 1650.0,
				"lanes": ["all"]
			}
		VehicleClass.DELIVERY_VAN:
			return {
				"name": "HIACE · DELIVERY VAN",
				"length": 5.1, "width": 2.0, "height": 2.1,
				"wheel_radius": 0.36, "wheel_width": 0.22,
				"max_speed": 28.0, "accel": 14.0, "turn": 1.8, "mass": 2100.0,
				"lanes": ["all"]
			}
		VehicleClass.BOX_TRUCK:
			return {
				"name": "ISUZU · BOX TRUCK",
				"length": 7.2, "width": 2.4, "height": 3.1,
				"wheel_radius": 0.48, "wheel_width": 0.30,
				"max_speed": 24.0, "accel": 10.0, "turn": 1.4, "mass": 5500.0,
				"lanes": ["arterial", "secondary", "primary", "trunk"]
			}
		VehicleClass.SEMI_TRAILER:
			return {
				"name": "MACK · SEMI-TRAILER",
				"length": 12.0, "width": 2.5, "height": 3.6,
				"wheel_radius": 0.52, "wheel_width": 0.32,
				"max_speed": 22.0, "accel": 8.0, "turn": 1.0, "mass": 14000.0,
				"lanes": ["arterial", "primary", "trunk", "motorway"]
			}
		VehicleClass.GARBAGE_TRUCK:
			return {
				"name": "CITY · RUBBISH TRUCK",
				"length": 7.8, "width": 2.5, "height": 3.2,
				"wheel_radius": 0.50, "wheel_width": 0.30,
				"max_speed": 22.0, "accel": 9.0, "turn": 1.3, "mass": 7000.0,
				"lanes": ["all"]
			}
		VehicleClass.TAXI:
			return {
				"name": "SYDNEY CAB · TAXI",
				"length": 4.6, "width": 1.85, "height": 1.45,
				"wheel_radius": 0.34, "wheel_width": 0.20,
				"max_speed": 33.0, "accel": 18.0, "turn": 2.3, "mass": 1500.0,
				"lanes": ["all"]
			}
		VehicleClass.BUS:
			return {
				"name": "STATE TRANSIT · SYDNEY BUS",
				"length": 11.5, "width": 2.55, "height": 3.2,
				"wheel_radius": 0.50, "wheel_width": 0.32,
				"max_speed": 25.0, "accel": 11.0, "turn": 1.3, "mass": 9500.0,
				"lanes": ["arterial", "secondary", "primary", "trunk"]
			}
		VehicleClass.MOTORBIKE:
			return {
				"name": "POSTIE / ROAD · MOTORBIKE",
				"length": 2.2, "width": 0.75, "height": 1.2,
				"wheel_radius": 0.32, "wheel_width": 0.12,
				"max_speed": 40.0, "accel": 28.0, "turn": 3.2, "mass": 220.0,
				"lanes": ["all"]
			}
		VehicleClass.SCOOTER:
			return {
				"name": "CITY · SCOOTER",
				"length": 1.8, "width": 0.65, "height": 1.1,
				"wheel_radius": 0.22, "wheel_width": 0.10,
				"max_speed": 25.0, "accel": 15.0, "turn": 3.6, "mass": 110.0,
				"lanes": ["all"]
			}
		VehicleClass.POLICE:
			return {
				"name": "NSW POLICE · HIGHWAY PATROL",
				"length": 4.85, "width": 1.95, "height": 1.5,
				"wheel_radius": 0.35, "wheel_width": 0.24,
				"max_speed": 44.0, "accel": 26.0, "turn": 2.4, "mass": 1750.0,
				"lanes": ["all"]
			}
		VehicleClass.AMBULANCE:
			return {
				"name": "NSW AMBULANCE · MOBILE ICU",
				"length": 5.8, "width": 2.15, "height": 2.5,
				"wheel_radius": 0.38, "wheel_width": 0.24,
				"max_speed": 34.0, "accel": 18.0, "turn": 1.9, "mass": 3200.0,
				"lanes": ["all"]
			}
		VehicleClass.FIRE_TRUCK:
			return {
				"name": "FIRE & RESCUE NSW · PUMPER",
				"length": 8.8, "width": 2.55, "height": 3.4,
				"wheel_radius": 0.52, "wheel_width": 0.32,
				"max_speed": 26.0, "accel": 12.0, "turn": 1.3, "mass": 11000.0,
				"lanes": ["arterial", "secondary", "primary", "trunk"]
			}
		VehicleClass.SUPERCAR:
			return {
				"name": "VELOCITY · SUPERCAR",
				"length": 4.5, "width": 2.05, "height": 1.05,
				"wheel_radius": 0.36, "wheel_width": 0.30,
				"max_speed": 62.0, "accel": 40.0, "turn": 2.7, "mass": 1280.0,
				"lanes": ["all"]
			}
		VehicleClass.MUSCLE:
			return {
				"name": "COMMODORE · MUSCLE",
				"length": 4.9, "width": 2.0, "height": 1.35,
				"wheel_radius": 0.38, "wheel_width": 0.28,
				"max_speed": 52.0, "accel": 32.0, "turn": 2.1, "mass": 1650.0,
				"lanes": ["all"]
			}
		VehicleClass.PERFORMANCE_SEDAN:
			return {
				"name": "SPORT · PERFORMANCE SEDAN",
				"length": 4.8, "width": 1.95, "height": 1.38,
				"wheel_radius": 0.36, "wheel_width": 0.25,
				"max_speed": 50.0, "accel": 30.0, "turn": 2.35, "mass": 1550.0,
				"lanes": ["all"]
			}
		VehicleClass.COUPE:
			return {
				"name": "HERON · COUPE",
				"length": 4.4, "width": 1.9, "height": 1.25,
				"wheel_radius": 0.34, "wheel_width": 0.24,
				"max_speed": 48.0, "accel": 28.0, "turn": 2.5, "mass": 1380.0,
				"lanes": ["all"]
			}
		VehicleClass.ROADSTER:
			return {
				"name": "STING · ROADSTER",
				"length": 4.2, "width": 1.88, "height": 1.12,
				"wheel_radius": 0.34, "wheel_width": 0.26,
				"max_speed": 54.0, "accel": 34.0, "turn": 2.75, "mass": 1150.0,
				"lanes": ["all"]
			}
		VehicleClass.HYPERCAR:
			return {
				"name": "PHANTOM · HYPERCAR",
				"length": 4.7, "width": 2.12, "height": 0.98,
				"wheel_radius": 0.36, "wheel_width": 0.32,
				"max_speed": 70.0, "accel": 46.0, "turn": 2.85, "mass": 1240.0,
				"lanes": ["all"]
			}
		VehicleClass.TRACK_CAR:
			return {
				"name": "APEX · TRACK SPECIAL",
				"length": 4.35, "width": 2.05, "height": 1.08,
				"wheel_radius": 0.35, "wheel_width": 0.30,
				"max_speed": 58.0, "accel": 42.0, "turn": 3.0, "mass": 980.0,
				"lanes": ["all"]
			}
		_:
			return get_class_specs(VehicleClass.SEDAN)

static func build_vehicle_visuals(root: Node3D, vclass: int, paint_color: Color) -> Dictionary:
	var spec := get_class_specs(vclass)
	var body_art := Node3D.new()
	body_art.name = "BodyArt"
	root.add_child(body_art)
	
	var wheels: Array[MeshInstance3D] = []
	var headlights: Array[MeshInstance3D] = []
	var taillights: Array[MeshInstance3D] = []
	var emergency_lights: Array[MeshInstance3D] = []
	var emergency_light_nodes: Array[OmniLight3D] = []
	var light_nodes: Array[SpotLight3D] = []
	
	var L: float = spec["length"]
	var W: float = spec["width"]
	var H: float = spec["height"]
	var wr: float = spec["wheel_radius"]
	var ww: float = spec["wheel_width"]
	var half_l := L * 0.5
	var half_w := W * 0.5
	
	# Match styling based on vehicle class
	match vclass:
		VehicleClass.MOTORBIKE, VehicleClass.SCOOTER:
			# Single track 2-wheel vehicle
			var frame_col := Color("1e2229")
			# Main chassis
			Art.box(body_art, Vector3(0, wr + 0.35, 0), Vector3(W * 0.45, 0.4, L * 0.6), frame_col)
			# Tank / bodywork
			Art.box(body_art, Vector3(0, wr + 0.55, -0.1), Vector3(W * 0.6, 0.3, L * 0.35), paint_color)
			# Handlebars
			Art.box(body_art, Vector3(0, wr + 0.85, -half_l * 0.55), Vector3(W * 0.9, 0.06, 0.06), frame_col)
			# Headlight
			var hl := Art.box(body_art, Vector3(0, wr + 0.75, -half_l * 0.7), Vector3(0.2, 0.2, 0.05), Color("fff8d6"))
			headlights.append(hl)
			# Taillight
			var tl := Art.box(body_art, Vector3(0, wr + 0.55, half_l * 0.7), Vector3(0.18, 0.12, 0.05), Color("cc1111"))
			taillights.append(tl)
			# Wheels: front and rear along center line
			var front_wheel := _make_wheel(body_art, Vector3(0, wr, -half_l * 0.7), wr, ww)
			var rear_wheel := _make_wheel(body_art, Vector3(0, wr, half_l * 0.7), wr, ww)
			wheels.append(front_wheel)
			wheels.append(rear_wheel)

		VehicleClass.BUS:
			# Sydney State Transit Bus (Classic blue & white or yellow & blue)
			var bus_paint := Color("1565c0") # Sydney bus blue
			var bus_roof := Color("f5f7fa") # White roof
			# Lower body
			Art.box(body_art, Vector3(0, wr + 0.7, 0), Vector3(W, 1.2, L), bus_paint)
			# Upper windows / roof
			Art.box(body_art, Vector3(0, wr + 1.8, 0), Vector3(W * 0.96, 1.0, L * 0.96), Color("263238")) # Window band
			Art.box(body_art, Vector3(0, wr + 2.4, 0), Vector3(W, 0.25, L), bus_roof)
			# Destination display
			Art.box(body_art, Vector3(0, wr + 2.2, -half_l + 0.02), Vector3(W * 0.7, 0.3, 0.05), Color("ffaa00"))
			Art.label(body_art, Vector3(0, wr + 2.22, -half_l + 0.06), "333 BONDI / CIRCULAR QUAY", 12)
			# Lights
			_add_standard_lights(body_art, half_w * 0.8, wr + 0.5, half_l, headlights, taillights)
			# 6 wheels (front pair, double rear axles)
			wheels.append(_make_wheel(body_art, Vector3(-half_w, wr, -half_l * 0.65), wr, ww))
			wheels.append(_make_wheel(body_art, Vector3(half_w, wr, -half_l * 0.65), wr, ww))
			wheels.append(_make_wheel(body_art, Vector3(-half_w, wr, half_l * 0.5), wr, ww))
			wheels.append(_make_wheel(body_art, Vector3(half_w, wr, half_l * 0.5), wr, ww))
			wheels.append(_make_wheel(body_art, Vector3(-half_w, wr, half_l * 0.75), wr, ww))
			wheels.append(_make_wheel(body_art, Vector3(half_w, wr, half_l * 0.75), wr, ww))

		VehicleClass.UTE:
			# Classic Aussie Ute (Front coupe cabin, rear open flatbed)
			var cab_len := L * 0.48
			var bed_len := L * 0.46
			# Lower body skirt
			Art.box(body_art, Vector3(0, wr + 0.35, 0), Vector3(W, 0.65, L), paint_color)
			# Front hood
			Art.box(body_art, Vector3(0, wr + 0.72, -half_l * 0.55), Vector3(W * 0.95, 0.15, cab_len * 0.9), paint_color)
			# Cabin
			Art.tapered_box(body_art, Vector3(0, wr + 0.95, -0.2), Vector3(W * 0.88, 0.65, cab_len * 0.75), Vector2(W * 0.75, cab_len * 0.55), Color("2b3a4a"))
			# Aussie tray sides & rollbar
			Art.box(body_art, Vector3(-half_w + 0.08, wr + 0.75, half_l * 0.45), Vector3(0.12, 0.35, bed_len), Color("718096"))
			Art.box(body_art, Vector3(half_w - 0.08, wr + 0.75, half_l * 0.45), Vector3(0.12, 0.35, bed_len), Color("718096"))
			Art.box(body_art, Vector3(0, wr + 0.75, half_l - 0.06), Vector3(W - 0.2, 0.35, 0.12), Color("718096"))
			# Bullbar on front
			Art.box(body_art, Vector3(0, wr + 0.45, -half_l - 0.08), Vector3(W * 0.9, 0.5, 0.15), Color("202020"))
			# Lights & wheels
			_add_standard_lights(body_art, half_w * 0.78, wr + 0.45, half_l, headlights, taillights)
			_add_four_wheels(body_art, half_w, wr, ww, half_l * 0.62, wheels)

		VehicleClass.BOX_TRUCK, VehicleClass.SEMI_TRAILER, VehicleClass.GARBAGE_TRUCK:
			# Heavy truck chassis + front cab + rear cargo box
			var cab_len := 2.2
			var cab_col := paint_color if vclass != VehicleClass.GARBAGE_TRUCK else Color("2e7d32")
			var cargo_col := Color("e2e8f0") if vclass == VehicleClass.BOX_TRUCK else (Color("37474f") if vclass == VehicleClass.GARBAGE_TRUCK else Color("b0bec5"))
			# Cab
			Art.box(body_art, Vector3(0, wr + 1.1, -half_l + cab_len * 0.5), Vector3(W * 0.95, 1.8, cab_len), cab_col)
			# Windshield
			Art.box(body_art, Vector3(0, wr + 1.4, -half_l + 0.1), Vector3(W * 0.85, 0.8, 0.2), Color("1e293b"))
			# Rear Box / Trailer
			var box_len := L - cab_len - 0.5
			var box_z := half_l - box_len * 0.5
			Art.box(body_art, Vector3(0, wr + H * 0.5, box_z), Vector3(W, H - wr, box_len), cargo_col)
			if vclass == VehicleClass.GARBAGE_TRUCK:
				# Compactor bin hopper rear detail
				Art.box(body_art, Vector3(0, wr + 0.8, half_l + 0.3), Vector3(W * 0.9, 1.2, 0.8), Color("1b5e20"))
				Art.label(body_art, Vector3(0, wr + 1.8, box_z), "CITY OF SYDNEY\nWASTE SERVICES", 18)
			# Lights & wheels
			_add_standard_lights(body_art, half_w * 0.8, wr + 0.5, half_l, headlights, taillights)
			# Front axle + rear tandem axles
			wheels.append(_make_wheel(body_art, Vector3(-half_w, wr, -half_l + 1.0), wr, ww))
			wheels.append(_make_wheel(body_art, Vector3(half_w, wr, -half_l + 1.0), wr, ww))
			wheels.append(_make_wheel(body_art, Vector3(-half_w, wr, half_l - 2.2), wr, ww))
			wheels.append(_make_wheel(body_art, Vector3(half_w, wr, half_l - 2.2), wr, ww))
			wheels.append(_make_wheel(body_art, Vector3(-half_w, wr, half_l - 0.8), wr, ww))
			wheels.append(_make_wheel(body_art, Vector3(half_w, wr, half_l - 0.8), wr, ww))

		VehicleClass.TAXI:
			# Sydney Taxi (Yellow/silver body with roof taxi light dome)
			var taxi_paint := Color("ffd600") # Vivid Sydney taxi yellow
			Art.box(body_art, Vector3(0, wr + 0.35, 0), Vector3(W, 0.6, L), taxi_paint)
			Art.tapered_box(body_art, Vector3(0, wr + 0.95, 0.1), Vector3(W * 0.88, 0.65, L * 0.55), Vector2(W * 0.72, L * 0.4), Color("2b3a4a"))
			# Taxi roof sign
			var sign := Art.box(body_art, Vector3(0, wr + 1.35, 0.1), Vector3(0.65, 0.16, 0.25), Color("ffffff"))
			headlights.append(sign) # illuminated roof dome at night
			Art.label(body_art, Vector3(0, wr + 1.35, 0.1), "TAXI", 12)
			_add_standard_lights(body_art, half_w * 0.78, wr + 0.4, half_l, headlights, taillights)
			_add_four_wheels(body_art, half_w, wr, ww, half_l * 0.62, wheels)

		VehicleClass.POLICE:
			# NSW Police Highway Patrol Sedan
			var base_paint := Color("f4f4f4")
			Art.box(body_art, Vector3(0, wr + 0.35, 0), Vector3(W, 0.6, L), base_paint)
			Art.tapered_box(body_art, Vector3(0, wr + 0.95, 0.1), Vector3(W * 0.88, 0.65, L * 0.55), Vector2(W * 0.72, L * 0.4), Color("1e293b"))
			# Blue & white Battenburg checkers along sides
			Art.box(body_art, Vector3(-half_w - 0.01, wr + 0.45, 0), Vector3(0.02, 0.22, L * 0.85), Color("003399"))
			Art.box(body_art, Vector3(half_w + 0.01, wr + 0.45, 0), Vector3(0.02, 0.22, L * 0.85), Color("003399"))
			Art.label(body_art, Vector3(-half_w - 0.03, wr + 0.45, 0), "POLICE", 10)
			Art.label(body_art, Vector3(half_w + 0.03, wr + 0.45, 0), "POLICE", 10)
			# Emergency Lightbar on roof
			_build_emergency_lightbar(body_art, Vector3(0, wr + 1.35, 0.1), W * 0.75, emergency_lights, emergency_light_nodes, true)
			_add_standard_lights(body_art, half_w * 0.78, wr + 0.4, half_l, headlights, taillights)
			_add_four_wheels(body_art, half_w, wr, ww, half_l * 0.62, wheels)

		VehicleClass.AMBULANCE:
			# NSW Ambulance Van
			var amb_paint := Color("f8f9fa")
			Art.box(body_art, Vector3(0, wr + 0.7, 0), Vector3(W, 1.4, L), amb_paint)
			Art.box(body_art, Vector3(0, wr + 1.3, -half_l * 0.35), Vector3(W * 0.92, 0.8, L * 0.4), Color("1e293b"))
			# Red & white / neon checker tape
			Art.box(body_art, Vector3(-half_w - 0.01, wr + 0.7, 0), Vector3(0.02, 0.28, L * 0.9), Color("cc1111"))
			Art.box(body_art, Vector3(half_w + 0.01, wr + 0.7, 0), Vector3(0.02, 0.28, L * 0.9), Color("cc1111"))
			Art.label(body_art, Vector3(-half_w - 0.03, wr + 0.7, 0), "AMBULANCE", 10)
			Art.label(body_art, Vector3(half_w + 0.03, wr + 0.7, 0), "AMBULANCE", 10)
			_build_emergency_lightbar(body_art, Vector3(0, wr + 2.15, -half_l * 0.35), W * 0.75, emergency_lights, emergency_light_nodes, true)
			_add_standard_lights(body_art, half_w * 0.8, wr + 0.5, half_l, headlights, taillights)
			_add_four_wheels(body_art, half_w, wr, ww, half_l * 0.65, wheels)

		VehicleClass.FIRE_TRUCK:
			# Fire & Rescue NSW Pumper Truck
			var fire_red := Color("b71c1c")
			Art.box(body_art, Vector3(0, wr + 1.1, -half_l + 1.2), Vector3(W * 0.96, 2.0, 2.4), fire_red) # Cab
			Art.box(body_art, Vector3(0, wr + 1.4, -half_l + 0.1), Vector3(W * 0.88, 0.9, 0.2), Color("1e293b")) # Windshield
			# Rear body with roller equipment shutters
			var body_len := L - 2.8
			Art.box(body_art, Vector3(0, wr + 1.2, half_l - body_len * 0.5), Vector3(W, 2.2, body_len), fire_red)
			Art.box(body_art, Vector3(-half_w - 0.01, wr + 1.1, half_l - body_len * 0.5), Vector3(0.02, 1.4, body_len * 0.85), Color("cfd8dc")) # Shutter
			Art.box(body_art, Vector3(half_w + 0.01, wr + 1.1, half_l - body_len * 0.5), Vector3(0.02, 1.4, body_len * 0.85), Color("cfd8dc")) # Shutter
			# Ladders on roof
			Art.box(body_art, Vector3(0.5, wr + 2.4, half_l - body_len * 0.5), Vector3(0.35, 0.25, body_len * 0.9), Color("e0e0e0"))
			Art.label(body_art, Vector3(0, wr + 1.8, half_l - body_len * 0.5), "FIRE & RESCUE NSW", 14)
			_build_emergency_lightbar(body_art, Vector3(0, wr + 2.25, -half_l + 1.2), W * 0.8, emergency_lights, emergency_light_nodes, false) # Red/red
			_add_standard_lights(body_art, half_w * 0.82, wr + 0.6, half_l, headlights, taillights)
			# 6 wheels
			wheels.append(_make_wheel(body_art, Vector3(-half_w, wr, -half_l + 1.2), wr, ww))
			wheels.append(_make_wheel(body_art, Vector3(half_w, wr, -half_l + 1.2), wr, ww))
			wheels.append(_make_wheel(body_art, Vector3(-half_w, wr, half_l - 2.4), wr, ww))
			wheels.append(_make_wheel(body_art, Vector3(half_w, wr, half_l - 2.4), wr, ww))
			wheels.append(_make_wheel(body_art, Vector3(-half_w, wr, half_l - 0.9), wr, ww))
			wheels.append(_make_wheel(body_art, Vector3(half_w, wr, half_l - 0.9), wr, ww))

		VehicleClass.SUPERCAR, VehicleClass.MUSCLE, VehicleClass.PERFORMANCE_SEDAN, VehicleClass.COUPE:
			# Distinct performance silhouettes: low wedge supercar, long-bonnet
			# muscle car, compact performance sedan and coupe.
			var low := vclass == VehicleClass.SUPERCAR
			var body_h := 0.48 if low else 0.62
			Art.box(body_art, Vector3(0, wr + body_h * 0.5, 0), Vector3(W, body_h, L), paint_color)
			var cab_h := 0.38 if low else (0.58 if vclass == VehicleClass.MUSCLE else 0.5)
			var cab_z := 0.35 if vclass == VehicleClass.MUSCLE else 0.05
			Art.tapered_box(body_art, Vector3(0, wr + body_h + cab_h * 0.5, cab_z),
				Vector3(W * 0.86, cab_h, L * 0.42), Vector2(W * 0.70, L * 0.32), Color("162431"))
			if low:
				Art.box(body_art, Vector3(0.0, wr + 0.06, -half_l - 0.05), Vector3(W * 0.9, 0.10, 0.3), Color("1b1f24"))
				Art.box(body_art, Vector3(0.0, wr + body_h + 0.16, half_l * 0.55), Vector3(W * 0.8, 0.08, 0.5), Color("1b1f24"))
			elif vclass == VehicleClass.MUSCLE:
				Art.box(body_art, Vector3(0.0, wr + 0.62, -half_l * 0.55), Vector3(W * 0.95, 0.14, L * 0.35), paint_color)
			_add_standard_lights(body_art, half_w * 0.8, wr + 0.35, half_l, headlights, taillights)
			_add_four_wheels(body_art, half_w, wr, ww, half_l * 0.62, wheels)

		VehicleClass.ROADSTER:
			# Open two-seater: low tub, tapered nose, seats and roll hoops exposed.
			var tub_h := 0.42
			Art.box(body_art, Vector3(0, wr + tub_h * 0.5, 0.15), Vector3(W, tub_h, L * 0.86), paint_color)
			Art.tapered_box(body_art, Vector3(0, wr + tub_h * 0.5, -half_l * 0.72),
				Vector3(W * 0.94, tub_h, L * 0.38), Vector2(W * 0.58, 0.3), paint_color)
			Art.box(body_art, Vector3(0, wr + tub_h + 0.02, 0.42), Vector3(W * 0.62, 0.18, L * 0.26), Color("141a20"))
			for side in [-1.0, 1.0]:
				Art.box(body_art, Vector3(side * W * 0.16, wr + tub_h + 0.12, 0.52), Vector3(W * 0.20, 0.16, L * 0.12), Color("2a2228"))
				Art.box(body_art, Vector3(side * W * 0.20, wr + tub_h + 0.28, 0.68), Vector3(0.12, 0.26, 0.12), Color("20262b"))
			Art.box(body_art, Vector3(0, wr + tub_h + 0.20, -0.02), Vector3(W * 0.66, 0.14, 0.05), Color("20303c"))
			for side in [-1.0, 1.0]:
				Art.box(body_art, Vector3(side * half_w, wr + 0.16, 0.1), Vector3(0.06, 0.10, L * 0.62), Color("1b2025"))
			Art.box(body_art, Vector3(0, wr + tub_h + 0.07, half_l * 0.74), Vector3(W * 0.8, 0.10, 0.34), paint_color)
			_add_standard_lights(body_art, half_w * 0.76, wr + 0.30, half_l, headlights, taillights)
			_add_four_wheels(body_art, half_w, wr, ww, half_l * 0.66, wheels)

		VehicleClass.HYPERCAR:
			# Long-tail hypercar: flat floor, bubble canopy, snorkel and rear wing.
			var floor_h := 0.36
			Art.box(body_art, Vector3(0, wr + floor_h * 0.5, 0), Vector3(W, floor_h, L), paint_color)
			Art.tapered_box(body_art, Vector3(0, wr + floor_h + 0.04, -half_l * 0.42),
				Vector3(W * 0.96, 0.20, L * 0.52), Vector2(W * 0.72, 0.28), paint_color)
			Art.tapered_box(body_art, Vector3(0, wr + floor_h + 0.26, 0.05),
				Vector3(W * 0.70, 0.36, L * 0.36), Vector2(W * 0.48, 0.20), Color("0f1720"))
			Art.box(body_art, Vector3(0, wr + floor_h + 0.44, 0.34), Vector3(0.52, 0.12, 0.72), Color("11171c"))
			Art.box(body_art, Vector3(0, wr + 0.10, -half_l - 0.08), Vector3(W * 0.98, 0.08, 0.42), Color("161b20"))
			Art.box(body_art, Vector3(0, wr + floor_h + 0.50, half_l * 0.80), Vector3(W * 0.94, 0.06, 0.46), Color("11161a"))
			for side in [-1.0, 1.0]:
				Art.box(body_art, Vector3(side * W * 0.30, wr + floor_h + 0.28, half_l * 0.80), Vector3(0.06, 0.34, 0.10), Color("1b2126"))
			Art.box(body_art, Vector3(0, wr + 0.16, half_l + 0.04), Vector3(W * 0.72, 0.16, 0.18), Color("101418"))
			_add_standard_lights(body_art, half_w * 0.80, wr + 0.28, half_l, headlights, taillights)
			_add_four_wheels(body_art, half_w, wr, ww, half_l * 0.64, wheels)

		VehicleClass.TRACK_CAR:
			# Winged track special: exposed cage, canards and a tall rear wing.
			var shell_h := 0.46
			Art.box(body_art, Vector3(0, wr + shell_h * 0.5, 0), Vector3(W, shell_h, L), paint_color)
			Art.tapered_box(body_art, Vector3(0, wr + shell_h * 0.42, -half_l * 0.64),
				Vector3(W * 0.92, shell_h * 0.78, L * 0.38), Vector2(W * 0.64, 0.3), paint_color)
			Art.tapered_box(body_art, Vector3(0, wr + shell_h + 0.20, 0.10),
				Vector3(W * 0.66, 0.34, L * 0.30), Vector2(W * 0.52, 0.18), Color("151d24"))
			Art.box(body_art, Vector3(0, wr + shell_h + 0.42, 0.48), Vector3(W * 0.60, 0.05, 0.05), Color("c8cdd2"))
			for side in [-1.0, 1.0]:
				Art.box(body_art, Vector3(side * W * 0.24, wr + shell_h + 0.24, 0.48), Vector3(0.05, 0.34, 0.05), Color("c8cdd2"))
				Art.box(body_art, Vector3(side * W * 0.46, wr + shell_h + 0.52, half_l * 0.74), Vector3(0.06, 0.46, 0.12), Color("1a1f24"))
				Art.box(body_art, Vector3(side * W * 0.48, wr + 0.20, -half_l * 0.92), Vector3(0.10, 0.04, 0.30), Color("1a1f24"))
			Art.box(body_art, Vector3(0, wr + shell_h + 0.72, half_l * 0.72), Vector3(W * 1.0, 0.07, 0.56), Color("12171b"))
			Art.box(body_art, Vector3(0, wr + 0.09, -half_l - 0.05), Vector3(W * 0.98, 0.07, 0.34), Color("14191e"))
			Art.box(body_art, Vector3(0, wr + 0.20, half_l + 0.02), Vector3(W * 0.9, 0.12, 0.20), Color("14191e"))
			_add_standard_lights(body_art, half_w * 0.78, wr + 0.30, half_l, headlights, taillights)
			_add_four_wheels(body_art, half_w, wr, ww, half_l * 0.62, wheels)

		_:
			# Standard Sedans, Hatchbacks, SUVs, Delivery Vans
			Art.box(body_art, Vector3(0, wr + 0.35, 0), Vector3(W, 0.6, L), paint_color)
			var cab_h := 0.65 if vclass != VehicleClass.DELIVERY_VAN else 1.3
			var cab_l := L * 0.55 if vclass != VehicleClass.DELIVERY_VAN else L * 0.75
			var cab_z := 0.1 if vclass != VehicleClass.DELIVERY_VAN else 0.4
			Art.tapered_box(body_art, Vector3(0, wr + 0.65 + cab_h * 0.5, cab_z), Vector3(W * 0.88, cab_h, cab_l), Vector2(W * 0.72, cab_l * 0.7), Color("2b3a4a"))
			_add_standard_lights(body_art, half_w * 0.78, wr + 0.4, half_l, headlights, taillights)
			_add_four_wheels(body_art, half_w, wr, ww, half_l * 0.62, wheels)

	# Near-future retrofit detail: restrained LED accents on modernised everyday
	# vehicles. No silhouette or physics changes; shared emissive materials only.
	_add_future_accents(body_art, vclass, L, W, wr, half_l)

	return {
		"body_art": body_art,
		"wheels": wheels,
		"headlights": headlights,
		"taillights": taillights,
		"emergency_lights": emergency_lights,
		"emergency_light_nodes": emergency_light_nodes,
		"specs": spec
	}

static var _accent_materials: Dictionary = {}

static func _accent_mat(color: Color) -> StandardMaterial3D:
	var key := color.to_html(false)
	if _accent_materials.has(key):
		return _accent_materials[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.4
	_accent_materials[key] = mat
	return mat


static func _accent_box(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var shape := BoxMesh.new()
	shape.size = size
	mesh.mesh = shape
	mesh.material_override = _accent_mat(color)
	parent.add_child(mesh)
	mesh.position = pos


static func _add_future_accents(parent: Node3D, vclass: int, length_m: float, width_m: float, wheel_r: float, half_len: float) -> void:
	var accent := Color("19e6ff")
	match vclass:
		VehicleClass.TAXI, VehicleClass.DELIVERY_VAN:
			accent = Color("ffae32")
		VehicleClass.POLICE:
			accent = Color("3a7bff")
		VehicleClass.SPORTS, VehicleClass.ROADSTER, VehicleClass.HYPERCAR, VehicleClass.TRACK_CAR:
			accent = Color("ff2e88")
		VehicleClass.BUS:
			accent = Color("38ffc8")
		_:
			return
	for side in [-1.0, 1.0]:
		_accent_box(parent, Vector3(side * (width_m * 0.5 + 0.01), wheel_r + 0.18, 0.0),
			Vector3(0.05, 0.05, length_m * 0.7), accent)
	_accent_box(parent, Vector3(0.0, wheel_r + 0.48, -half_len - 0.02),
		Vector3(width_m * 0.55, 0.045, 0.04), accent)


static func _build_emergency_lightbar(parent: Node3D, pos: Vector3, width: float, out_meshes: Array[MeshInstance3D], out_lights: Array[OmniLight3D], is_police_ambulance: bool) -> void:
	# Base aerodynamic bar
	Art.box(parent, pos, Vector3(width, 0.12, 0.28), Color("1a1a1a"))
	# Left flasher (Blue for police/ambulance, Red for fire)
	var left_color := Color("0044ff") if is_police_ambulance else Color("ff1111")
	var right_color := Color("ff1111")
	var half_w := width * 0.4
	
	var left_mesh := Art.box(parent, pos + Vector3(-half_w * 0.5, 0.05, 0), Vector3(half_w, 0.16, 0.24), left_color)
	var right_mesh := Art.box(parent, pos + Vector3(half_w * 0.5, 0.05, 0), Vector3(half_w, 0.16, 0.24), right_color)
	out_meshes.append(left_mesh)
	out_meshes.append(right_mesh)

	var left_light := OmniLight3D.new()
	left_light.name = "EmergencyLightLeft"
	left_light.position = pos + Vector3(-half_w * 0.5, 0.2, 0)
	left_light.light_color = left_color
	left_light.light_energy = 0.0
	left_light.omni_range = 14.0
	left_light.shadow_enabled = false
	parent.add_child(left_light)
	out_lights.append(left_light)

	var right_light := OmniLight3D.new()
	right_light.name = "EmergencyLightRight"
	right_light.position = pos + Vector3(half_w * 0.5, 0.2, 0)
	right_light.light_color = right_color
	right_light.light_energy = 0.0
	right_light.omni_range = 14.0
	right_light.shadow_enabled = false
	parent.add_child(right_light)
	out_lights.append(right_light)

static func _add_standard_lights(parent: Node3D, x: float, y: float, z: float, hl_arr: Array[MeshInstance3D], tl_arr: Array[MeshInstance3D]) -> void:
	for side in [-1, 1]:
		# Front headlights (bright warm white)
		var hl := Art.box(parent, Vector3(side * x, y, -z + 0.05), Vector3(0.35, 0.18, 0.08), Color("fff8d6"))
		hl_arr.append(hl)
		# Rear taillights (red)
		var tl := Art.box(parent, Vector3(side * x, y, z - 0.05), Vector3(0.35, 0.18, 0.08), Color("cc1111"))
		tl_arr.append(tl)

static func _add_four_wheels(parent: Node3D, half_w: float, wr: float, ww: float, axle_z: float, out_wheels: Array[MeshInstance3D]) -> void:
	out_wheels.append(_make_wheel(parent, Vector3(-half_w, wr, -axle_z), wr, ww))
	out_wheels.append(_make_wheel(parent, Vector3(half_w, wr, -axle_z), wr, ww))
	out_wheels.append(_make_wheel(parent, Vector3(-half_w, wr, axle_z), wr, ww))
	out_wheels.append(_make_wheel(parent, Vector3(half_w, wr, axle_z), wr, ww))

static func _make_wheel(parent: Node3D, pos: Vector3, radius: float, width: float) -> MeshInstance3D:
	var mesh_inst := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = width
	mesh_inst.mesh = cylinder
	mesh_inst.rotation.z = PI * 0.5
	mesh_inst.position = pos
	
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("1a1a1a")
	mat.roughness = 0.8
	mesh_inst.material_override = mat
	parent.add_child(mesh_inst)
	return mesh_inst
