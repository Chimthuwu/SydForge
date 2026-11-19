extends SceneTree

# Smoke entry for the Inner West district (Phase 6C).
# Run: ./Godot_v4.7.2-stable_win64_console.exe --headless --path . \
#       --script res://tests/inner_west_smoke.gd --log-file tests/inner_west_smoke.log

var checks := 0
var failures := 0
var world: InnerWestWorld


func check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + description)
	else:
		failures += 1
		push_error("FAIL: " + description)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var root := Node3D.new()

	world = InnerWestWorld.new()
	check(world.load_world(), "inner west world loads: " + world.load_error)
	root.add_child(world)
	check(world.geometry_counts.has("Terrain"), "terrain mesh node created")
	check(world.geometry_counts.has("Roads"), "road mesh node created")
	check(world.geometry_counts.has("Buildings"), "building mesh node created")
	check(world.geometry_counts.has("Trees"), "tree instances created")
	check(world.stats.get("buildings", 0) > 20000, "scaled building count (got %s)" % [world.stats.get("buildings", 0)])
	check(world.player_spawn.distance_to(Vector3.ZERO) > 100.0, "player spawn is in Inner West")

	# terrain height function responds on the heat map
	var peak := InnerWestMesh.height_at(world.height_grid, -8570.0, -5200.0)
	print("sample: peak=%.1f balmain=%.1f Sydney-test=%.1f" % [
		peak,
		InnerWestMesh.height_at(world.height_grid, -1400.0, -2400.0),
		InnerWestMesh.height_at(world.height_grid, -200.0, -2600.0),
	])

	root.queue_free()
	quit(0 if failures == 0 else 1)


func _predelete() -> void:
	if world != null:
		world.free()
