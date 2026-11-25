extends Node3D

## District anchor installations for the underdressed areas.
##
## Rather than adding more repetitive neon panels, each district gets one or two
## designed structures that establish identity: a transport information monument,
## a heritage retrofit arch, a corporate plaza canopy, or a nightlife gateway.
## Presentation only; no collision or navigation changes.

const NEON_SHADER := preload("res://shaders/neon_panel.gdshader")
const HOLO_SHADER := preload("res://shaders/hologram.gdshader")

const CYAN := Color("19e6ff")
const BLUE := Color("3a7bff")
const MAGENTA := Color("ff2e88")
const RED := Color("ff4438")
const AMBER := Color("ffae32")
const AQUA := Color("38ffc8")

var stats: Dictionary = {}
var _materials: Dictionary = {}
var _night_factor := 0.0
var _time_mgr: Node = null


func build() -> void:
	name = "DistrictAnchors"
	_quay(Vector2(173.2, -1506.4))
	_rocks(Vector2(17.6, -1528.3))
	_barangaroo(Vector2(-618.4, -1196.5))
	_central(Vector2(-75.7, 1067.9))
	_darling_quarter(Vector2(-601.0, 22.2))
	_chinatown(Vector2(-425.8, 686.8))
	_surry_hills(Vector2(273.8, 1713.7))
	_kings_cross(Vector2(1499.0, 44.5))
	call_deferred("_wire_clock")
	_apply_night_factor(_night_factor)
	stats = {"installations": 8, "materials": _materials.size()}


func _neon(color: Color, accent: Color, seed: int) -> ShaderMaterial:
	var key := "n:%s|%s|%d" % [color.to_html(false), accent.to_html(false), seed % 4]
	if _materials.has(key): return _materials[key]
	var m := ShaderMaterial.new()
	m.shader = NEON_SHADER
	m.set_shader_parameter("panel_color", color)
	m.set_shader_parameter("accent_color", accent)
	m.set_shader_parameter("seed", float(seed % 4))
	m.set_shader_parameter("night_factor", _night_factor)
	_materials[key] = m
	return m


func _holo(color: Color, seed: int, alpha: float) -> ShaderMaterial:
	var key := "h:%s|%d" % [color.to_html(false), seed % 4]
	if _materials.has(key): return _materials[key]
	var m := ShaderMaterial.new()
	m.shader = HOLO_SHADER
	m.set_shader_parameter("holo_color", color)
	m.set_shader_parameter("seed", float(seed % 4))
	m.set_shader_parameter("alpha_strength", alpha)
	m.set_shader_parameter("night_factor", _night_factor)
	_materials[key] = m
	return m


## Wall-mounted sign plane. QuadMesh stands upright under a yaw rotation; a
## horizontal PlaneMesh laid these screens flat on the ground.
func _quad(parent: Node3D, pos: Vector3, size: Vector2, yaw: float, mat: Material) -> void:
	var mesh := MeshInstance3D.new()
	var plane := QuadMesh.new()
	plane.size = size
	mesh.mesh = plane
	mesh.material_override = mat
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


func _anchor(name: String, at: Vector2) -> Node3D:
	var node := Node3D.new()
	node.name = name
	node.position = Vector3(at.x, 0.0, at.y)
	add_child(node)
	return node


func _quay(at: Vector2) -> void:
	# Futuristic ferry information monument, placed directly ahead of the
	# authored Circular Quay viewpoint and facing back toward the player.
	var q := _anchor("QuayTransportMonument", at)
	q.rotation.y = 1.816  # authored viewpoint yaw: +Z locally faces the camera
	_box(q, Vector3(0.0, 2.0, -0.6), Vector3(3.6, 4.0, 0.6), Color("161e26"))
	_quad(q, Vector3(0.0, 2.7, -0.25), Vector2(2.8, 1.7), 0.0, _neon(AQUA, CYAN, 2))
	_quad(q, Vector3(0.0, 1.1, -0.25), Vector2(2.8, 0.9), 0.0, _neon(CYAN, BLUE, 3))
	_quad(q, Vector3(0.0, 3.2, 0.6), Vector2(2.4, 2.4), 0.0, _holo(AQUA, 4, 0.34))
	for i in 5:
		_box(q, Vector3(-8.0 + float(i) * 4.0, 0.13, 2.6), Vector3(3.0, 0.06, 0.08), AQUA, 1.3)


