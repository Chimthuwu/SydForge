extends Node3D

## CYBERPUNK SYDNEY — CITY-WIDE VISUAL SYSTEM
##
## Extends the approved George Street / Wynyard vertical slice across the whole
## playable world. This is a presentation-only layer: no footprints, roads,
## collisions, trains, traffic or pedestrian systems are changed.
##
## Design rules:
##   * district profiles drive palette + density (no per-sign hardcoding);
##   * shared, cached materials — not one ShaderMaterial per sign;
##   * a hard budget of real lights, culled to the nearest few each frame;
##   * architectural skyline treatment (crowns, antennae, beacons, strips),
##     not glowing rectangles on the horizon;
##   * landmarks keep their silhouettes and gain only additive dressing.

const NEON_SHADER := preload("res://shaders/neon_panel.gdshader")
const HOLO_SHADER := preload("res://shaders/hologram.gdshader")
const BEACON_SHADER := preload("res://shaders/beacon.gdshader")

# Restrained palette. Primary cool corporate, entertainment warm, industrial.
const CYAN := Color("19e6ff")
const BLUE := Color("3a7bff")
const MAGENTA := Color("ff2e88")
const VIOLET := Color("a95cff")
const AMBER := Color("ffae32")
const RED := Color("ff4438")
const AQUA := Color("38ffc8")
const WHITE := Color("e8f6ff")

## district id -> visual identity. sign_count is capped per district; tower_count
## is the number of that district's tallest buildings that get skyline dressing.
const DISTRICTS := {
	"cbd-core": {"palette": [CYAN, BLUE, AQUA], "signs": 10, "towers": 8, "style": "corporate"},
	"town-hall": {"palette": [CYAN, BLUE, MAGENTA], "signs": 8, "towers": 4, "style": "retail"},
	"wynyard": {"palette": [CYAN, AQUA, BLUE], "signs": 6, "towers": 3, "style": "corporate"},
	"martin-place": {"palette": [CYAN, BLUE, WHITE], "signs": 7, "towers": 4, "style": "corporate"},
	"circular-quay": {"palette": [AQUA, CYAN, BLUE], "signs": 9, "towers": 4, "style": "waterfront"},
	"the-rocks": {"palette": [AMBER, CYAN, WHITE], "signs": 6, "towers": 2, "style": "heritage"},
	"barangaroo": {"palette": [BLUE, CYAN, AQUA], "signs": 8, "towers": 6, "style": "corporate"},
	"darling-quarter": {"palette": [MAGENTA, BLUE, CYAN], "signs": 7, "towers": 4, "style": "entertainment"},
	"haymarket": {"palette": [MAGENTA, CYAN, AMBER], "signs": 8, "towers": 3, "style": "entertainment"},
	"central": {"palette": [CYAN, AQUA, BLUE], "signs": 8, "towers": 4, "style": "transport"},
	"surry-hills": {"palette": [AMBER, MAGENTA, CYAN], "signs": 6, "towers": 2, "style": "industrial"},
	"darlinghurst": {"palette": [MAGENTA, VIOLET, CYAN], "signs": 7, "towers": 3, "style": "nightlife"},
	"kings-cross": {"palette": [MAGENTA, VIOLET, RED], "signs": 10, "towers": 3, "style": "nightlife"},
	"potts-point": {"palette": [MAGENTA, VIOLET, CYAN], "signs": 5, "towers": 2, "style": "nightlife"},
	"woolloomooloo": {"palette": [AMBER, CYAN, MAGENTA], "signs": 5, "towers": 2, "style": "mixed"},
	"hyde-park": {"palette": [AQUA, CYAN, WHITE], "signs": 4, "towers": 2, "style": "civic"},
	"the-domain": {"palette": [AQUA, CYAN, BLUE], "signs": 3, "towers": 1, "style": "civic"},
	"botanic-garden": {"palette": [AQUA, CYAN], "signs": 2, "towers": 1, "style": "civic"},
	"millers-point": {"palette": [AMBER, CYAN, AQUA], "signs": 5, "towers": 2, "style": "waterfront"},
	"barangaroo-reserved": {"palette": [BLUE, CYAN], "signs": 3, "towers": 1, "style": "corporate"},
}

