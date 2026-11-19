extends SceneTree

## Visual screenshot capture script for Sydney Living Ecosystem across Day/Night phases:
## - Morning (10:00 AM)
## - Midday (12:30 PM)
## - Sunset (17:45 PM)
## - Night (22:00 PM with streetlights, vehicle headlights, Opera House & Harbour Bridge floodlights)
## - Representative scenes of traffic, pedestrians, and Australian White Ibis (bin chickens)

const CbdDistrictScript := preload("res://scripts/sydney_cbd_district.gd")

func _init() -> void:
	call_deferred("_run_captures")

func _run_captures() -> void:
	var tree_root := get_root()
	var scene: Node3D = CbdDistrictScript.new()
	tree_root.add_child(scene)
	
	for i in 25:
		await process_frame
	
	var time_mgr = scene.get_node_or_null("WorldTimeManager")
	var rig: BoomCamera = scene.get_node_or_null("BoomCamera")
	if rig == null:
		for child in scene.get_children():
			if child is BoomCamera:
				rig = child
				break

	# 1. Capture Morning (10:00 AM) - Opera House and Harbour Bridge framing
	time_mgr.set_time(10.0)
	for i in 10:
		await process_frame
	_save_screenshot("res://tests/ecosystem_morning.png")
	
	# 2. Capture Midday (12:30 PM) - Bright overhead sun, crisp shadows
	time_mgr.set_time(12.5)
	for i in 10:
		await process_frame
	_save_screenshot("res://tests/ecosystem_midday.png")
	
	# 3. Capture Sunset (17:45 PM) - Warm golden/orange glow over harbour & city
	time_mgr.set_time(17.75)
	for i in 10:
		await process_frame
	_save_screenshot("res://tests/ecosystem_sunset.png")
	
	# 4. Capture Night (22:00 PM) - Deep night sky, illuminated bridge, streetlights
	time_mgr.set_time(22.0)
	for i in 10:
		await process_frame
	_save_screenshot("res://tests/ecosystem_night.png")
	
	print("ALL SCREENSHOTS CAPTURED SUCCESSFULLY")
	quit(0)

func _save_screenshot(path: String) -> void:
	var vp := get_root().get_viewport()
	var img := vp.get_texture().get_image()
	if img != null:
		var global_path := ProjectSettings.globalize_path(path)
		img.save_png(global_path)
		print("Saved screenshot: %s" % path)