func _rocks(at: Vector2) -> void:
	# Sandstone heritage retrofit: warm amber gateway and hanging cable runs.
	var r := _anchor("RocksHeritageRetrofit", at)
	for side in [-1.0, 1.0]:
		_box(r, Vector3(side * 4.6, 2.3, 0.0), Vector3(0.35, 4.6, 0.35), Color("4a4034"))
	_box(r, Vector3(0.0, 4.7, 0.0), Vector3(9.6, 0.30, 0.4), Color("4a4034"))
	_quad(r, Vector3(0.0, 4.7, 0.25), Vector2(8.5, 0.5), 0.0, _neon(AMBER, CYAN, 7))
	_quad(r, Vector3(-4.35, 2.4, 0.0), Vector2(0.4, 3.8), -PI * 0.5, _neon(AMBER, Color("e8f6ff"), 8))
	_quad(r, Vector3(4.35, 2.4, 0.0), Vector2(0.4, 3.8), PI * 0.5, _neon(AMBER, Color("e8f6ff"), 9))
	# Service cables retrofitted along the heritage street.
	for i in 3:
		_box(r, Vector3(0.0, 3.0 + float(i) * 0.18, -0.3), Vector3(9.0, 0.035, 0.035), Color("1c1c1a"))


func _barangaroo(at: Vector2) -> void:
	# Corporate plaza: restrained blue light grid canopy + wayfinding monolith.
	var b := _anchor("BarangarooCorporatePlaza", at)
	for i in 5:
		_box(b, Vector3(-8.0 + float(i) * 4.0, 3.4, 0.0), Vector3(0.12, 0.12, 7.0), BLUE, 0.8)
	for i in 3:
		_box(b, Vector3(0.0, 3.4, -3.0 + float(i) * 3.0), Vector3(16.0, 0.12, 0.12), BLUE, 0.8)
	_box(b, Vector3(3.4, 1.6, 2.6), Vector3(0.35, 3.2, 1.6), Color("121820"))
	_quad(b, Vector3(3.15, 2.0, 2.6), Vector2(1.2, 1.8), -PI * 0.5, _neon(BLUE, CYAN, 12))


func _central(at: Vector2) -> void:
	# Major transport hub: large departures board and direction pylons.
	var c := _anchor("CentralTransportHub", at)
	_box(c, Vector3(0.0, 2.6, -2.4), Vector3(0.4, 5.2, 4.6), Color("151b22"))
	_quad(c, Vector3(0.25, 3.2, -2.4), Vector2(4.0, 2.2), PI * 0.5, _neon(CYAN, BLUE, 15))
	_quad(c, Vector3(0.27, 1.4, -2.4), Vector2(4.0, 0.7), PI * 0.5, _neon(AQUA, CYAN, 16))
	for side in [-1.0, 1.0]:
		_box(c, Vector3(side * 5.0, 1.5, 1.0), Vector3(0.25, 3.0, 0.25), Color("1a222a"))
		_quad(c, Vector3(side * 5.0, 2.3, 1.2), Vector2(0.9, 1.4), 0.0, _neon(AQUA, CYAN, 17))