const MAX_LIGHTS := 12
const ACTIVE_LIGHTS := 6
const LIGHT_RANGE := 130.0

# The approved vertical slice already dresses these areas; avoid double signs.
const SLICE_ANCHORS := [Vector2(-90.0, -300.0), Vector2(-202.5, -778.2)]
const SLICE_EXCLUSION_M := 95.0

var stats: Dictionary = {}
var _materials: Dictionary = {}
var _beacon_material: ShaderMaterial
var _lights: Array[OmniLight3D] = []
var _player: Node3D
var _time_mgr: Node
var _night_factor := 0.0
var _update_timer := 0.0
var _signed: Dictionary = {}
var _towered: Dictionary = {}
var _batches: Dictionary = {}
var _beacon_batch: Array[Transform3D] = []
## Emissive StandardMaterial3D instances (opera edge light, bridge deck lamps,
## harbour path lights). Their energy is scaled by the night factor so they do
## not glow at midday.
var _night_emissives: Array = []
var _unit_quad: PlaneMesh
var _sun: DirectionalLight3D
## Skyline light dressing is pure light (batched glow strips and rooftop
## adverts) with no physical body, so it is hidden entirely in daylight rather
## than left as a grid of unlit rectangles across the skyline.
var _skyline_root: Node3D


func build(world_data: Dictionary, harbour_bridge: Node3D = null) -> void:
	name = "NeonCity"
	_build_districts(world_data)
	_build_skyline(world_data)
	_build_street_props(world_data)
	_build_landmarks(world_data, harbour_bridge)
	call_deferred("_wire_clock")
	_apply_night_factor(_night_factor)
	stats = {
		"materials": _materials.size(),
		"signs": _signed.size(),
		"towers": _towered.size(),
		"lights": _lights.size(),
		"districts": DISTRICTS.size(),
	}


# ---------------------------------------------------------------------------
# Shared resources
# ---------------------------------------------------------------------------

func _neon(color: Color, accent: Color, seed: int, solid: bool = false) -> ShaderMaterial:
	var key := "n:%s|%s|%d|%d" % [color.to_html(false), accent.to_html(false), seed % 4, int(solid)]
	if _materials.has(key):
		return _materials[key]
	var material := ShaderMaterial.new()
	material.shader = NEON_SHADER
	material.set_shader_parameter("panel_color", color)
	material.set_shader_parameter("accent_color", accent)
	material.set_shader_parameter("seed", float(seed % 4))
	material.set_shader_parameter("night_factor", _night_factor)
	material.set_shader_parameter("solid_glow", 1.0 if solid else 0.0)
	material.set_shader_parameter("glow_strength", 1.5 if solid else 1.0)
	_materials[key] = material
	return material


func _holo(color: Color, seed: int, alpha: float) -> ShaderMaterial:
	var key := "h:%s|%d|%d" % [color.to_html(false), seed % 4, int(alpha * 100.0)]
	if _materials.has(key):
		return _materials[key]
	var material := ShaderMaterial.new()
	material.shader = HOLO_SHADER
	material.set_shader_parameter("holo_color", color)
	material.set_shader_parameter("seed", float(seed % 4))
	material.set_shader_parameter("alpha_strength", alpha)
	material.set_shader_parameter("night_factor", _night_factor)
	_materials[key] = material
	return material


func _beacon() -> ShaderMaterial:
	if _beacon_material == null:
		_beacon_material = ShaderMaterial.new()
		_beacon_material.shader = BEACON_SHADER
		_beacon_material.set_shader_parameter("night_factor", _night_factor)
	return _beacon_material


## Wall-mounted sign plane. `QuadMesh` lies in local XY facing +Z, so a yaw
## rotation makes it stand on the facade; a horizontal `PlaneMesh` here left
## every sign flat on the ground plane (invisible from the street).
func _quad(parent: Node3D, pos: Vector3, size: Vector2, yaw: float, material: Material, name: String) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = name
	var plane := QuadMesh.new()
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
		mat.set_meta("night_energy", emission)
		_night_emissives.append(mat)
	mesh.material_override = mat
	parent.add_child(mesh)
	mesh.position = pos
	return mesh


