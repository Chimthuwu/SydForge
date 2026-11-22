extends Node3D

## ARCHITECTURAL CBD VERTICAL SLICE
##
## Rebuilds a representative CBD block's facades with genuine geometric detail:
## recessed window bays, structural mullions/fins, floor slabs, podium
## arcades, balcony bands and rooftop plant. Uses the real OSM footprints and
## heights — the underlying collision and navigation are untouched.
##
## Only this block is upgraded (an explicit acceptance gate). City-wide rollout
## happens only after this slice passes visual + performance review.

const ARCH_SHADER := preload("res://shaders/architecture.gdshader")
const MeshBuilder := preload("res://sydney/sydney_mesh.gd")

const SLICE_RECT := Rect2(-220.0, -520.0, 340.0, 340.0)
const STOREY := 3.4

# Material-family alpha tags consumed by architecture.gdshader.
const FAM_GLASS := 0.15
const FAM_FRAME := 0.35
const FAM_STONE := 0.55
const FAM_METAL := 0.75
const FAM_CONCRETE := 0.95

## Backing/window tint. architecture.gdshader multiplies glass by 0.48, so the
## raw shell colour would read as a black hole; this keeps the glazing legible.
const GLAZING := Color("466b7c")
const CORPORATE_WALL := Color("2c3941")
const RETAIL_STONE := Color("6a5c49")
const BRICK_WALL := Color("54362a")
const FRAME_METAL := Color("263036")
const FRAME_LIGHT := Color("4d585e")
const CONCRETE := Color("43443f")

var stats: Dictionary = {}
var _material: ShaderMaterial
var _night_factor := 0.0
var _time_mgr: Node = null
var _upgraded: Dictionary = {}


func build(world_data: Dictionary) -> void:
	name = "ArchitectureSlice"
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := 0
	var triangles := 0
	for row in world_data.get("buildings", []):
		var ring: PackedVector2Array = MeshBuilder._clean_ring(row.get("ring", []))
		if ring.size() < 3:
			continue
		var c := Vector2.ZERO
		for p in ring:
			c += p
		c /= ring.size()
		var height := clampf(float(row.get("heightM", 10.0)), 8.0, 240.0)
		var detailed := SLICE_RECT.has_point(c)
		# Only the reviewed slice gets added geometry. The earlier city-wide
		# "simple facade" tier stood dark bars and floor bands proud of the flat
		# legacy shell with no glazing behind them, which is exactly the reported
		# scaffolding-wrapped-building look. Elsewhere the facade shader's own
		# aligned windows and mullions remain the surface treatment.
		if not detailed:
			continue
		var style := str(row.get("style", "stone-commercial"))
		var id := str(row.get("id", ""))
		if id.is_empty() or _upgraded.has(id):
			continue
		_upgraded[id] = true
		triangles += _emit_building(surface, ring, height, style, absi(id.hash()), detailed)
		count += 1

	var mesh := surface.commit()
	if mesh != null and mesh.get_surface_count() > 0:
		_material = ShaderMaterial.new()
		_material.shader = ARCH_SHADER
		_material.set_shader_parameter("night_factor", _night_factor)
		mesh.surface_set_material(0, _material)
		var instance := MeshInstance3D.new()
		instance.name = "ArchitectureSliceMesh"
		instance.mesh = mesh
		add_child(instance)

	call_deferred("_wire_clock")
	_apply_night_factor(_night_factor)
	stats = {"buildings": count, "triangles": triangles, "rect": str(SLICE_RECT)}


# ---------------------------------------------------------------------------
# Mesh helpers
# ---------------------------------------------------------------------------

func _tri(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3, color: Color) -> void:
	surface.set_normal(normal)
	surface.set_color(color)
	surface.add_vertex(a)
	surface.set_normal(normal)
	surface.set_color(color)
	surface.add_vertex(b)
	surface.set_normal(normal)
	surface.set_color(color)
	surface.add_vertex(c)


func _quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3, color: Color) -> int:
	_tri(surface, a, b, c, normal, color)
	_tri(surface, a, c, d, normal, color)
	return 2


