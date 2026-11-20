extends SceneTree

## Regression guard for the Milsons Point -> Wynyard rail descent.
## The bore must only be built where its roof is below the city slab, and the
## portal marker must sit at grade rather than on the carriageway.

const CbdDistrictScript := preload("res://scripts/sydney_cbd_district.gd")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("PASS: " + description)
	else:
		_failures += 1
		push_error("FAIL: " + description)


func _run() -> void:
	var scene := CbdDistrictScript.new()
	get_root().add_child(scene)
	for i in 20:
		await process_frame

	var railway: Node3D = scene.get_node_or_null("CbdWorld/SydneyRailNetwork")
	if railway == null:
		for candidate in scene.find_children("*", "Node3D", true, false):
			if candidate.name == "SydneyRailNetwork":
				railway = candidate
				break
	_check(railway != null, "rail network exists in canonical world")
	if railway == null:
		_finish()
		return

	var walls: MeshInstance3D = railway.get_node_or_null("RailTunnelWalls") as MeshInstance3D
	_check(walls != null and walls.mesh != null, "rail tunnel bore mesh exists")
	if walls != null and walls.mesh != null:
		var box: AABB = walls.mesh.get_aabb()
		var top := box.position.y + box.size.y
		_check(top <= 0.05, "tunnel bore stays below street grade (max y = %.2f)" % top)

	var portal: Node3D = railway.get_node_or_null("WynyardRailTunnelPortal") as Node3D
	_check(portal != null, "Wynyard tunnel portal marker exists")
	if portal != null:
		_check(portal.position.y <= 0.05, "Wynyard portal marker is at grade (y = %.2f)" % portal.position.y)
		var tallest := 0.0
		for child in portal.get_children():
			if child is MeshInstance3D:
				var local: AABB = (child as MeshInstance3D).mesh.get_aabb()
				tallest = maxf(tallest, local.position.y + local.size.y)
		_check(tallest <= 2.0, "portal marker is a low cutting mouth (max local y = %.2f)" % tallest)

	_finish()


func _finish() -> void:
	print("RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