func _add_light(parent: Node3D, pos: Vector3, color: Color, energy: float) -> void:
	if _lights.size() >= MAX_LIGHTS:
		return
	var light := OmniLight3D.new()
	light.light_color = color
	light.omni_range = 26.0
	light.shadow_enabled = false
	light.visible = false
	parent.add_child(light)
	light.position = pos
	light.set_meta("base_energy", energy)
	_lights.append(light)


func _wire_clock() -> void:
	if not is_inside_tree() or get_tree() == null:
		call_deferred("_wire_clock")
		return
	var mgrs := get_tree().get_nodes_in_group("time_managers")
	if not mgrs.is_empty():
		_time_mgr = mgrs[0]
	if _time_mgr != null and _time_mgr.has_signal("lighting_factor_changed"):
		_time_mgr.connect("lighting_factor_changed", Callable(self, "_apply_night_factor"))
	if _time_mgr != null and "lighting_factor" in _time_mgr:
		_apply_night_factor(float(_time_mgr.get("lighting_factor")))


func _apply_night_factor(factor: float) -> void:
	_night_factor = clampf(factor, 0.0, 1.0)
	if is_instance_valid(_skyline_root):
		_skyline_root.visible = _night_factor > 0.04
	for entry in _night_emissives:
		var mat := entry as StandardMaterial3D
		if mat != null:
			mat.emission_energy_multiplier = float(mat.get_meta("night_energy")) * _night_factor
	for material in _materials.values():
		var sm := material as ShaderMaterial
		if sm != null:
			if sm.shader == NEON_SHADER or sm.shader == HOLO_SHADER:
				sm.set_shader_parameter("night_factor", _night_factor)
	if _beacon_material != null:
		_beacon_material.set_shader_parameter("night_factor", _night_factor)


func _process(delta: float) -> void:
	_update_timer += delta
	if _update_timer < 0.5:
		return
	_update_timer = 0.0
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	# At night the sun contributes almost no light, yet its shadow pass still
	# re-renders the whole city. Skip it after dark; reinstate it by day.
	if not is_instance_valid(_sun):
		var suns := get_tree().root.find_children("*", "DirectionalLight3D", true, false)
		_sun = suns[0] as DirectionalLight3D if not suns.is_empty() else null
	if is_instance_valid(_sun):
		_sun.shadow_enabled = _night_factor < 0.45
	if _player == null or _lights.is_empty():
		return
	var player_pos: Vector3 = _player.global_position
	var ranked: Array[Dictionary] = []
	for light in _lights:
		if is_instance_valid(light):
			ranked.append({"light": light, "dist": light.global_position.distance_to(player_pos)})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["dist"]) < float(b["dist"]))
	for i in ranked.size():
		var item: Dictionary = ranked[i]
		var light: OmniLight3D = item["light"]
		var active := i < ACTIVE_LIGHTS and float(item["dist"]) < LIGHT_RANGE and _night_factor > 0.05
		light.visible = active
		if active:
			light.light_energy = float(light.get_meta("base_energy")) * _night_factor


# ---------------------------------------------------------------------------
# Geometry helpers
# ---------------------------------------------------------------------------

func _bounds(row: Dictionary) -> Rect2:
	var ring: Array = row.get("ring", [])
	if ring.size() < 3:
		return Rect2()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for point in ring:
		var p := Vector2(float(point[0]), float(point[1]))
		lo = lo.min(p)
		hi = hi.max(p)
	return Rect2(lo, hi - lo)


func _face(rect: Rect2, target: Vector2, y: float) -> Dictionary:
	var c := rect.get_center()
	var dx := target.x - c.x
	var dy := target.y - c.y
	if absf(dx) > absf(dy):
		var sign := 1.0 if dx > 0.0 else -1.0
		var x := rect.end.x if sign > 0.0 else rect.position.x
		var z := clampf(target.y, rect.position.y, rect.end.y)
		var normal := Vector3(sign, 0.0, 0.0)
		return {"pos": Vector3(x, y, z), "normal": normal, "yaw": atan2(normal.x, normal.z)}
	var sign := 1.0 if dy > 0.0 else -1.0
	var z := rect.end.y if sign > 0.0 else rect.position.y
	var x := clampf(target.x, rect.position.x, rect.end.x)
	var normal := Vector3(0.0, 0.0, sign)
	return {"pos": Vector3(x, y, z), "normal": normal, "yaw": atan2(normal.x, normal.z)}


