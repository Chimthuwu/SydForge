extends RefCounted
## Facade decoration over the exact OSM shell. No change to footprint collision.
## Kit axes: X across bay, Y up, +Z exterior; metres, bottom-centred pivot.
const KIT := "res://sydney/architecture/megakit/"
const FACADE_OFFSET := 0.32 # Keep the kit's 0.26 m recessed backing outside the shell.
## Reviewed against Stage A roads/footpaths with a conservative 0.9 m envelope.
## Excludes the GPO landmark, which needs an authored facade rather than a kit.
const PILOT_IDS := ["way/620819399", "way/448339172", "way/335699128", "way/386563353", "way/1176087505", "way/547758509", "way/173542968"]
const MeshBuilder = preload("res://sydney/sydney_mesh.gd")
const MODULES := ["Brick_Window_Square_Single", "Brick_Window_CurvedDouble", "Trim_Window", "Trim_FirstFloor_Window_Columns", "Metal_FullWindow", "Metal_FirstFloor_Window", "Cornice_Trim_Center", "Prop_ACUnit"]
var batches: Dictionary = {}
var sources: Dictionary = {}

static func plan(row: Dictionary) -> Dictionary:
	var ring := MeshBuilder._clean_ring(row.get("ring", []))
	var height := float(row.get("heightM", 0.0))
	if ring.size() < 3 or height < 6.0 or height > 180.0 or not is_finite(height) or not row.get("holes", []).is_empty():
		return {}
	var area := MeshBuilder._signed_area(ring)
	if absf(area) < 20.0 or Geometry2D.triangulate_polygon(ring).is_empty():
		return {}
	var orientation := signf(area)
	for i in ring.size():
		var edge := ring[(i + 1) % ring.size()] - ring[i]
		var next := ring[(i + 2) % ring.size()] - ring[(i + 1) % ring.size()]
		if edge.length() < 2.5 or edge.cross(next) * orientation < -0.001:
			return {} # Concave and short-edge footprints keep the existing extrusion.
	var identity := str(row.get("id", ""))
	var seed_value := absi(identity.hash())
	var family := "glass" if height > 35.0 else ("stone" if seed_value % 2 == 0 else "brick")
	if row.get("architectureStyle", "") in ["glass", "stone", "brick"]:
		family = row.architectureStyle
	var floors := maxi(2, roundi(height / 3.2))
	var ground := minf(4.2, height / 2.0)
	var upper := (height - ground) / float(floors - 1)
	var bays: Array[Dictionary] = []
	for i in ring.size():
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		var tangent := (b - a).normalized()
		var outward := Vector2(tangent.y, -tangent.x) * orientation
		var width := a.distance_to(b)
		var count := maxi(1, roundi((width - 0.6) / (4.0 if family == "glass" else 2.2)))
		var bay_width := (width - 0.6) / count
		# Reverse X for clockwise rings to retain a right-handed basis.
		var x := -Vector3(tangent.x, 0, tangent.y) * orientation
		var z := Vector3(outward.x, 0, outward.y)
		var basis := Basis(x, Vector3.UP, z)
		for floor_index in floors:
			var y := 0.0 if floor_index == 0 else ground + (floor_index - 1) * upper
			var h := ground if floor_index == 0 else upper
			for bay in count:
				var center := a + tangent * (0.3 + (bay + 0.5) * bay_width) + outward * FACADE_OFFSET
				var module := "Metal_FirstFloor_Window" if family == "glass" else "Trim_FirstFloor_Window_Columns"
				if floor_index > 0:
					module = "Metal_FullWindow" if family == "glass" else "Trim_Window"
					if family == "brick":
						module = "Brick_Window_CurvedDouble" if (seed_value + bay + i * 3) % 4 == 0 else "Brick_Window_Square_Single"
				bays.append({"module": module, "transform": Transform3D(basis, Vector3(center.x, y, center.y)), "width": bay_width, "height": h, "floor": floor_index, "edge": i})
	return {"id": identity, "family": family, "height": height, "floors": floors, "ring": ring, "bays": bays, "seed": seed_value}

static func pilot(rows: Array, spawn: Vector3) -> Array:
	var candidates: Array = []
	for row in rows:
		if str(row.get("id", "")) not in PILOT_IDS:
			continue
		var label := str(row.get("name", "")).to_lower()
		if label.contains("town hall") or label.contains("victoria") or label.contains("cathedral") or label.contains("church"):
			continue # Do not present generic modules as authored historic landmarks.
		var p := plan(row)
		if p.is_empty():
			continue
		var center := Vector2.ZERO
		for point in p.ring:
			center += point
		center /= p.ring.size()
		var distance := center.distance_to(Vector2(spawn.x, spawn.z))
		if distance < 260.0:
			candidates.append({"row": row, "distance": distance})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if is_equal_approx(a.distance, b.distance):
			return str(a.row.id) < str(b.row.id)
		return a.distance < b.distance)
	var selected: Array = []
	for i in candidates.size():
		selected.append(candidates[i].row)
	return selected

