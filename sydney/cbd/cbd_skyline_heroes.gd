extends Node3D

## A small set of authored "future retrofit" skyline landmarks.
##
## The city-wide neon system dresses many towers with light strips, but thin
## strips alone did not produce a convincing skyline. This module builds a
## handful of genuine architectural silhouettes — stepped illuminated crowns,
## rooftop structures and facade-integrated light panels — on real OSM building
## footprints. Presentation only: no collision, roads or navigation are changed.

const TOWER_SHADER := preload("res://shaders/tower_panel.gdshader")
const NEON_SHADER := preload("res://shaders/neon_panel.gdshader")

const CYAN := Color("19e6ff")
const BLUE := Color("3a7bff")
const MAGENTA := Color("ff2e88")
const VIOLET := Color("a95cff")
const AMBER := Color("ffae32")
const AQUA := Color("38ffc8")

## One hero per key skyline district; selected by tallest footprint at runtime.
const HERO_DISTRICTS := [
	{"id": "cbd-core", "color": CYAN, "crown": 0},
	{"id": "barangaroo", "color": BLUE, "crown": 1},
	{"id": "town-hall", "color": AQUA, "crown": 2},
	{"id": "martin-place", "color": CYAN, "crown": 3},
	{"id": "circular-quay", "color": AQUA, "crown": 1},
	{"id": "darling-quarter", "color": MAGENTA, "crown": 2},
	{"id": "haymarket", "color": VIOLET, "crown": 0},
	{"id": "central", "color": CYAN, "crown": 3},
	{"id": "surry-hills", "color": AMBER, "crown": 1},
	{"id": "kings-cross", "color": MAGENTA, "crown": 2},
]

var stats: Dictionary = {}
var _materials: Dictionary = {}
var _night_factor := 0.0
var _time_mgr: Node = null


func build(world_data: Dictionary) -> void:
	name = "SkylineHeroes"
	var by_district: Dictionary = {}
	for row in world_data.get("buildings", []):
		var district := str(row.get("district", ""))
		if district.is_empty():
			continue
		if not by_district.has(district):
			by_district[district] = []
		(by_district[district] as Array).append(row)

	var built := 0
	for spec in HERO_DISTRICTS:
		var district_id: String = spec["id"]
		if not by_district.has(district_id):
			continue
		var rows: Array = by_district[district_id]
		rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a.get("heightM", 0.0)) > float(b.get("heightM", 0.0)))
		if rows.is_empty():
			continue
		var row: Dictionary = rows[0]
		var rect := _bounds(row)
		if rect.size.x < 6.0 or rect.size.y < 6.0:
			continue
		_build_hero(row, rect, spec, built)
		built += 1

	call_deferred("_wire_clock")
	_apply_night_factor(_night_factor)
	stats = {"heroTowers": built, "materials": _materials.size()}


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


func _panel_material(color: Color, rows: float, cols: float, band: float, seed: float) -> ShaderMaterial:
	var key := "p:%s|%d|%d|%d|%d" % [color.to_html(false), int(rows), int(cols), int(band * 10.0), int(seed)]
	if _materials.has(key):
		return _materials[key]
	var m := ShaderMaterial.new()
	m.shader = TOWER_SHADER
	m.set_shader_parameter("shell_color", Color("050a10"))
	m.set_shader_parameter("light_color", color)
	m.set_shader_parameter("rows", rows)
	m.set_shader_parameter("cols", cols)
	m.set_shader_parameter("lit_ratio", 0.68)
	m.set_shader_parameter("band_mode", band)
	m.set_shader_parameter("night_factor", _night_factor)
	m.set_shader_parameter("seed", seed)
	_materials[key] = m
	return m


func _neon_material(color: Color) -> ShaderMaterial:
	var key := "n:" + color.to_html(false)
	if _materials.has(key):
		return _materials[key]
	var m := ShaderMaterial.new()
	m.shader = NEON_SHADER
	m.set_shader_parameter("panel_color", color)
	m.set_shader_parameter("accent_color", color)
	m.set_shader_parameter("night_factor", _night_factor)
	m.set_shader_parameter("solid_glow", 1.0)
	m.set_shader_parameter("glow_strength", 1.4)
	_materials[key] = m
	return m


## Facade panel plane. QuadMesh stands vertically under a yaw rotation; the
## previous horizontal PlaneMesh laid every "facade" panel flat, so the hero
## towers never received their light panels.
func _quad(parent: Node3D, pos: Vector3, size: Vector2, yaw: float, material: Material) -> void:
	var mesh := MeshInstance3D.new()
	var plane := QuadMesh.new()
	plane.size = size
	mesh.mesh = plane
	mesh.material_override = material
	parent.add_child(mesh)
	mesh.position = pos
	mesh.rotation.y = yaw