func _in_slice(center: Vector2) -> bool:
	for anchor in SLICE_ANCHORS:
		if center.distance_to(anchor) < SLICE_EXCLUSION_M:
			return true
	return false


# ---------------------------------------------------------------------------
# District signage
# ---------------------------------------------------------------------------

func _build_districts(world_data: Dictionary) -> void:
	var centres: Dictionary = {}
	for row in world_data.get("districts", []):
		centres[str(row.get("id", ""))] = Vector2(float(row.get("x", 0.0)), float(row.get("z", 0.0)))

	var by_district: Dictionary = {}
	for row in world_data.get("buildings", []):
		var district := str(row.get("district", ""))
		if district.is_empty():
			continue
		if not by_district.has(district):
			by_district[district] = []
		(by_district[district] as Array).append(row)

	var root := Node3D.new()
	root.name = "DistrictSignage"
	add_child(root)

	for district_id in DISTRICTS:
		if not by_district.has(district_id):
			continue
		var profile: Dictionary = DISTRICTS[district_id]
		var rows: Array = by_district[district_id]
		var centre: Vector2 = centres.get(district_id, Vector2.ZERO)
		var palette: Array = profile["palette"]
		var district_node := Node3D.new()
		district_node.name = "District_" + district_id
		root.add_child(district_node)

		# Street-level signs: prefer buildings near the district centre, then
		# fill from the tallest remaining candidates.
		var candidates: Array = []
		for row in rows:
			var rect := _bounds(row)
			if rect.size.x < 4.0 or rect.size.y < 4.0:
				continue
			var c := rect.get_center()
			if _in_slice(c):
				continue
			var height := float(row.get("heightM", 8.0))
			var d := c.distance_to(centre)
			candidates.append({
				"row": row, "rect": rect, "center": c,
				"height": height, "score": d - minf(height, 40.0) * 1.5,
			})
		if candidates.is_empty():
			continue
		candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["score"] < b["score"])

		var limit: int = mini(int(profile["signs"]), candidates.size())
		for i in limit:
			var entry: Dictionary = candidates[i]
			var id := str((entry["row"] as Dictionary).get("id", "")) + "_d"
			if _signed.has(id):
				continue
			_signed[id] = true
			_build_shop_sign(district_node, entry, palette, i, centre, str(profile["style"]))


func _build_shop_sign(parent: Node3D, entry: Dictionary, palette: Array, index: int, centre: Vector2, style: String) -> void:
	var rect: Rect2 = entry["rect"]
	var height: float = entry["height"]
	var c: Vector2 = entry["center"]
	var target := centre.lerp(c, 0.5)
	var face := _face(rect, target, 3.4)
	var color: Color = palette[index % palette.size()]
	var accent: Color = palette[(index + 1) % palette.size()]
	var normal: Vector3 = face["normal"]
	var yaw: float = face["yaw"]

	# Shopfront band. Heritage districts get amber bands, nightlife gets taller.
	var band_w := minf(6.5, maxf(3.5, rect.size.length() * 0.35))
	var band_h := 2.0 if style != "nightlife" else 2.8
	_quad(parent, face["pos"] + normal * 0.35, Vector2(band_w, band_h), yaw,
		_neon(color, accent, index + 3), "Shop_%s_%d" % [style, index])

	# Blade sign perpendicular to the wall, readable along the street.
	var blade_yaw := yaw + PI * 0.5
	var blade_pos: Vector3 = face["pos"] + normal * 1.3
	blade_pos.y = 4.3
	_quad(parent, blade_pos, Vector2(2.2, 1.5), blade_yaw,
		_neon(accent, color, index + 11), "Blade_%s_%d" % [style, index])

	# Upper billboard for mid-rise and towers.
	if height > 15.0:
		var by := clampf(minf(height * 0.45, 28.0), 7.0, 28.0)
		var upper := _face(rect, target, by)
		_quad(parent, upper["pos"] + upper["normal"] * 0.4,
			Vector2(minf(8.0, rect.size.length() * 0.5), minf(6.0, height * 0.25)), upper["yaw"],
			_neon(color, accent, index + 19), "Billboard_%s_%d" % [style, index])

	# Nightlife/waterfront districts get one floating holographic ad.
	if style in ["nightlife", "entertainment", "waterfront"] and index % 3 == 0:
		var holo_pos := Vector3(c.x, 3.2, c.y) + Vector3(normal.x, 0.0, normal.z) * 3.5
		_quad(parent, holo_pos, Vector2(2.4, 3.0), yaw,
			_holo(accent, index + 27, 0.36), "Holo_%s_%d" % [style, index])