func _source(module: String) -> Dictionary:
	if sources.has(module):
		return sources[module]
	var scene: PackedScene = load(KIT + module + ".gltf")
	var node := scene.instantiate()
	var meshes := node.find_children("*", "MeshInstance3D", true, false)
	if node is MeshInstance3D:
		meshes.push_front(node)
	var mesh: Mesh = meshes[0].mesh
	mesh = mesh.duplicate()
	for i in mesh.get_surface_count():
		var original := mesh.surface_get_material(i) as StandardMaterial3D
		if original != null:
			if module == "Trim_Window" and original.resource_name in ["MI_Trim", "MI_InteriorWall"]:
				var stone := StandardMaterial3D.new()
				stone.albedo_color = Color("c9b58e")
				stone.roughness = 0.85
				stone.cull_mode = BaseMaterial3D.CULL_DISABLED
				mesh.surface_set_material(i, stone)
			elif original.resource_name == "MI_FakeInterior":
				var backing := StandardMaterial3D.new()
				backing.albedo_color = Color("344c55")
				backing.roughness = 0.35
				backing.cull_mode = BaseMaterial3D.CULL_DISABLED
				mesh.surface_set_material(i, backing)
	var result := {"mesh": mesh, "bounds": mesh.get_aabb()}
	sources[module] = result
	node.free()
	return result

func _add(key: String, mesh: Mesh, transform: Transform3D) -> void:
	if not batches.has(key):
		batches[key] = {"mesh": mesh, "transforms": []}
	batches[key].transforms.append(transform)

func _box(key: String, size: Vector3, transform: Transform3D, color: Color, metallic: float = 0.0) -> void:
	if not sources.has(key):
		var box := BoxMesh.new()
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.metallic = metallic
		material.roughness = 0.28 if metallic > 0 else 0.8
		box.material = material
		sources[key] = {"mesh": box}
	var scaled := transform
	scaled.basis = transform.basis.scaled_local(size)
	_add(key, sources[key].mesh, scaled)

func assemble(rows: Array) -> Node3D:
	batches.clear()
	var root := Node3D.new()
	root.name = "Architecture"
	var plans: Array = []
	for row in rows:
		var p := plan(row)
		if p.is_empty():
			continue
		plans.append({"id": p.id, "family": p.family, "floors": p.floors, "bays": p.bays.size()})
		for bay in p.bays:
			var source := _source(bay.module)
			var bounds: AABB = source.bounds
			var t: Transform3D = bay.transform
			var scale := Vector3(bay.width / bounds.size.x, bay.height / bounds.size.y, 1.0)
			var module_transform := Transform3D(t.basis.scaled_local(scale), t.origin)
			module_transform.origin -= module_transform.basis * Vector3(bounds.get_center().x, bounds.position.y, 0)
			_add(bay.module, source.mesh, module_transform)
			if p.family == "glass" and bay.floor > 0:
				# Flat opaque glass avoids sorted transparency and fake interiors.
				var glass_t := t.translated_local(Vector3(0, bay.height * 0.5, -0.1))
				var shade := int(p.seed + bay.edge + bay.floor / 4) % 3
				_box("glass_%d" % shade, Vector3(bay.width - 0.12, bay.height - 0.18, 0.035), glass_t, [Color("345563"), Color("426979"), Color("527684")][shade], 0.55)
			if bay.floor == 0:
				var shop := t.translated_local(Vector3(0, bay.height * 0.5, -0.01))
				_box("shop_glass", Vector3(bay.width - 0.15, bay.height - 0.25, 0.025), shop, Color("28444b"), 0.3)
				var fascia := t.translated_local(Vector3(0, bay.height - 0.25, 0.08))
				_box("fascia_%d" % (p.seed % 3), Vector3(bay.width, 0.35, 0.18), fascia, [Color("263c3d"), Color("6c4435"), Color("b29c75")][p.seed % 3])
			if bay.floor == p.floors - 1:
				var roof_t := t.translated_local(Vector3(0, bay.height - 0.12, 0.0))
				_box("parapet", Vector3(bay.width, 0.24, 0.42), roof_t, Color("c2b8a1"))
				if p.family == "stone":
					var cornice := _source("Cornice_Trim_Center")
					var cornice_t := t.translated_local(Vector3(0, bay.height - 0.65, -0.05))
					cornice_t.basis = cornice_t.basis.scaled_local(Vector3(bay.width / 2.0, 0.65, 1.0))
					_add("Cornice_Trim_Center", cornice.mesh, cornice_t)
		var ring: PackedVector2Array = p.ring
		var orientation := signf(MeshBuilder._signed_area(ring))
		for i in ring.size():
			var a := ring[i]
			var b := ring[(i + 1) % ring.size()]
			var tangent := (b - a).normalized()
			var outward := Vector2(tangent.y, -tangent.x) * orientation
			var t := Transform3D(Basis(Vector3(tangent.x, 0, tangent.y) * orientation, Vector3.UP, -Vector3(outward.x, 0, outward.y)), Vector3(a.x, p.height * 0.5, a.y))
			_box("pier", Vector3(0.48, p.height, 0.48), t, Color("b7ac98"))
		var center := Vector2.ZERO
		for point in ring:
			center += point
		center /= ring.size()
		var ac := _source("Prop_ACUnit")
		for i in 2 + p.seed % 3:
			var location := center + Vector2(i * 2 - 2, 0)
			var contained := true
			for offset in [Vector2(-1,-1), Vector2(-1,1), Vector2(1,-1), Vector2(1,1)]:
				contained = contained and Geometry2D.is_point_in_polygon(location + offset, ring)
			if contained:
				_add("Prop_ACUnit", ac.mesh, Transform3D(Basis.IDENTITY.scaled(Vector3(2, 2, 2)), Vector3(location.x, p.height + 0.01, location.y)))
	for key in batches:
		var batch: Dictionary = batches[key]
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = batch.mesh
		multi.instance_count = batch.transforms.size()
		for i in multi.instance_count:
			multi.set_instance_transform(i, batch.transforms[i])
		var instance := MultiMeshInstance3D.new()
		instance.name = key
		instance.multimesh = multi
		root.add_child(instance)
	root.set_meta("buildings", plans)
	return root
