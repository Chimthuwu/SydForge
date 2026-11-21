extends Node3D

## CYBERPUNK SYDNEY — VISUAL VERTICAL SLICE
##
## A deliberately scoped art-direction layer, NOT a replacement world. It keeps
## every OSM footprint, road, landmark, train and pedestrian system intact and
## only adds presentation geometry to two hero locations:
##   1. the George Street CBD corridor (Town Hall / QVB end), and
##   2. the Wynyard underground station concourse + platform.
##
## The shared asset library has no neon / holographic / futuristic 3D assets
## (see docs/CYBERPUNK_ASSET_GAP.md), so signage is built from cheap animated
## shader quads with a restrained palette. Only a handful of real lights are
## created; everything else is emissive geometry that uses the scene's glow.

const NEON_SHADER := preload("res://shaders/neon_panel.gdshader")
const HOLO_SHADER := preload("res://shaders/hologram.gdshader")

# Restrained cyberpunk palette: cool corporate cyan/blue, entertainment pink,
# warm amber industrial. Used deliberately, not one colour per building.
const CYAN := Color("19e6ff")
const BLUE := Color("3a7bff")
const MAGENTA := Color("ff2e88")
const VIOLET := Color("a95cff")
const AMBER := Color("ffae32")
const RED := Color("ff4438")
const AQUA := Color("38ffc8")

const HERO_STREET := "george"
## The long George Street service/trunk segment through the CBD near Town Hall.
const HERO_ANCHOR := Vector2(-90.0, -300.0)

var stats: Dictionary = {}
var _night_factor := 0.0
var _neon_materials: Array[ShaderMaterial] = []
var _holo_materials: Array[ShaderMaterial] = []
var _dyn_lights: Array[OmniLight3D] = []
var _time_mgr: Node = null
var _signed_buildings: Dictionary = {}


func build(world_data: Dictionary) -> void:
	name = "NeonVerticalSlice"
	_build_street_dressing(world_data)
	_build_hero_facade()
	_build_wynyard_dressing()
	# The world builds this module before add_child(), so get_tree() is null here.
	# Defer wiring to the clock until the node is inside the scene tree.
	call_deferred("_connect_time_manager")
	_apply_night_factor(_night_factor)
	stats = {
		"neonPanels": _neon_materials.size(),
		"holograms": _holo_materials.size(),
		"dynamicLights": _dyn_lights.size(),
		"locations": ["george_street_cbd", "wynyard_underground"],
	}


# ---------------------------------------------------------------------------
# Shared material / mesh helpers
# ---------------------------------------------------------------------------