# ---------------------------------------------------------------------------
# Futuristic skyline
# ---------------------------------------------------------------------------

## A wall-plane strip: `size.x` runs along the facade tangent, `size.y` is the
## strip height. `_unit_quad` is a PlaneMesh, whose triangles lie in its local
## XZ plane, so the basis must map local X to the tangent and local Z to world
## up. Scaling a horizontal plane by Y (the previous code) leaves it horizontal
## and collapses its height, which showed up as dark slivers floating in the sky
## above and around towers instead of vertical light strips on their facades.
func _quad_xform(pos: Vector3, size: Vector2, yaw: float) -> Transform3D:
	var normal := Vector3(sin(yaw), 0.0, cos(yaw))
	var tangent := Vector3(cos(yaw), 0.0, -sin(yaw))
	var basis := Basis(tangent * size.x, normal, Vector3.UP * size.y)
	return Transform3D(basis, pos)


func _batch(color: Color, pos: Vector3, size: Vector2, yaw: float) -> void:
	var key := color.to_html(false)
	if not _batches.has(key):
		_batches[key] = []
	(_batches[key] as Array).append(_quad_xform(pos, size, yaw))


func _commit_batches(parent: Node3D) -> void:
	if _unit_quad == null:
		_unit_quad = PlaneMesh.new()
		_unit_quad.size = Vector2(1.0, 1.0)
	for key in _batches:
		var xforms: Array = _batches[key]
		if xforms.is_empty():
			continue
		var color := Color(key)
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = _unit_quad
		multi.instance_count = xforms.size()
		for i in xforms.size():
			multi.set_instance_transform(i, xforms[i])
		var instance := MultiMeshInstance3D.new()
		instance.name = "SkylineBatch_" + key
		instance.multimesh = multi
		instance.material_override = _neon(color, color, 0, true)
		parent.add_child(instance)
	if not _beacon_batch.is_empty():
		var beacon_multi := MultiMesh.new()
		beacon_multi.transform_format = MultiMesh.TRANSFORM_3D
		beacon_multi.mesh = _unit_quad
		beacon_multi.instance_count = _beacon_batch.size()
		for i in _beacon_batch.size():
			beacon_multi.set_instance_transform(i, _beacon_batch[i])
		var beacon_instance := MultiMeshInstance3D.new()
		beacon_instance.name = "SkylineBeacons"
		beacon_instance.multimesh = beacon_multi
		beacon_instance.material_override = _beacon()
		parent.add_child(beacon_instance)


