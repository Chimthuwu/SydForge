extends SceneTree

## Headless CPU probe for the wired living-world systems. Mirrors the method in
## PERFORMANCE_AUDIT.md: load the canonical scene, let actors fill, then time a
## window of frames. Rendering is stubbed, so this is CPU + physics + script only.

const CbdDistrictScript := preload("res://scripts/sydney_cbd_district.gd")

var scene: Node3D


func _initialize() -> void:
	call_deferred("_run")


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _run() -> void:
	scene = CbdDistrictScript.new()
	get_root().add_child(scene)
	await _frames(320)

	var traffic = scene.get_node_or_null("TrafficManager")
	var peds = scene.get_node_or_null("PedestrianManager")
	var wildlife = scene.get_node_or_null("WildlifeManager")
	var events = scene.get_node_or_null("AmbientEventDirector")
	var incidents = scene.get_node_or_null("EmergencyIncidentManager")
	var audio = scene.get_node_or_null("AmbientAudioDirector")

	var start := Time.get_ticks_usec()
	await _frames(240)
	var elapsed := Time.get_ticks_usec() - start
	var per_frame := float(elapsed) / 240.0 / 1000.0

	print("POPULATION traffic=%d peds=%d wildlife=%d" % [
		(traffic.get("active_vehicles") as Array).size(),
		(peds.get("active_pedestrians") as Array).size(),
		(wildlife.get("active_wildlife") as Array).size(),
	])
	print("EVENTS ambient=%d incidents=%d" % [
		(events.get("active_events") as Array).size(),
		(incidents.get("active_incidents") as Array).size(),
	])
	print("AUDIO ambient_voices=%d" % int(audio.call("voice_count")))
	print("CPU_MS_PER_FRAME %.2f (headless, 240 frames)" % per_frame)
	quit(0)
