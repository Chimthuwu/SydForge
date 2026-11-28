extends RefCounted

## Cuts everything out of a tunnel's interior: street ribbons, the bridge deck
## and their collision all carried straight on through the rail approach.
##
## A volume is a convex box: {"inverse": Transform3D, "half": Vector3, "centre": Vector3}.
## Triangles are split against its six planes and only the outside pieces kept.


static func box(transform: Transform3D, size: Vector3) -> Dictionary:
	var world := transform * AABB(-size * 0.5, size)
	return {"inverse": transform.affine_inverse(), "half": size * 0.5, "bounds": world}


static func contains(volumes: Array, point: Vector3) -> bool:
	for volume: Dictionary in volumes:
		var local: Vector3 = (volume.inverse as Transform3D) * point
		var half: Vector3 = volume.half
		if absf(local.x) < half.x and absf(local.y) < half.y and absf(local.z) < half.z:
			return true
	return false


static func _pokes_in(volumes: Array, bounds: AABB) -> bool:
	for step in 41:
		var point := bounds.get_center()
		point.y = bounds.position.y + bounds.size.y * step / 40.0
		if contains(volumes, point):
			return true
	return false


static func carve(root: Node, skip: Node, volumes: Array) -> void:
	if volumes.is_empty():
		return
	var region: AABB = volumes[0].bounds
	for volume: Dictionary in volumes:
		region = region.merge(volume.bounds)
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if skip.is_ancestor_of(instance) or instance.mesh == null:
			continue
		var bounds: AABB = instance.global_transform * instance.get_aabb()
		if not bounds.intersects(region):
			continue
		if instance.mesh is ArrayMesh:
			_carve_mesh(instance, volumes, region)
		elif contains(volumes, bounds.get_center()) 				or (maxf(bounds.size.x, bounds.size.z) < 3.0 and _pokes_in(volumes, bounds)):
			instance.visible = false # shared primitive (a lamp, a deck box)
	for node in root.find_children("*", "CollisionShape3D", true, false):
		var collider := node as CollisionShape3D
		if skip.is_ancestor_of(collider) or not collider.shape is ConcavePolygonShape3D:
			continue
		_carve_shape(collider, volumes, region)


static func _carve_mesh(instance: MeshInstance3D, volumes: Array, region: AABB) -> void:
	var source := instance.mesh as ArrayMesh
	var xform := instance.global_transform
	var result := ArrayMesh.new()
	var changed := false
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices := PackedInt32Array()
		if arrays[Mesh.ARRAY_INDEX] != null:
			indices = arrays[Mesh.ARRAY_INDEX]
		var count := positions.size() if indices.is_empty() else indices.size()
		var normals: Variant = arrays[Mesh.ARRAY_NORMAL]
		var colors: Variant = arrays[Mesh.ARRAY_COLOR]
		var uvs: Variant = arrays[Mesh.ARRAY_TEX_UV]
		var out_positions := PackedVector3Array()
		var out_normals := PackedVector3Array()
		var out_colors := PackedColorArray()
		var out_uvs := PackedVector2Array()
		for start in range(0, count - 2, 3):
			var ids := [start, start + 1, start + 2]
			if not indices.is_empty():
				ids = [indices[start], indices[start + 1], indices[start + 2]]
			var a: Vector3 = positions[ids[0]]
			var b: Vector3 = positions[ids[1]]
			var c: Vector3 = positions[ids[2]]
			var pieces := _outside_pieces([xform * a, xform * b, xform * c], volumes, region)
			if pieces.size() != 1 or not pieces[0].is_empty():
				changed = true
			else:
				pieces = [[xform * a, xform * b, xform * c]]
			var inverse := xform.affine_inverse()
			for piece: Array in pieces:
				for corner in range(1, piece.size() - 1):
					for world: Vector3 in [piece[0], piece[corner], piece[corner + 1]]:
						var local := inverse * world
						var weight := _weights(local, a, b, c)
						out_positions.append(local)
						if normals != null:
							out_normals.append((normals[ids[0]] * weight.x + normals[ids[1]] * weight.y
								+ normals[ids[2]] * weight.z).normalized())
						if colors != null:
							out_colors.append(colors[ids[0]] * weight.x + colors[ids[1]] * weight.y
								+ colors[ids[2]] * weight.z)
						if uvs != null:
							out_uvs.append(uvs[ids[0]] * weight.x + uvs[ids[1]] * weight.y
								+ uvs[ids[2]] * weight.z)
		if out_positions.is_empty():
			continue
		var built := []
		built.resize(Mesh.ARRAY_MAX)
		built[Mesh.ARRAY_VERTEX] = out_positions
		if normals != null:
			built[Mesh.ARRAY_NORMAL] = out_normals
		if colors != null:
			built[Mesh.ARRAY_COLOR] = out_colors
		if uvs != null:
			built[Mesh.ARRAY_TEX_UV] = out_uvs
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, built)
		result.surface_set_material(result.get_surface_count() - 1, source.surface_get_material(surface))
	if changed:
		instance.mesh = result