func _build_skyline(world_data: Dictionary) -> void:
	var towers: Array = []
	for row in world_data.get("buildings", []):
		var height := float(row.get("heightM", 0.0))
		if height < 48.0:
			continue
		var rect := _bounds(row)
		if rect.size.x < 4.0 or rect.size.y < 4.0:
			continue
		var c := rect.get_center()
		if _in_slice(c):
			continue
		towers.append({"row": row, "rect": rect, "center": c, "height": height})
	towers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["height"] > b["height"])

	var root := Node3D.new()
	root.name = "SkylineDressing"
	add_child(root)
	_skyline_root = root

	# Batched MultiMesh: hundreds of towers become a handful of draw calls.
	var target := Vector2(300.0, 250.0)
	var second_target := Vector2(-80.0, -180.0)
	var limit: int = mini(320, towers.size())
	for i in limit:
		var entry: Dictionary = towers[i]
		var id := str((entry["row"] as Dictionary).get("id", "")) + "_t"
		if _towered.has(id):
			continue
		_towered[id] = true
		var rect: Rect2 = entry["rect"]
		var height: float = entry["height"]
		var c: Vector2 = entry["center"]
		var district := str((entry["row"] as Dictionary).get("district", "cbd-core"))
		var profile: Dictionary = DISTRICTS.get(district, {"palette": [CYAN, BLUE]})
		var palette: Array = profile["palette"]
		var color: Color = palette[i % palette.size()]

		var face := _face(rect, target, height - 3.0)
		var normal: Vector3 = face["normal"]
		_batch(color, face["pos"] + normal * 0.4,
			Vector2(minf(30.0, rect.size.length() * 0.95), 10.0), face["yaw"])

		# Vertical strips on the two primary skyline approaches.
		for view_target in [target, second_target]:
			var vt: Vector2 = view_target
			var strip_face := _face(rect, vt, height * 0.5)
			var strip_normal: Vector3 = strip_face["normal"]
			_batch(color, strip_face["pos"] + strip_normal * 0.4,
				Vector2(8.0, minf(height * 0.85, 78.0)), strip_face["yaw"])

		# Roof halo frame: four rails above the parapet, readable from any angle.
		var halo_w := minf(rect.size.x * 0.72, 26.0)
		var halo_d := minf(rect.size.y * 0.72, 26.0)
		var halo_y := height + 3.5
		for side in [-1.0, 1.0]:
			var side_f: float = float(side)
			_batch(color, Vector3(c.x + side_f * halo_w * 0.5, halo_y, c.y),
				Vector2(4.0, 14.0), PI * 0.5)
			_batch(color, Vector3(c.x, halo_y, c.y + side_f * halo_d * 0.5),
				Vector2(4.0, 14.0), 0.0)

		# Crossed roof beacons share one material and one MultiMesh.
		var roof_y := height + 4.6
		_beacon_batch.append(_quad_xform(Vector3(c.x, roof_y, c.y), Vector2(3.0, 3.0), 0.0))
		_beacon_batch.append(_quad_xform(Vector3(c.x, roof_y, c.y), Vector2(3.0, 3.0), PI * 0.5))
		if i % 7 == 0:
			_box(root, Vector3(c.x, height + 4.0, c.y), Vector3(0.18, 9.0, 0.18), Color("2c3339"))

		# Top towers carry a large rooftop advertisement.
		if i < 60 and height > 58.0:
			var top_face := _face(rect, target, height - 16.0)
			var top_normal: Vector3 = top_face["normal"]
			_batch(color, top_face["pos"] + top_normal * 0.45,
				Vector2(minf(48.0, rect.size.length() * 0.95), 24.0), top_face["yaw"])

	_commit_batches(root)


# ---------------------------------------------------------------------------
# Street-level digital infrastructure
# ---------------------------------------------------------------------------

func _build_street_props(world_data: Dictionary) -> void:
	var stops: Array = world_data.get("transit", [])
	var root := Node3D.new()
	root.name = "DigitalStreetFurniture"
	add_child(root)

	var count := 0
	for stop in stops:
		if str(stop.get("kind", "")) != "subway_entrance":
			continue
		var name := str(stop.get("name", ""))
		if name.is_empty():
			continue
		if count >= 26:
			break
		var x := float(stop.get("x", 0.0))
		var z := float(stop.get("z", 0.0))
		var p := Vector2(x, z)
		if _in_slice(p):
			continue
		count += 1
		var kiosk := Node3D.new()
		kiosk.name = "TransitKiosk_%d" % count
		kiosk.position = Vector3(x, 0.0, z)
		root.add_child(kiosk)
		_box(kiosk, Vector3(0.0, 1.05, 0.0), Vector3(0.7, 2.1, 0.45), Color("1a2026"))
		_quad(kiosk, Vector3(0.0, 1.5, 0.24), Vector2(0.55, 0.85), 0.0,
			_neon(CYAN, BLUE, count + 7), "KioskScreen_%d" % count)
		# Small holographic wayfinding marker.
		_quad(kiosk, Vector3(0.0, 2.7, 0.0), Vector2(1.4, 1.0), 0.0,
			_holo(AQUA, count + 13, 0.28), "KioskHolo_%d" % count)