func _darling_quarter(at: Vector2) -> void:
	# Entertainment quarter: large billboard and coloured promenade lighting.
	var d := _anchor("DarlingQuarterEntertainment", at)
	_quad(d, Vector3(0.0, 6.0, -3.0), Vector2(10.0, 4.5), 0.0, _neon(MAGENTA, CYAN, 20))
	for i in 4:
		_box(d, Vector3(-6.0 + float(i) * 4.0, 0.14, 0.0), Vector3(2.6, 0.06, 0.08), MAGENTA, 1.2)
	_quad(d, Vector3(3.0, 3.0, 0.0), Vector2(2.0, 2.6), 0.0, _holo(CYAN, 21, 0.32))


func _chinatown(at: Vector2) -> void:
	# Haymarket gateway: illuminated red/magenta arch.
	var h := _anchor("ChinatownGateway", at)
	for side in [-1.0, 1.0]:
		_box(h, Vector3(side * 4.0, 2.2, 0.0), Vector3(0.4, 4.4, 0.4), Color("3a1418"))
	_box(h, Vector3(0.0, 4.4, 0.0), Vector3(8.4, 0.35, 0.45), Color("3a1418"))
	_quad(h, Vector3(0.0, 4.4, 0.3), Vector2(7.6, 0.55), 0.0, _neon(RED, MAGENTA, 24))
	_quad(h, Vector3(0.0, 3.7, 0.3), Vector2(5.0, 0.35), 0.0, _neon(AMBER, RED, 25))


func _surry_hills(at: Vector2) -> void:
	# Converted industrial street: amber workshop sign and conduit runs.
	var s := _anchor("SurryHillsWorkshop", at)
	_box(s, Vector3(3.0, 2.4, 0.0), Vector3(0.3, 4.8, 2.4), Color("1b1815"))
	_quad(s, Vector3(2.8, 3.0, 0.0), Vector2(2.0, 1.4), -PI * 0.5, _neon(AMBER, CYAN, 28))
	for i in 3:
		_box(s, Vector3(0.0, 3.2 + float(i) * 0.16, -0.2), Vector3(7.0, 0.04, 0.04), Color("2a2420"))


func _kings_cross(at: Vector2) -> void:
	# The Cross's identity piece: a huge double-sided billboard on a pylon
	# above the intersection, in the classic red/amber/yellow stack.
	var k := _anchor("KingsCrossBillboard", at)
	_box(k, Vector3(0.0, 9.0, 0.0), Vector3(1.0, 10.0, 1.0), Color("1a1618"))
	_box(k, Vector3(0.0, 14.2, 0.0), Vector3(11.0, 0.5, 0.8), Color("1a1618"))
	_quad(k, Vector3(0.0, 11.6, -0.45), Vector2(10.5, 5.0), 0.0, _neon(RED, AMBER, 31))
	_quad(k, Vector3(0.0, 11.6, 0.45), Vector2(10.5, 5.0), PI, _neon(MAGENTA, RED, 32))
	# Wayfinding blades down the pylon, as for the nightlife strip.
	for i in 3:
		_quad(k, Vector3(0.55, 3.0 + float(i) * 1.4, 0.0), Vector2(0.8, 1.0), PI * 0.5, _neon(AMBER, RED, 33 + i))


func _wire_clock() -> void:
	if not is_inside_tree() or get_tree() == null:
		call_deferred("_wire_clock")
		return
	var mgrs := get_tree().get_nodes_in_group("time_managers")
	if not mgrs.is_empty(): _time_mgr = mgrs[0]
	if _time_mgr != null and _time_mgr.has_signal("lighting_factor_changed"):
		_time_mgr.connect("lighting_factor_changed", Callable(self, "_apply_night_factor"))
	if _time_mgr != null and "lighting_factor" in _time_mgr:
		_apply_night_factor(float(_time_mgr.get("lighting_factor")))


func _apply_night_factor(factor: float) -> void:
	_night_factor = clampf(factor, 0.0, 1.0)
	for material in _materials.values():
		var sm := material as ShaderMaterial
		if sm != null: sm.set_shader_parameter("night_factor", _night_factor)
