extends RefCounted

## Cuts a city-wide flat mesh into square tiles. The compatibility renderer
## gives each mesh a capped list of lights; an 8 km road mesh is touched by
## every light in the city, so streetlights and headlights near the player were
## dropped and never lit the asphalt. Tiles only collect their local lights.

const TILE_M := 256.0


## Replaces the drawing of `source` with tiles. `source` keeps its mesh (tools
## and geometry tests read it) but is hidden.
static func split(source: MeshInstance3D, tile: float = TILE_M) -> int:
	var mesh := source.mesh
	if mesh == null:
		return 0
	var buckets: Dictionary = {}  # tile -> {surface -> PackedInt32Array}
	var surfaces: Array = []
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		surfaces.append(arrays)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices := PackedInt32Array()
		if arrays[Mesh.ARRAY_INDEX] != null:
			indices = arrays[Mesh.ARRAY_INDEX]
		var count := indices.size() if not indices.is_empty() else vertices.size()
		for i in range(0, count - 2, 3):
			var ids := [i, i + 1, i + 2]
			if not indices.is_empty():
				ids = [indices[i], indices[i + 1], indices[i + 2]]
			var centre: Vector3 = (vertices[ids[0]] + vertices[ids[1]] + vertices[ids[2]]) / 3.0
			var key := Vector2i(floori(centre.x / tile), floori(centre.z / tile))
			if not buckets.has(key):
				buckets[key] = {}
			if not buckets[key].has(s):
				buckets[key][s] = []
			buckets[key][s].append_array(ids)

	var holder := Node3D.new()
	holder.name = str(source.name) + "Tiles"
	holder.transform = source.transform
	source.get_parent().add_child(holder)
	for key: Vector2i in buckets:
		var piece := ArrayMesh.new()
		for s: int in buckets[key]:
			var ids: Array = buckets[key][s]
			var from: Array = surfaces[s]
			var to: Array = []
			to.resize(Mesh.ARRAY_MAX)
			for channel in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2, Mesh.ARRAY_COLOR]:
				if from[channel] == null:
					continue
				var values = from[channel].duplicate()
				values.resize(ids.size())
				for n in ids.size():
					values[n] = from[channel][ids[n]]
				to[channel] = values
			piece.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, to)
			piece.surface_set_material(piece.get_surface_count() - 1, mesh.surface_get_material(s))
		var instance := MeshInstance3D.new()
		instance.mesh = piece
		instance.material_override = source.material_override
		instance.cast_shadow = source.cast_shadow
		for group in source.get_groups():
			instance.add_to_group(group)
		holder.add_child(instance)
	source.visible = false
	return buckets.size()