# ---------------------------------------------------------------------------
# Landmarks — additive dressing only, silhouettes preserved
# ---------------------------------------------------------------------------

func _building_center(world_data: Dictionary, id: String) -> Vector2:
	for row in world_data.get("buildings", []):
		if str(row.get("id", "")) == id:
			return _bounds(row).get_center()
	return Vector2.ZERO


func _build_landmarks(world_data: Dictionary, bridge: Node3D) -> void:
	var root := Node3D.new()
	root.name = "LandmarkDressing"
	add_child(root)

	# Opera House: restrained architectural edge light + waterfront display.
	var opera := Vector2(658.72, -1763.81)
	for i in 3:
		var strip := _box(root, Vector3(opera.x - 30.0 + float(i) * 30.0, 2.2, opera.y + 34.0),
			Vector3(20.0, 0.12, 0.12), AQUA, 1.4)
		strip.name = "OperaEdge_%d" % i
	_quad(root, Vector3(opera.x - 44.0, 4.2, opera.y + 52.0), Vector2(7.0, 2.2), 0.0,
		_neon(CYAN, AQUA, 41), "OperaWaterfrontDisplay")
	_add_light(root, Vector3(opera.x, 12.0, opera.y + 20.0), AQUA, 1.8)

	# Harbour Bridge: deck-edge lighting along the real route, no silhouette change.
	if bridge != null:
		var route: Array = bridge.get("route")
		var east: Array = bridge.get("route_east")
		if route.size() > 10 and east.size() == route.size():
			var step := maxi(3, route.size() / 14)
			for i in range(0, route.size(), step):
				var p: Vector3 = route[i]
				var e: Vector3 = east[i]
				for side in [-1.0, 1.0]:
					var side_f: float = float(side)
					var lamp_pos: Vector3 = p + e * side_f * 11.0 + Vector3.UP * 1.3
					var lamp := _box(root, lamp_pos, Vector3(0.3, 0.12, 0.3), CYAN, 1.5)
					lamp.name = "BridgeDeckLight_%d_%d" % [i, int(side)]

	# Circular Quay: digital transport information at the real wharf locations.
	for i in 2:
		var qx := 251.4 if i == 0 else 190.7
		var qz := -1292.3 if i == 0 else -1273.8
		_quad(root, Vector3(qx, 3.4, qz), Vector2(5.0, 1.8), 0.0,
			_neon(AQUA, CYAN, 51 + i), "QuayTransportBoard_%d" % i)

	# Town Hall + QVB: heritage facades retrofitted with restrained signage.
	var th := _building_center(world_data, "way/104948253")
	var qvb := _building_center(world_data, "way/40717424")
	for pair in [{"c": th, "name": "TownHall"}, {"c": qvb, "name": "QVB"}]:
		var c: Vector2 = pair["c"]
		if c == Vector2.ZERO:
			continue
		_quad(root, Vector3(c.x, 5.0, c.y + 24.0), Vector2(6.0, 1.6), 0.0,
			_neon(AMBER, CYAN, 61), "Retrofit_%s" % pair["name"])
		_add_light(root, Vector3(c.x, 4.0, c.y + 20.0), AMBER, 1.2)

	# Central Station: major transport digital signage.
	var central := _building_center(world_data, "way/270319610")
	if central == Vector2.ZERO:
		central = Vector2(-174.7, 1156.8)
	_quad(root, Vector3(central.x, 4.0, central.y + 8.0), Vector2(8.0, 2.0), 0.0,
		_neon(CYAN, AQUA, 71), "CentralDigitalBoard")

	# Hyde Park / St Mary's: quiet path illumination, no signage clutter.
	var st_marys := _building_center(world_data, "way/16749128")
	if st_marys != Vector2.ZERO:
		for i in 3:
			_box(root, Vector3(st_marys.x - 20.0 + float(i) * 20.0, 0.5, st_marys.y + 40.0),
				Vector3(0.16, 1.0, 0.16), AQUA, 0.9)
