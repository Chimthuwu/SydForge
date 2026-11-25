extends SceneTree

## L86 first bounded step: measure what the existing Inner West DEM
## (AWS/Mapzen terrarium extract, 16 m float32 grid) can already cover of the
## Stage B bounds, and report the heights a terrain rebase would re-base onto.
## Run: godot --headless --path . --script res://tests/terrain_stage_b_probe.gd
## This is a probe + guard: it pins the tile's coverage so a later terrain
## pass (and any new DEM fetch) has exact numbers to work from.

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)

func _run() -> void:
	var iw := {}
	var iw_file := FileAccess.open("res://sydney/world/inner_west/world.json", FileAccess.READ)
	if iw_file != null:
		iw = JSON.parse_string(iw_file.get_as_text())
	var sb := {}
	var sb_file := FileAccess.open("res://sydney/world/stage_b/world.json", FileAccess.READ)
	if sb_file != null:
		sb = JSON.parse_string(sb_file.get_as_text())
	_check(not iw.is_empty() and not sb.is_empty(), "world JSONs parse")

	var meta: Dictionary = iw.get("terrain", {})
	var nx := int(meta.get("nx", 0))
	var nz := int(meta.get("nz", 0))
	var spacing := float(meta.get("spacingM", 0.0))
	var min_x := float(meta.get("minX", 0.0))
	var min_z := float(meta.get("minZ", 0.0))
	_check(nx > 100 and nz > 100 and spacing > 0.0,
		"inner west DEM meta present (%dx%d @ %.0f m)" % [nx, nz, spacing])

	var raw := InnerWestMesh.load_height_grid("res://sydney/world/inner_west/height.bin")
	_check(not raw.is_empty() and raw["data"].size() >= nx * nz, "height.bin loads (%d floats)" % (0 if raw.is_empty() else raw["data"].size()))
	if raw.is_empty():
		_finish()
		return
	var data: PackedFloat32Array = raw["data"]

	# Tile footprint in world space.
	var tile_max_x := min_x + float(nx) * spacing
	var tile_max_z := min_z + float(nz) * spacing
	print("NOTE DEM tile covers x %.1f..%.1f  z %.1f..%.1f" % [min_x, tile_max_x, min_z, tile_max_z])

	# Stage B bounds and the intersection with the tile.
	var sb_b: Dictionary = sb.get("bounds", {})
	var sb_min_x := float(sb_b.get("minX", 0.0))
	var sb_max_x := float(sb_b.get("maxX", 0.0))
	var sb_min_z := float(sb_b.get("minZ", 0.0))
	var sb_max_z := float(sb_b.get("maxZ", 0.0))
	var ov_min_x := maxf(sb_min_x, min_x)
	var ov_max_x := minf(sb_max_x, tile_max_x)
	var ov_min_z := maxf(sb_min_z, min_z)
	var ov_max_z := minf(sb_max_z, tile_max_z)
	_check(ov_max_x > ov_min_x and ov_max_z > ov_min_z, "DEM overlaps the Stage B bounds")
	var ov_w := ov_max_x - ov_min_x
	var ov_d := ov_max_z - ov_min_z
	var sb_w := sb_max_x - sb_min_x
	var sb_d := sb_max_z - sb_min_z
	var covered := (ov_w * ov_d) / (sb_w * sb_d) * 100.0
	print("NOTE overlap x %.1f..%.1f  z %.1f..%.1f = %.1f%% of Stage B area" % [ov_min_x, ov_max_x, ov_min_z, ov_max_z, covered])
	if ov_max_x < sb_max_x:
		print("NOTE GAP east of x=%.1f to x=%.1f (~%.0f m wide) needs another DEM fetch" % [ov_max_x, sb_max_x, sb_max_x - ov_max_x])

	# Heights inside the overlap: what a rebase would re-base onto.
	var h_min := INF
	var h_max := -INF
	var row0 := int(floor((ov_min_z - min_z) / spacing))
	var row1 := int(ceil((ov_max_z - min_z) / spacing))
	var col0 := int(floor((ov_min_x - min_x) / spacing))
	var col1 := int(ceil((ov_max_x - min_x) / spacing))
	for row in range(maxi(row0, 0), mini(row1 + 1, nz)):
		for col in range(maxi(col0, 0), mini(col1 + 1, nx)):
			var h := data[row * nx + col]
			h_min = minf(h_min, h)
			h_max = maxf(h_max, h)
	print("NOTE heights in overlap: min %.1f m  max %.1f m  (world y = metres ASL)" % [h_min, h_max])

	# The CBD samples read 0.0 — check whether that is a flat region in the
	# tile or zeroed data. Report the elevated-sample share east vs west of
	# x = -1000 so a rebase design knows which half carries real terrain.
	for side in [["CBD (east of x=-1000)", -1000.0, ov_max_x], ["inner west (x<-1000)", ov_min_x, -1000.0]]:
		var label: String = side[0]
		var lo: float = maxf(side[1], ov_min_x)
		var hi: float = minf(side[2], ov_max_x)
		if hi <= lo:
			continue
		var raised := 0
		var total := 0
		var c0 := int(floor((lo - min_x) / spacing))
		var c1 := int(ceil((hi - min_x) / spacing))
		for row in range(maxi(row0, 0), mini(row1 + 1, nz)):
			for col in range(maxi(c0, 0), mini(c1 + 1, nx)):
				total += 1
				if data[row * nx + col] > 0.5:
					raised += 1
		var share := float(raised) / maxf(float(total), 1.0) * 100.0
		print("NOTE %s: %.1f%% of samples above 0.5 m (%d/%d)" % [label, share, raised, total])

	# Sample known points so a datum/offset policy has anchors.
	for sample in [["Central Station", -40.0, -460.0], ["Circular Quay", 200.0, -1500.0], ["Harbour Bridge south", 0.0, -1100.0], ["Parramatta Rd Leichhardt", -4000.0, 600.0]]:
		var x: float = sample[1]
		var z: float = sample[2]
		if x >= min_x and x <= tile_max_x and z >= min_z and z <= tile_max_z:
			var h := InnerWestMesh.height_at({"data": data, "nx": nx, "nz": nz, "minX": min_x, "minZ": min_z, "spacing": spacing}, x, z)
			print("NOTE %s (%.0f, %.0f): %.1f m" % [sample[0], x, z, h])

	_finish()

func _finish() -> void:
	print("RESULT: checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