func _box(parent: Node3D, pos: Vector3, size: Vector3, color: Color, emission: float = 0.0) -> void:
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


func _build_hero(row: Dictionary, rect: Rect2, spec: Dictionary, index: int) -> void:
	var color: Color = spec["color"]
	var crown_style: int = int(spec["crown"])
	var height := float(row.get("heightM", 60.0))
	var centre := rect.get_center()
	var name_str := str(row.get("name", "")) if not str(row.get("name", "")).is_empty() else str(row.get("id", "tower"))

	var hero := Node3D.new()
	hero.name = "HeroTower_%d_%s" % [index, name_str.replace(" ", "_").replace("/", "_")]
	hero.position = Vector3(centre.x, 0.0, centre.y)
	add_child(hero)

	# Stepped retrofit volume above the existing roof. Three tiers with
	# progressively smaller footprints create a real skyline silhouette.
	var tier_w := [minf(rect.size.x * 1.10, 48.0), minf(rect.size.x * 0.85, 36.0), minf(rect.size.x * 0.60, 24.0)]
	var tier_h := [26.0, 20.0, 15.0]
	var y := height - 1.5
	for tier in 3:
		var w: float = tier_w[tier]
		var d: float = minf(rect.size.y * (1.10 - float(tier) * 0.25), w)
		var h: float = tier_h[tier]
		var band_mode := 1.0 if tier == 1 else 0.0
		var mat := _panel_material(color, h / 2.2, maxf(3.0, w / 3.0), band_mode, float(index * 3 + tier))
		_box(hero, Vector3(0.0, y + h * 0.5, 0.0), Vector3(w, h, d), Color("050910"))
		# Four facade-integrated light panels, one per face.
		_quad(hero, Vector3(0.0, y + h * 0.5, d * 0.5 + 0.06), Vector2(w * 0.94, h * 0.9), 0.0, mat)
		_quad(hero, Vector3(0.0, y + h * 0.5, -d * 0.5 - 0.06), Vector2(w * 0.94, h * 0.9), PI, mat)
		_quad(hero, Vector3(w * 0.5 + 0.06, y + h * 0.5, 0.0), Vector2(d * 0.94, h * 0.9), PI * 0.5, mat)
		_quad(hero, Vector3(-w * 0.5 - 0.06, y + h * 0.5, 0.0), Vector2(d * 0.94, h * 0.9), -PI * 0.5, mat)
		y += h

	# Distinctive crown per hero tower.
	match crown_style:
		0:
			# Spire + stacked light rings.
			for i in 3:
				var r := 6.0 - float(i) * 1.6
				_box(hero, Vector3(0.0, y + float(i) * 4.0, 0.0), Vector3(r, 0.5, r), color, 1.6)
				_quad(hero, Vector3(0.0, y + float(i) * 4.0 + 1.2, 0.0), Vector2(r * 0.8, 1.6), 0.0, _neon_material(color))
				_quad(hero, Vector3(0.0, y + float(i) * 4.0 + 1.2, 0.0), Vector2(r * 0.8, 1.6), PI * 0.5, _neon_material(color))
			_box(hero, Vector3(0.0, y + 14.0, 0.0), Vector3(0.4, 16.0, 0.4), Color("303840"))
		1:
			# Corporate halo ring + antenna array.
			for i in 4:
				var a := float(i) * PI * 0.5
				_quad(hero, Vector3(cos(a) * 9.0, y + 3.0, sin(a) * 9.0), Vector2(12.0, 3.0), a + PI * 0.5, _neon_material(color))
			_box(hero, Vector3(0.0, y + 6.0, 0.0), Vector3(0.35, 12.0, 0.35), Color("303840"))
		2:
			# Blade crown: two tall illuminated fins.
			for side in [-1.0, 1.0]:
				_box(hero, Vector3(side * 5.0, y + 6.0, 0.0), Vector3(1.0, 14.0, 8.0), Color("0a1016"))
				_quad(hero, Vector3(side * 5.6, y + 6.0, 0.0), Vector2(7.0, 12.0), PI * 0.5, _neon_material(color))
		3:
			# stepped transmission mast with beacon bands.
			for i in 3:
				_box(hero, Vector3(0.0, y + float(i) * 5.0, 0.0), Vector3(4.0 - float(i), 2.4, 4.0 - float(i)), Color("0a1016"))
				_quad(hero, Vector3(0.0, y + float(i) * 5.0 + 1.3, 2.2), Vector2(3.0, 0.8), 0.0, _neon_material(color))


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
	for material in _materials.values():
		var sm := material as ShaderMaterial
		if sm != null:
			if sm.shader == TOWER_SHADER:
				sm.set_shader_parameter("night_factor", _night_factor)
			elif sm.shader == NEON_SHADER:
				sm.set_shader_parameter("night_factor", _night_factor)
