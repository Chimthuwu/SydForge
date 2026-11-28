extends SceneTree

## Owner request: Woolworths and Coles should be quite big.

const World := preload("res://sydney/cbd/cbd_world.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var world = World.new()
	world.load_world()
	root.add_child(world)
	await process_frame
	var stores := get_nodes_in_group("supermarket")
	var failures := 0
	if stores.size() != 2:
		failures += 1
		print("FAIL: expected both supermarkets, got ", stores.size())
	for store: Node3D in stores:
		var width := float(store.get_meta("frontage_width", 0.0))
		var ok := width >= 25.0
		failures += 0 if ok else 1
		print(("PASS: " if ok else "FAIL: ") + "%s frontage is %.1f m wide at %.0f, %.0f" % [
			store.name, width, store.position.x, store.position.z])
	print("RESULT: %d failures" % failures)
	quit(1 if failures else 0)