func _neon_material(color: Color, accent: Color, seed: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = NEON_SHADER
	material.set_shader_parameter("panel_color", color)
	material.set_shader_parameter("accent_color", accent)
	material.set_shader_parameter("seed", seed)
	material.set_shader_parameter("night_factor", _night_factor)
	_neon_materials.append(material)
	return material


func _holo_material(color: Color, seed: float, alpha: float = 0.42) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = HOLO_SHADER
	material.set_shader_parameter("holo_color", color)
	material.set_shader_parameter("seed", seed)
	material.set_shader_parameter("alpha_strength", alpha)
	material.set_shader_parameter("night_factor", _night_factor)
	_holo_materials.append(material)
	return material


func _quad(parent: Node3D, name: String, pos: Vector3, size: Vector2, yaw: float, material: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = name
	var plane := PlaneMesh.new()
	plane.size = size
	mesh.mesh = plane
	mesh.material_override = material
	parent.add_child(mesh)
	mesh.position = pos
	mesh.rotation.y = yaw
	return mesh


func _box(parent: Node3D, pos: Vector3, size: Vector3, color: Color, emission: float = 0.0) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var shape := BoxMesh.new()
	shape.size = size
	mesh.mesh = shape
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if emission > 0.0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = emission
	mesh.material_override = mat
	parent.add_child(mesh)
	mesh.position = pos
	return mesh


func _add_light(parent: Node3D, pos: Vector3, color: Color, energy: float, range_m: float) -> void:
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 0.0  # enabled by night factor
	light.omni_range = range_m
	light.shadow_enabled = false
	parent.add_child(light)
	light.position = pos
	_dyn_lights.append(light)
	light.set_meta("base_energy", energy)


func _connect_time_manager() -> void:
	if not is_inside_tree() or get_tree() == null:
		call_deferred("_connect_time_manager")
		return
	var mgrs := get_tree().get_nodes_in_group("time_managers")
	if not mgrs.is_empty():
		_time_mgr = mgrs[0]
	if _time_mgr != null:
		if _time_mgr.has_signal("lighting_factor_changed"):
			_time_mgr.connect("lighting_factor_changed", Callable(self, "_apply_night_factor"))
		if "lighting_factor" in _time_mgr:
			_night_factor = float(_time_mgr.get("lighting_factor"))


func _apply_night_factor(factor: float) -> void:
	_night_factor = clampf(factor, 0.0, 1.0)
	for mat in _neon_materials:
		mat.set_shader_parameter("night_factor", _night_factor)
	for mat in _holo_materials:
		mat.set_shader_parameter("night_factor", _night_factor)
	for light in _dyn_lights:
		if is_instance_valid(light):
			light.light_energy = float(light.get_meta("base_energy")) * _night_factor
			light.visible = _night_factor > 0.05


# ---------------------------------------------------------------------------
# Hero street: George Street CBD
# ---------------------------------------------------------------------------

func _find_street_road(world_data: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_score := INF
	for road in world_data.get("roads", []):
		var road_name := str(road.get("name", "")).to_lower()
		if not road_name.contains(HERO_STREET):
			continue
		var points: Array = road.get("points", [])
		# Prefer a long continuous segment so the dressing spans the hero street.
		if points.size() < 8:
			continue
		var idx := points.size() / 2
		var mid := Vector2(float(points[idx][0]), float(points[idx][1]))
		var score := mid.distance_to(HERO_ANCHOR)
		if score < best_score:
			best_score = score
			best = road
	return best


func _building_bounds(row: Dictionary) -> Rect2:
	var ring: Array = row.get("ring", [])
	if ring.size() < 3:
		return Rect2()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for point in ring:
		var v := Vector2(float(point[0]), float(point[1]))
		lo = lo.min(v)
		hi = hi.max(v)
	return Rect2(lo, hi - lo)


func _face_near(rect: Rect2, target: Vector2, y: float) -> Dictionary:
	var c := rect.get_center()
	var dx := target.x - c.x
	var dz := target.y - c.y
	if absf(dx) > absf(dz):
		var sign := 1.0 if dx > 0.0 else -1.0
		var x := rect.end.x if sign > 0.0 else rect.position.x
		var z := clampf(target.y, rect.position.y, rect.end.y)
		var normal := Vector3(sign, 0.0, 0.0)
		return {"pos": Vector3(x, y, z), "normal": normal, "yaw": atan2(normal.x, normal.z)}
	var sign := 1.0 if dz > 0.0 else -1.0
	var z := rect.end.y if sign > 0.0 else rect.position.y
	var x := clampf(target.x, rect.position.x, rect.end.x)
	var normal := Vector3(0.0, 0.0, sign)
	return {"pos": Vector3(x, y, z), "normal": normal, "yaw": atan2(normal.x, normal.z)}


func _palette_for(district: String) -> Array:
	match district:
		"kings-cross", "darlinghurst":
			return [MAGENTA, VIOLET, RED]
		"cbd-core", "town-hall", "wynyard", "martin-place":
			return [CYAN, BLUE, AQUA]
		"haymarket", "darling-quarter":
			return [MAGENTA, CYAN, AMBER]
		_:
			return [CYAN, MAGENTA, AMBER]


func _build_street_dressing(world_data: Dictionary) -> void:
	var road := _find_street_road(world_data)
	var points: Array = road.get("points", [])
	if points.size() < 4:
		push_warning("NeonVerticalSlice: George Street road not found; street dressing skipped")
		return

	var street := Node3D.new()
	street.name = "HeroStreet_GeorgeCBD"
	add_child(street)

	# Index buildings once; choose the closest un-signed candidate per sample.
	var buildings: Array = []
	for row in world_data.get("buildings", []):
		var rect := _building_bounds(row)
		if rect.size.x < 3.0 or rect.size.y < 3.0:
			continue
		buildings.append({"row": row, "rect": rect, "center": rect.get_center()})

	var colours := [CYAN, BLUE, MAGENTA, VIOLET, AQUA, AMBER]
	var sample_step := maxi(2, points.size() / 16)
	var sample_count := 0
	for index in range(1, points.size() - 1, sample_step):
		var p := Vector2(float(points[index][0]), float(points[index][1]))
		if p.distance_to(HERO_ANCHOR) > 520.0:
			continue
		sample_count += 1

		# Two nearest buildings to this street sample (one per side).
		var candidates: Array = []
		for entry in buildings:
			var d: float = (entry["center"] as Vector2).distance_to(p)
			if d < 46.0:
				candidates.append({"entry": entry, "d": d})
		candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["d"] < b["d"])

		var placed := 0
		for cand in candidates:
			if placed >= 2:
				break
			var entry: Dictionary = cand["entry"]
			var row: Dictionary = entry["row"]
			var id := str(row.get("id", ""))
			if _signed_buildings.has(id):
				continue
			_signed_buildings[id] = true
			placed += 1

			var rect: Rect2 = entry["rect"]
			var height := float(row.get("heightM", 10.0))
			var district := str(row.get("district", "cbd-core"))
			var palette := _palette_for(district)
			var color: Color = palette[(sample_count + placed) % palette.size()]
			var accent: Color = palette[(sample_count + placed + 1) % palette.size()]
			var before := Vector2(float(points[index - 1][0]), float(points[index - 1][1]))
			var after := Vector2(float(points[index + 1][0]), float(points[index + 1][1]))
			var tangent := (after - before).normalized()
			var side_vec := Vector2(-tangent.y, tangent.x)
			var side_sign := 1.0 if (rect.get_center() - p).dot(side_vec) >= 0.0 else -1.0
			var face_point := p + side_vec * side_sign * 8.0

			# Ground-floor neon shopfront band.
			var shop_face := _face_near(rect, face_point, 3.2)
			var shop_mat := _neon_material(color, accent, float(sample_count * 3 + placed))
			var shop := _quad(street, "NeonShop_%d_%d" % [sample_count, placed],
				shop_face["pos"] + shop_face["normal"] * 0.35,
				Vector2(6.0, 2.2), shop_face["yaw"], shop_mat)
			shop.set_meta("kind", "shopfront")

			# Blade sign projects out over the footpath: reads face-on from a
			# street-level camera looking down the road, unlike a flat wall sign.
			var blade_mat := _neon_material(accent, color, float(sample_count * 5 + placed))
			var blade_normal: Vector3 = shop_face["normal"]
			var blade_yaw := atan2(blade_normal.x, blade_normal.z) + PI * 0.5
			var blade_pos: Vector3 = shop_face["pos"] + blade_normal * 1.4
			blade_pos.y = 4.2
			_quad(street, "BladeSign_%d_%d" % [sample_count, placed], blade_pos,
				Vector2(2.4, 1.6), blade_yaw, blade_mat)

			# Large vertical signage / billboard higher on the facade.
			if height > 16.0:
				var bill_y := clampf(minf(height * 0.55, 34.0), 8.0, 34.0)
				var bill_face := _face_near(rect, face_point, bill_y)
				var bill_mat := _neon_material(color, accent, float(sample_count * 7 + placed))
				var bill := _quad(street, "NeonBillboard_%d_%d" % [sample_count, placed],
					bill_face["pos"] + bill_face["normal"] * 0.4,
					Vector2(minf(9.0, rect.size.length() * 0.6), minf(7.0, height * 0.3)),
					bill_face["yaw"], bill_mat)
				bill.set_meta("kind", "billboard")

				# Tower crown band on the tallest buildings.
				if height > 55.0 and sample_count % 3 == 0:
					var crown := _face_near(rect, face_point, height - 4.0)
					var crown_mat := _neon_material(accent, color, float(sample_count * 11))
					_quad(street, "TowerCrown_%d" % sample_count,
						crown["pos"] + crown["normal"] * 0.4,
						Vector2(minf(12.0, rect.size.length() * 0.7), 2.2),
						crown["yaw"], crown_mat)

		# Holographic ad floating just off the footpath at selected samples.
		if sample_count % 2 == 0:
			var tangent := (Vector2(float(points[mini(index + 1, points.size() - 1)][0]), float(points[mini(index + 1, points.size() - 1)][1]))
				- Vector2(float(points[maxi(index - 1, 0)][0]), float(points[maxi(index - 1, 0)][1]))).normalized()
			var side := Vector2(-tangent.y, tangent.x)
			var holo_pos := Vector3(p.x + side.x * 5.0, 2.6, p.y + side.y * 5.0)
			var yaw := atan2(side.x, side.y)
			var holo_mat := _holo_material(colours[sample_count % colours.size()], float(sample_count) * 1.7, 0.38)
			_quad(street, "HoloAd_%d" % sample_count, holo_pos, Vector2(2.2, 3.0), yaw, holo_mat)

		# Electronic kiosk / charging point on the footpath.
		if sample_count % 3 == 0:
			_build_kiosk(street, p, sample_count, colours)

		# Selective real lighting: one coloured fixture per few samples.
		if sample_count % 4 == 0:
			var tint: Color = colours[sample_count % colours.size()]
			_add_light(street, Vector3(p.x, 5.2, p.y), tint, 1.5, 24.0)
			_box(street, Vector3(p.x, 5.6, p.y), Vector3(0.5, 0.12, 0.5), tint, 2.0)


## A deliberate hero installation on the big CBD block the street camera faces.
## This is what makes the vertical slice read instantly as a neon city rather
## than the original dark street; everything is presentation-only geometry.
func _build_hero_facade() -> void:
	var hero := Node3D.new()
	hero.name = "HeroBillboardCluster"
	add_child(hero)

	# The main building face at the end of the viewport (yaw 0 => faces +Z,
	# towards a camera standing north of it and looking south).
	var bill_mat := _neon_material(CYAN, MAGENTA, 77.0)
	_quad(hero, "MegaBillboard", Vector3(-62.0, 13.0, -329.0), Vector2(16.0, 9.0), 0.0, bill_mat)

	# Vertical banner signs flanking the billboard.
	for side in [-1.0, 1.0]:
		var side_mat := _neon_material(MAGENTA if side < 0.0 else VIOLET, CYAN, float(80 + int(side)))
		_quad(hero, "VerticalBanner_%d" % int(side),
			Vector3(-62.0 + side * 10.0, 10.0, -328.8), Vector2(1.7, 8.0), 0.0, side_mat)
		var strip_mat := _neon_material(AQUA, CYAN, float(90 + int(side)))
		_quad(hero, "FacadeStrip_%d" % int(side),
			Vector3(-62.0 + side * 12.5, 20.0, -328.8), Vector2(0.35, 11.0), 0.0, strip_mat)

	# Floating holographic ad above the street, visible at eye level.
	var holo := _holo_material(MAGENTA, 91.0, 0.55)
	_quad(hero, "HeroHologram", Vector3(-56.0, 5.4, -310.0), Vector2(4.0, 5.2), 0.0, holo)

	# Neon light spill / reflection patches on the wet asphalt (additive).
	for i in 5:
		var spill := _holo_material(CYAN if i % 2 == 0 else MAGENTA, float(100 + i), 0.14)
		_quad(hero, "RoadSpill_%d" % i,
			Vector3(-62.0 + randf_range(-6.0, 6.0), 0.075, -303.0 - float(i) * 6.0),
			Vector2(6.0, 1.8), 0.0, spill)

	_add_light(hero, Vector3(-62.0, 10.0, -316.0), CYAN, 2.4, 34.0)
	_add_light(hero, Vector3(-62.0, 5.0, -308.0), MAGENTA, 1.6, 24.0)


func _build_kiosk(parent: Node3D, at: Vector2, index: int, colours: Array) -> void:
	var kiosk := Node3D.new()
	kiosk.name = "DigitalKiosk_%d" % index
	kiosk.position = Vector3(at.x, 0.0, at.y)
	parent.add_child(kiosk)
	_box(kiosk, Vector3(0.0, 1.1, 0.0), Vector3(0.8, 2.2, 0.5), Color("1b2229"))
	_box(kiosk, Vector3(0.0, 2.25, 0.0), Vector3(1.0, 0.12, 0.65), Color("2a333c"))
	var mat := _neon_material(CYAN, colours[index % colours.size()], float(index * 13))
	_quad(kiosk, "KioskScreen", Vector3(0.0, 1.6, 0.27), Vector2(0.62, 0.9), 0.0, mat)
	# CCTV mast — surveillance is a quiet part of the setting, not a gameplay device.
	_box(kiosk, Vector3(0.45, 2.8, 0.0), Vector3(0.06, 1.2, 0.06), Color("3a4048"))
	_box(kiosk, Vector3(0.45, 3.4, -0.12), Vector3(0.22, 0.12, 0.3), Color("20262b"))


# ---------------------------------------------------------------------------
# Hero underground: Wynyard
# ---------------------------------------------------------------------------

func _build_wynyard_dressing() -> void:
	var wynyard := Node3D.new()
	wynyard.name = "HeroUnderground_Wynyard"
	wynyard.position = Vector3(-202.5, 0.0, -778.2)
	add_child(wynyard)

	var conc_y := -5.5
	var plat_y := -9.85

	# Large digital departure board above the ticket hall.
	var board_mat := _neon_material(CYAN, BLUE, 3.0)
	_quad(wynyard, "DigitalDepartureBoard", Vector3(0.0, conc_y + 3.1, -7.6), Vector2(7.0, 2.0), 0.0, board_mat)
	_box(wynyard, Vector3(0.0, conc_y + 3.1, -7.75), Vector3(7.4, 2.4, 0.16), Color("161c22"))

	# Wayfinding strips along both concourse walls.
	for side in [-1.0, 1.0]:
		var strip_mat := _neon_material(AQUA if side > 0.0 else MAGENTA, CYAN, float(side + 9.0))
		_quad(wynyard, "Wayfinding_%d" % int(side), Vector3(side * 14.7, conc_y + 1.9, 0.0),
			Vector2(18.0, 0.35), PI * 0.5 * side, strip_mat)

	# Futuristic ticket gates: slim illuminated pedestals rather than toy boxes.
	for gate in range(6):
		var gx := -4.0 + float(gate) * 1.6
		_box(wynyard, Vector3(gx, conc_y + 0.85, 1.5), Vector3(0.22, 1.7, 1.0), Color("2a3138"))
		var reader := _neon_material(CYAN, AQUA, float(gate + 21.0))
		_quad(wynyard, "GateReader_%d" % gate, Vector3(gx, conc_y + 1.45, 2.02), Vector2(0.3, 0.16), 0.0, reader)

	# Digital advertisements in the passage.
	for ad in range(4):
		var z := -12.0 + float(ad) * 8.0
		var mat := _neon_material(MAGENTA if ad % 2 == 0 else VIOLET, CYAN, float(ad + 31.0))
		_quad(wynyard, "StationAd_%d" % ad, Vector3(-14.6, conc_y + 2.0, z), Vector2(4.0, 2.6), PI * 0.5, mat)

	# Holographic transport map floating in the concourse.
	var holo := _holo_material(AQUA, 5.0, 0.5)
	_quad(wynyard, "HoloNetworkMap", Vector3(4.5, conc_y + 2.2, -3.0), Vector2(2.6, 2.2), -0.5, holo)

	# Industrial ceiling infrastructure: conduit runs and cablebay boxes.
	for side in [-1.0, 1.0]:
		_box(wynyard, Vector3(side * 2.5, conc_y + 4.0, 0.0), Vector3(0.35, 0.35, 28.0), Color("343b42"))
		for cable in range(5):
			_box(wynyard, Vector3(side * (1.2 + float(cable) * 0.22), conc_y + 3.75, 0.0),
				Vector3(0.06, 0.06, 28.0), Color("202729"))

	# Platform-level illuminated wayfinding and lighting.
	for side in [-1.0, 1.0]:
		var plat_mat := _neon_material(AQUA if side > 0.0 else BLUE, CYAN, float(side + 41.0))
		_quad(wynyard, "PlatformStrip_%d" % int(side), Vector3(side * 6.6, plat_y + 2.4, 0.0),
			Vector2(42.0, 0.28), PI * 0.5 * side, plat_mat)
	_add_light(wynyard, Vector3(0.0, conc_y + 3.4, -2.0), CYAN, 2.2, 22.0)
	_add_light(wynyard, Vector3(0.0, plat_y + 3.0, 0.0), AQUA, 1.8, 26.0)
