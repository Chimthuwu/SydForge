extends SceneTree

## Focused coverage for the reusable station component library. Verifies that
## palettes do not mutate shared defaults, that each component produces the
## expected geometry/collision, and that the existing interiors builder still
## produces the authored stations through the library.

const StationComponents := preload("res://sydney/railway/station_components.gd")
const StationInteriors := preload("res://sydney/railway/station_interiors.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)


func _run() -> void:
	var root := Node3D.new()
	root.name = "ComponentTestRoot"
	get_root().add_child(root)

	var palette := StationComponents.make_palette({
		"tile_floor": Color("aa3322"),
		"canopy": Color("2244aa"),
	})
	_check(palette["tile_floor"] == Color("aa3322"), "palette override applies to the copy")
	_check(
		StationComponents.DEFAULT_PALETTE["tile_floor"] != Color("aa3322"),
		"palette override does not mutate the shared defaults"
	)

	var room_node: Node3D = StationComponents.room(root, Vector3(0, 1, 0), Vector3(20, 4, 12), palette)
	_check(room_node.get_child_count() >= 8, "room has floor, ceiling, walls and bands")
	var room_collisions := room_node.find_children("*", "CollisionShape3D", true, false)
	_check(room_collisions.size() >= 1, "room floor is solid")

	var hall := Node3D.new()
	root.add_child(hall)
	StationComponents.ticket_hall(hall, Vector2(20, 12), palette)
	_check(hall.get_child_count() > 20, "ticket hall adds gates, machines, benches and board")

	var platform := Node3D.new()
	root.add_child(platform)
	StationComponents.platform_dressing(platform, 80.0, 14.0, "Test Halt", false, palette)
	_check(platform.get_child_count() > 10, "platform dressing adds edge strips, seating and signs")
	var platform_lights := 0
	for child in platform.get_children():
		if child is Label3D:
			platform_lights += 1
	_check(platform_lights >= 1, "platform dressing adds a station name label")

	var canopy: Node3D = StationComponents.canopy(platform, Vector3(0, 0, 0), 60.0, 10.0, 3.8, palette)
	_check(canopy != null and canopy.get_child_count() >= 10, "canopy adds posts, roof and fascias")

	StationComponents.signage(hall, "Test Halt", Vector3(0, 3, 0), palette)
	_check(hall.get_child_count() > 20, "signage adds a name board without replacing hall content")

	var stair_root := Node3D.new()
	root.add_child(stair_root)
	StationComponents.stairs(stair_root, Vector3(0, 0, 0), 3.0, 3.0, 8.0, 0.0, palette)
	var stair_collisions := stair_root.find_children("*", "CollisionShape3D", true, false)
	_check(stair_collisions.size() >= 6, "stairs expose solid steps")

	# The existing authored builder must still resolve all eight stations after
	# delegating its dressing to the component library.
	var interiors := StationInteriors.new()
	root.add_child(interiors)
	interiors.build(null, {})
	_check(int(interiors.stats.get("stations", 0)) == 8, "interiors builder still builds eight stations")
	_check(interiors.get_child_count() == 8, "interiors builder creates one root per station")
	_check(StationInteriors.openings().size() == 4, "underground openings remain unchanged")

	print("RESULT: checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
