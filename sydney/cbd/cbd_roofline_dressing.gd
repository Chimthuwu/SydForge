extends Node3D

## City-wide rooftop clutter for the tall base shell (skyline L63 step).
##
## The hero towers carry authored crowns, but every other tower was a bare
## extruded prism, so the skyline read as thin neon lines over flat slabs.
## This dresses the remaining tall buildings with cheap industrial rooftop
## geometry — antenna masts with beacon tips, AC/plant blocks and water tanks
## — batched into three MultiMeshes so the draw-call budget barely moves.
## Presentation only: no collision, roads or navigation change.

const CONCRETE := Color("3c3f42")
const METAL := Color("262c31")
const TANK := Color("4a4640")
const BEACON := Color("ff3524")

const MIN_TOWER_HEIGHT := 18.0
const MAX_MASTS := 700
const MAX_PLANT := 3200
const MAX_TANKS := 500

var stats: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func build(world_data: Dictionary) -> void:
	name = "RooflineDressing"
	_rng.seed = 20261126  # deterministic layout: captures and cache keys stay stable
	var masts: Array[Transform3D] = []
	var plant: Array[Transform3D] = []
	var tanks: Array[Transform3D] = []
	var beacons: Array[Transform3D] = []

	# Each district's tallest building is a SkylineHeroes hero — leave it alone.
	var hero_height: Dictionary = {}
	for row in world_data.get("buildings", []):
		var district := str(row.get("district", ""))
		var h := float(row.get("heightM", 0.0))
		if not district.is_empty():
			hero_height[district] = maxf(float(hero_height.get(district, 0.0)), h)

	var dressed := 0
	for row in world_data.get("buildings", []):
		if dressed >= MAX_MASTS and plant.size() >= MAX_PLANT and tanks.size() >= MAX_TANKS:
			break
		var h := float(row.get("heightM", 0.0))
		if h < MIN_TOWER_HEIGHT:
			continue
		var district := str(row.get("district", ""))
		if not district.is_empty() and h >= float(hero_height.get(district, INF)):
			continue
		var rect := _bounds(row)
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue
		dressed += 1
		var cx := rect.get_center().x
		var cz := rect.get_center().y
		var roof := h
		var half_w := rect.size.x * 0.5
		var half_d := rect.size.y * 0.5
		var yaw := _rng.randf() * TAU

		# Antenna mast near a corner with a beacon tip.
		if masts.size() < MAX_MASTS:
			var mast_h := _rng.randf_range(4.0, 9.0)
			var ox := (_rng.randf() - 0.5) * half_w
			var oz := (_rng.randf() - 0.5) * half_d
			# Scale the BASIS only: Transform3D.scaled() would multiply the
			# origin as well and teleport the prop. Boxes are 1 m cubes centred
			# on their origin, so raise the origin to half the prop height.
			masts.append(_prop(Vector3(cx + ox, roof + mast_h * 0.5, cz + oz), 0.0, Vector3(0.3, mast_h, 0.3)))
			beacons.append(_prop(Vector3(cx + ox, roof + mast_h + 0.3, cz + oz), 0.0, Vector3(0.5, 0.6, 0.5)))
		# 1-3 plant blocks near the core.
		var blocks := 1 + _rng.randi() % 3
		for b in blocks:
			if plant.size() >= MAX_PLANT:
				break
			var ox := (_rng.randf() - 0.5) * half_w * 0.9
			var oz := (_rng.randf() - 0.5) * half_d * 0.9
			var sx := _rng.randf_range(1.6, 3.2)
			var sy := _rng.randf_range(1.0, 2.2)
			var sz := _rng.randf_range(1.6, 3.2)
			plant.append(_prop(Vector3(cx + ox, roof + sy * 0.5, cz + oz), yaw + _rng.randf() * 0.4 - 0.2, Vector3(sx, sy, sz)))
		# Occasional water tank on the bigger roofs.
		if h > 42.0 and tanks.size() < MAX_TANKS and _rng.randf() < 0.35:
			var ox := (_rng.randf() - 0.5) * half_w * 0.7
			var oz := (_rng.randf() - 0.5) * half_d * 0.7
			tanks.append(_prop(Vector3(cx + ox, roof + 1.1, cz + oz), 0.0, Vector3(2.2, 2.2, 2.2)))

	_add_multimesh("RoofMasts", _box_mesh(), METAL, masts)
	_add_multimesh("RoofPlant", _box_mesh(), CONCRETE, plant)
	_add_multimesh("RoofTanks", _cylinder_mesh(), TANK, tanks)
	var beacon_mat := StandardMaterial3D.new()
	beacon_mat.albedo_color = BEACON
	beacon_mat.emission_enabled = true
	beacon_mat.emission = BEACON
	beacon_mat.emission_energy_multiplier = 1.6
	_add_multimesh("RoofBeacons", _box_mesh(), BEACON, beacons, beacon_mat)

	stats = {
		"buildings_dressed": dressed,
		"masts": masts.size(),
		"plant": plant.size(),
		"tanks": tanks.size(),
		"nodes": 4,
	}


func _bounds(row: Dictionary) -> Rect2:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var count := 0
	for raw in row.get("ring", []):
		if typeof(raw) == TYPE_ARRAY and (raw as Array).size() >= 2:
			var p := Vector2(float(raw[0]), float(raw[1]))
			lo = lo.min(p)
			hi = hi.max(p)
			count += 1
	if count < 3:
		return Rect2()
	return Rect2(lo, hi - lo)


## Absolute transform for a prop: pos is the box centre, scale is baked into
## the basis so the origin survives untouched.
func _prop(pos: Vector3, yaw: float, scale: Vector3) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw).scaled(scale), pos)


func _box_mesh() -> BoxMesh:
	var mesh := BoxMesh.new()
	return mesh


func _cylinder_mesh() -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.height = 1.0
	mesh.radius = 0.5
	return mesh


func _add_multimesh(node_name: String, mesh: Mesh, color: Color, transforms: Array[Transform3D], material: StandardMaterial3D = null) -> void:
	if transforms.is_empty():
		return
	var mat := material
	if mat == null:
		mat = StandardMaterial3D.new()
		mat.albedo_color = color
	mesh.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
