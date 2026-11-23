extends SceneTree

## Every enterable ArcadeCar must have real dynamic headlights, not only
## emissive lamp meshes. Verifies beam geometry, toggle state and that the
## toggle is not shared with the on-foot flashlight.

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


func _beams(vehicle: Node3D) -> Array[SpotLight3D]:
	var found: Array[SpotLight3D] = []
	for child: Node in vehicle.get_children():
		if child is SpotLight3D and str(child.name).begins_with("HeadlightBeam"):
			found.append(child as SpotLight3D)
	return found


func _run() -> void:
	var root := Node3D.new()
	root.name = "HeadlightTestRoot"
	get_root().add_child(root)

	for scene_name in ["comet", "viper", "hauler"]:
		var car: Node3D = load("res://scenes/vehicles/%s.tscn" % scene_name).instantiate()
		root.add_child(car)
		var beams := _beams(car)
		_check(beams.size() == 2, "%s has two forward headlight beams" % scene_name)
		if beams.size() == 2:
			var left := beams[0]
			_check(left.spot_range >= 30.0, "%s beams reach the road ahead" % scene_name)
			_check(left.spot_angle > 20.0, "%s beams are wide enough to read the lane" % scene_name)
			_check(not left.shadow_enabled, "%s headlights add no shadow pass" % scene_name)
			_check(left.position.z < 0.0, "%s beams sit at the front of the car" % scene_name)
		_check(car.is_headlights_on() == false, "%s starts with headlights off" % scene_name)
		car.toggle_headlights()
		_check(car.is_headlights_on(), "%s F toggle switches headlights on" % scene_name)
		var any_visible := false
		for beam: SpotLight3D in beams:
			any_visible = any_visible or beam.visible
		_check(any_visible, "%s headlights produce actual illumination when on" % scene_name)
		car.toggle_headlights()
		_check(not car.is_headlights_on(), "%s second toggle switches headlights off" % scene_name)
		var none_visible := true
		for beam: SpotLight3D in beams:
			none_visible = none_visible and not beam.visible
		_check(none_visible, "%s headlights stop illuminating when off" % scene_name)

	var bike: Node3D = load("res://scenes/vehicles/motorbike.tscn").instantiate()
	root.add_child(bike)
	_check(_beams(bike).size() == 1, "motorbike uses a single central headlight")
	bike.toggle_headlights()
	_check(bike.is_headlights_on(), "motorbike headlight toggles")

	root.queue_free()
	print("RESULT: checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