## A world-space box, six faces, with per-face colour tag. Used for mullions,
## floor slabs, fins, balcony rails and rooftop equipment.
func _box(surface: SurfaceTool, center: Vector3, size: Vector3, color: Color) -> int:
	var h := size * 0.5
	var x0 := center.x - h.x
	var x1 := center.x + h.x
	var y0 := center.y - h.y
	var y1 := center.y + h.y
	var z0 := center.z - h.z
	var z1 := center.z + h.z
	var total := 0
	total += _quad(surface, Vector3(x0,y1,z1), Vector3(x1,y1,z1), Vector3(x1,y0,z1), Vector3(x0,y0,z1), Vector3.FORWARD, color)
	total += _quad(surface, Vector3(x1,y1,z0), Vector3(x0,y1,z0), Vector3(x0,y0,z0), Vector3(x1,y0,z0), Vector3.BACK, color)
	total += _quad(surface, Vector3(x1,y1,z1), Vector3(x1,y1,z0), Vector3(x1,y0,z0), Vector3(x1,y0,z1), Vector3.RIGHT, color)
	total += _quad(surface, Vector3(x0,y1,z0), Vector3(x0,y1,z1), Vector3(x0,y0,z1), Vector3(x0,y0,z0), Vector3.LEFT, color)
	total += _quad(surface, Vector3(x0,y1,z1), Vector3(x0,y1,z0), Vector3(x1,y1,z0), Vector3(x1,y1,z1), Vector3.UP, color)
	total += _quad(surface, Vector3(x0,y0,z0), Vector3(x0,y0,z1), Vector3(x1,y0,z1), Vector3(x1,y0,z0), Vector3.DOWN, color)
	return total


# ---------------------------------------------------------------------------
# Building families
# ---------------------------------------------------------------------------

func _emit_building(surface: SurfaceTool, ring: PackedVector2Array, height: float, style: String, variant: int, detailed: bool = true) -> int:
	var total := 0
	var is_tower := style == "glass-tower" or height > 55.0
	var is_retail := style in ["retail", "stone-commercial"]
	var is_brick := style in ["brick-commercial", "terrace", "warehouse"]

	# Wall base colour chosen per family; alpha tags the shader material type.
	var wall := CORPORATE_WALL if is_tower else (RETAIL_STONE if is_retail else BRICK_WALL)
	wall.a = FAM_CONCRETE if is_brick else FAM_STONE
	var glass := GLAZING
	glass.a = FAM_GLASS
	var frame := FRAME_METAL.darkened(0.18)
	frame.a = FAM_FRAME

	# 1. Opaque backing panels sit just outside the legacy shell. They hide the
	#    old flat facade shader in this block so the new architecture reads as a
	#    complete designed building, not decoration over an old grid. Towers get
	#    glazing behind their mullions; masonry keeps its wall tone and gains
	#    real window glass in _emit_masonry_facade.
	var backing := glass if is_tower else wall
	total += _emit_backing(surface, ring, height, backing)

	# 2. Per-edge facade systems: piers, floor bands, recessed glazing bays.
	var floors := clampi(int(height / STOREY), 2, 56)
	for i in ring.size():
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		var edge := b - a
		var length := edge.length()
		if length < 2.5:
			continue
		var tangent := edge.normalized()
		var orientation := signf(MeshBuilder._signed_area(ring))
		var outward := Vector2(edge.y, -edge.x).normalized() * orientation
		var normal := Vector3(outward.x, 0.0, outward.y)

		if is_tower:
			if detailed:
				total += _emit_curtain_wall(surface, a, b, tangent, outward, height, floors, glass, frame, variant + i)
			else:
				total += _emit_simple_facade(surface, a, b, tangent, outward, height, floors, frame)
		elif is_retail:
			if detailed:
				total += _emit_masonry_facade(surface, a, b, tangent, outward, height, floors, wall, frame, variant + i, true)
			else:
				total += _emit_simple_facade(surface, a, b, tangent, outward, height, floors, frame)
		else:
			if detailed:
				total += _emit_masonry_facade(surface, a, b, tangent, outward, height, floors, wall, frame, variant + i, false)
			else:
				total += _emit_simple_facade(surface, a, b, tangent, outward, height, floors, frame)

	# 3. Podium / shopfront arcade for street-facing taller buildings.
	if detailed and height > 24.0:
		total += _emit_podium(surface, ring, height, is_tower, variant)

	# 4. Distinctive rooftop architecture.
	if detailed or height > 70.0:
		total += _emit_roof_structure(surface, ring, height, is_tower, variant)
	return total


## Full-height facade backing panels, offset 6 cm outside the legacy shell.
func _emit_backing(surface: SurfaceTool, ring: PackedVector2Array, height: float, wall: Color) -> int:
	var total := 0
	var orientation := signf(MeshBuilder._signed_area(ring))
	for i in ring.size():
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		var edge := b - a
		if edge.length() < 0.2:
			continue
		var outward := Vector2(edge.y, -edge.x).normalized() * orientation
		var oa := a + outward * 0.06
		var ob := b + outward * 0.06
		var n := Vector3(outward.x, 0.0, outward.y)
		total += _quad(surface, Vector3(oa.x, 0.0, oa.y), Vector3(ob.x, 0.0, ob.y),
			Vector3(ob.x, height, ob.y), Vector3(oa.x, height, oa.y), n, wall)
	return total


