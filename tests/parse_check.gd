extends SceneTree

# Load-check for all new scripts (dev tool, not shipped). Reports resources
# that fail to load; parse errors also print to stderr.
var files := [
	"res://sydney/inner_west/inner_west_world.gd",
	"res://sydney/inner_west/inner_west_mesh.gd",
	"res://sydney/inner_west/buildings.gd",
	"res://sydney/inner_west/character.gd",
	"res://sydney/inner_west/anzac_bridge.gd",
	"res://scripts/sydney_inner_west_district.gd",
	"res://tests/inner_west_smoke.gd",
	"res://tests/inner_west_scene_test.gd",
	"res://tests/inner_west_geometry_test.gd",
]

func _initialize() -> void:
	var failures := 0
	for f in files:
		if not FileAccess.file_exists(f):
			print("MISSING: " + f)
			failures += 1
			continue
		var resource := ResourceLoader.load(f)
		if resource == null:
			print("LOAD FAILED: " + f)
			failures += 1
		else:
			print("LOADED: " + f)
	quit(0)