static func _carve_shape(collider: CollisionShape3D, volumes: Array, region: AABB) -> void:
	var shape := collider.shape as ConcavePolygonShape3D
	var faces := shape.get_faces()
	var xform := collider.global_transform
	var inverse := xform.affine_inverse()
	var kept := PackedVector3Array()
	var changed := false
	for start in range(0, faces.size(), 3):
		var triangle := [xform * faces[start], xform * faces[start + 1], xform * faces[start + 2]]
		var pieces := _outside_pieces(triangle, volumes, region)
		if pieces.size() == 1 and pieces[0].is_empty():
			for offset in 3:
				kept.append(faces[start + offset])
			continue
		changed = true
		for piece: Array in pieces:
			for corner in range(1, piece.size() - 1):
				for world: Vector3 in [piece[0], piece[corner], piece[corner + 1]]:
					kept.append(inverse * world)
	if changed:
		var carved := ConcavePolygonShape3D.new()
		carved.set_faces(kept)
		carved.backface_collision = shape.backface_collision
		collider.shape = carved


## The parts of a triangle outside every volume. `[[]]` means "untouched".
static func _outside_pieces(triangle: Array, volumes: Array, region: AABB) -> Array:
	var bounds := AABB(triangle[0], Vector3.ZERO).expand(triangle[1]).expand(triangle[2])
	if not bounds.grow(0.01).intersects(region):
		return [[]]
	var pieces: Array = [triangle]
	var touched := false
	for volume: Dictionary in volumes:
		if not bounds.grow(0.01).intersects(volume.bounds):
			continue
		var next: Array = []
		for piece: Array in pieces:
			var split := _split(piece, volume)
			if split.hit:
				touched = true
				next.append_array(split.outside)
			else:
				next.append(piece)
		pieces = next
	return pieces if touched else [[]]


static func _split(polygon: Array, volume: Dictionary) -> Dictionary:
	var inverse: Transform3D = volume.inverse
	var half: Vector3 = volume.half
	var inside := polygon
	var outside: Array = []
	for axis in 3:
		for side in [-1.0, 1.0]:
			var front: Array = []
			var back: Array = []
			for i in inside.size():
				var p: Vector3 = inside[i]
				var q: Vector3 = inside[(i + 1) % inside.size()]
				var dp: float = (inverse * p)[axis] * side - half[axis]
				var dq: float = (inverse * q)[axis] * side - half[axis]
				if dp >= -0.0001:
					front.append(p)
				if dp <= 0.0001:
					back.append(p)
				if (dp > 0.0001 and dq < -0.0001) or (dp < -0.0001 and dq > 0.0001):
					var cross := p.lerp(q, dp / (dp - dq))
					front.append(cross)
					back.append(cross)
			if front.size() >= 3:
				outside.append(front)
			if back.size() < 3:
				return {"hit": false, "outside": []}
			inside = back
	return {"hit": true, "outside": outside}


static func _weights(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var v0 := b - a
	var v1 := c - a
	var v2 := p - a
	var d00 := v0.dot(v0)
	var d01 := v0.dot(v1)
	var d11 := v1.dot(v1)
	var denominator := d00 * d11 - d01 * d01
	if absf(denominator) < 0.0000001:
		return Vector3(1.0, 0.0, 0.0)
	var v := (d11 * v2.dot(v0) - d01 * v2.dot(v1)) / denominator
	var w := (d00 * v2.dot(v1) - d01 * v2.dot(v0)) / denominator
	return Vector3(1.0 - v - w, v, w)