func _emit_shell(surface: SurfaceTool, ring: PackedVector2Array, height: float, wall: Color) -> int:
	var total := 0
	var orientation := signf(MeshBuilder._signed_area(ring))
	for i in ring.size():
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		var edge := b - a
		if edge.length() < 0.1:
			continue
		var outward := Vector2(edge.y, -edge.x).normalized() * orientation
		var normal := Vector3(outward.x, 0.0, outward.y)
		total += _quad(surface, Vector3(a.x,0,a.y), Vector3(b.x,0,b.y),
			Vector3(b.x,height,b.y), Vector3(a.x,height,a.y), normal, wall)
	# Roof cap
	var indices := Geometry2D.triangulate_polygon(ring)
	for j in range(0, indices.size(), 3):
		var a: Vector2 = ring[indices[j]]
		var b: Vector2 = ring[indices[j + 1]]
		var c: Vector2 = ring[indices[j + 2]]
		_tri(surface, Vector3(a.x,height,a.y), Vector3(b.x,height,b.y), Vector3(c.x,height,c.y), Vector3.UP, wall)
		total += 1
	return total


## A quad in facade-local space: width along the edge tangent, height up,
## facing outward. All facade elements use this so diagonal edges stay aligned.
func _fquad(surface: SurfaceTool, center: Vector3, tangent: Vector2, outward: Vector2, width: float, tall: float, color: Color) -> int:
	var n := Vector3(outward.x, 0.0, outward.y)
	var half := tangent * (width * 0.5)
	var p0 := Vector3(center.x - half.x, center.y - tall * 0.5, center.z - half.y)
	var p1 := Vector3(center.x + half.x, center.y - tall * 0.5, center.z + half.y)
	var p2 := Vector3(center.x + half.x, center.y + tall * 0.5, center.z + half.y)
	var p3 := Vector3(center.x - half.x, center.y + tall * 0.5, center.z - half.y)
	return _quad(surface, p0, p1, p2, p3, n, color)


func _emit_curtain_wall(surface: SurfaceTool, a: Vector2, b: Vector2, tangent: Vector2, outward: Vector2, height: float, floors: int, glass: Color, frame: Color, variant: int) -> int:
	var total := 0
	var length: float = (b - a).length()
	var bays := clampi(int(length / 2.6), 1, 18)
	var bay_w := length / float(bays)
	var n := Vector3(outward.x, 0.0, outward.y)
	var offset := 0.10
	var rng := RandomNumberGenerator.new()
	rng.seed = variant * 977 + 7

	# Vertical mullions and floor spandrel bands naturally divide the facade.
	for bay in bays:
		var p := a + tangent * (bay_w * (float(bay) + 0.5))
		var gx := p.x + outward.x * offset
		var gz := p.y + outward.y * offset
		# Glazing itself is left to the existing facade shader so its lit
		# windows remain visible; this layer supplies the structural frame only.

	# Spandrel / floor slabs as proud horizontal bands along the real edge.
	for floor in range(1, floors):
		var y := float(floor) * STOREY
		var c := (a + b) * 0.5 + outward * (offset + 0.06)
		total += _fquad(surface, Vector3(c.x, y, c.y), tangent, outward, length, 0.30, frame)
	# Mullions between bays, with deeper structural fins every third bay so the
	# curtain wall has real depth and casts shadow lines down the facade.
	for bay in range(bays + 1):
		var p := a + tangent * (bay_w * float(bay)) + outward * (offset + 0.14)
		total += _fquad(surface, Vector3(p.x, height * 0.5, p.y), tangent, outward, 0.18, height, frame)
		if bay % 3 == 0:
			var fin := p + outward * 0.42
			var fin_top := Vector3(fin.x, height + 0.2, fin.y)
			var fin_bot := Vector3(fin.x, 0.2, fin.y)
			var root_top := Vector3(p.x, height + 0.2, p.y)
			var root_bot := Vector3(p.x, 0.2, p.y)
			# Fin front face and one side face give a projecting blade.
			total += _fquad(surface, Vector3(fin.x, height * 0.5, fin.y), tangent, outward, 0.34, height, frame)
			var side_n := Vector3(tangent.x, 0.0, tangent.y)
			total += _quad(surface, root_bot, fin_bot, fin_top, root_top, side_n, frame)
	return total


## Cheap tier for distant tall buildings: backing panel plus structural floor
## bands and vertical piers. No per-window geometry, so the city-wide rollout
## stays within a sensible triangle budget.
func _emit_simple_facade(surface: SurfaceTool, a: Vector2, b: Vector2, tangent: Vector2, outward: Vector2, height: float, floors: int, frame: Color) -> int:
	var total := 0
	var length: float = (b - a).length()
	var c := (a + b) * 0.5 + outward * 0.10
	for floor in range(1, floors, 2):
		var y := float(floor) * STOREY
		total += _fquad(surface, Vector3(c.x, y, c.y), tangent, outward, length, 0.34, frame)
	var piers := clampi(int(length / 6.0), 1, 6)
	for i in piers + 1:
		var p := a + tangent * (length * float(i) / float(piers)) + outward * 0.14
		total += _fquad(surface, Vector3(p.x, height * 0.5, p.y), tangent, outward, 0.36, height, frame)
	return total


func _emit_masonry_facade(surface: SurfaceTool, a: Vector2, b: Vector2, tangent: Vector2, outward: Vector2, height: float, floors: int, wall: Color, frame: Color, variant: int, heritage: bool) -> int:
	var total := 0
	var length: float = (b - a).length()
	var windows := clampi(int(length / 3.0), 1, 14)
	var win_w := minf(1.2, length / float(windows) * 0.52)
	var n := Vector3(outward.x, 0.0, outward.y)
	var offset := 0.09
	var glass := GLAZING
	glass.a = FAM_GLASS
	var rng := RandomNumberGenerator.new()
	rng.seed = variant * 613 + 11

	for floor in floors:
		var y0 := float(floor) * STOREY + 0.9
		if y0 + 1.5 > height - 0.6:
			break
		for w in windows:
			var p := a + tangent * (length * (float(w) + 0.5) / float(windows)) + outward * offset
			var gx := p.x
			var gz := p.y
			var frame_c := frame.lightened(0.12) if heritage else frame
			# The opaque backing hides the old facade shader, so emit the glazing
			# itself behind the sill/head frames instead of letting the legacy
			# procedural window grid show through the structural layer.
			var wc := p - outward * offset + outward * 0.075
			total += _fquad(surface, Vector3(wc.x, y0 + 0.75, wc.y), tangent, outward, win_w, 1.42, glass)
			total += _fquad(surface, Vector3(gx, y0 - 0.06, gz), tangent, outward, win_w + 0.30, 0.14, frame_c)
			total += _fquad(surface, Vector3(gx, y0 + 1.52, gz), tangent, outward, win_w + 0.24, 0.14, frame_c)
	return total


func _emit_podium(surface: SurfaceTool, ring: PackedVector2Array, height: float, tower: bool, variant: int) -> int:
	var total := 0
	var podium_h := 5.4 if tower else 4.2
	var orientation := signf(MeshBuilder._signed_area(ring))
	for i in ring.size():
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		var edge := b - a
		if edge.length() < 3.0:
			continue
		var outward := Vector2(edge.y, -edge.x).normalized() * orientation
		var tangent := edge.normalized()
		var c := (a + b) * 0.5 + outward * 0.22
		# Fascia band + glazing reads as a shopfront at street level.
		total += _fquad(surface, Vector3(c.x, podium_h, c.y), tangent, outward, edge.length(), 0.36,
			FRAME_LIGHT if tower else Color("8b7a5f"))
		total += _fquad(surface, Vector3(c.x, 2.1, c.y), tangent, outward,
			minf(3.0, edge.length() * 0.4), 2.6, Color("24333c"))
	return total


func _emit_roof_structure(surface: SurfaceTool, ring: PackedVector2Array, height: float, tower: bool, variant: int) -> int:
	var total := 0
	var c := Vector2.ZERO
	for p in ring:
		c += p
	c /= ring.size()
	if tower:
		# Stepped plant deck, antenna mast and parapet — a real roof silhouette.
		var w := minf(rect_width(ring) * 0.55, 18.0)
		var d := minf(rect_height(ring) * 0.55, 18.0)
		total += _box(surface, Vector3(c.x, height + 2.0, c.y), Vector3(w, 4.0, d), CONCRETE)
		total += _box(surface, Vector3(c.x, height + 5.2, c.y), Vector3(w * 0.5, 2.4, d * 0.5), FRAME_METAL)
		total += _box(surface, Vector3(c.x, height + 10.0, c.y), Vector3(0.3, 8.0, 0.3), FRAME_LIGHT)
	else:
		# Low-rise rooftop machinery + parapet band.
		total += _box(surface, Vector3(c.x, height + 1.2, c.y), Vector3(4.0, 2.4, 3.0), FRAME_METAL)
		total += _box(surface, Vector3(c.x + 3.0, height + 0.7, c.y + 2.0), Vector3(2.0, 1.4, 2.0), CONCRETE)
	return total


func rect_width(ring: PackedVector2Array) -> float:
	var lo := INF
	var hi := -INF
	for p in ring:
		lo = minf(lo, p.x)
		hi = maxf(hi, p.x)
	return hi - lo


func rect_height(ring: PackedVector2Array) -> float:
	var lo := INF
	var hi := -INF
	for p in ring:
		lo = minf(lo, p.y)
		hi = maxf(hi, p.y)
	return hi - lo


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
	if _material != null:
		_material.set_shader_parameter("night_factor", _night_factor)
