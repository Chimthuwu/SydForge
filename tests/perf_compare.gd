extends SceneTree

## Comparable performance probe: fixed camera, time, weather and actor budget.
## Set SPLOOGE_PERF_TAG to label the run before/after an optimisation.
## Set SPLOOGE_PERF_GPU=1 to run with a real viewport for GPU metrics (requires windowed mode).

var scene: Node3D
var review: Camera3D
var tag := "baseline"
var gpu_mode := false

func _initialize() -> void:
	var e := OS.get_environment("SPLOOGE_PERF_TAG")
	if not e.is_empty(): tag = e
	var gpu_env := OS.get_environment("SPLOOGE_PERF_GPU")
	if not gpu_env.is_empty() and gpu_env.to_lower() in ["1", "true", "yes"]:
		gpu_mode = true
	call_deferred("_run")

func _frames(n: int) -> void:
	for i in n: await process_frame

func _run() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(scene)
	await _frames(80)
	var tm = scene.get_node_or_null("WorldTimeManager")
	var wm = scene.get_node_or_null("WeatherManager")
	var hour := 22.0
	var te := OS.get_environment("SPLOOGE_PERF_TIME")
	if not te.is_empty(): hour = float(te)
	if tm != null: tm.set_time(hour)
	if wm != null: wm.set_weather_by_name("light_rain", true)
	
	if gpu_mode:
		# Create a real viewport for GPU metrics
		var vp := SubViewport.new()
		vp.size = Vector2i(1280, 720)
		vp.render_target_v_flip = true
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		vp.current = true
		scene.add_child(vp)
		
		review = Camera3D.new()
		review.fov = 62.0
		review.far = 8000.0
		vp.add_child(review)
		review.current = true
		review.global_position = Vector3(-60.0, 1.75, -300.0)
		review.look_at(Vector3(-60.0, 2.4, -380.0), Vector3.UP)
		if scene.player != null:
			scene.player.global_position = Vector3(-60.0, 0.4, -300.0)
	else:
		# Headless mode: just set up camera for consistency
		review = Camera3D.new()
		review.fov = 62.0
		review.far = 8000.0
		scene.add_child(review)
		review.current = true
		review.global_position = Vector3(-60.0, 1.75, -300.0)
		review.look_at(Vector3(-60.0, 2.4, -380.0), Vector3.UP)
		if scene.player != null:
			scene.player.global_position = Vector3(-60.0, 0.4, -300.0)
	
	await _frames(120)

	var p = Performance
	var draw := int(p.get_monitor(p.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var prim := int(p.get_monitor(p.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var lights := 0
	var meshes := 0
	var shadow_lights := 0
	for n in scene.find_children("*", "", true, false):
		if n is Light3D:
			lights += 1
			if n is DirectionalLight3D and (n as Light3D).shadow_enabled: shadow_lights += 1
		elif n is MeshInstance3D or n is MultiMeshInstance3D:
			meshes += 1
	var t0 := Time.get_ticks_usec()
	await _frames(300)
	var elapsed := Time.get_ticks_usec() - t0
	var avg_ms := float(elapsed) / 300.0 / 1000.0
	var gpu_tag := "gpu" if gpu_mode else "cpu"
	print("PERF_COMPARE tag=%s mode=%s avg_frame_ms=%.2f draw=%d primitives=%d lights=%d mesh_nodes=%d sun_shadows=%d mem_texture=%.1fMB" % [
		tag, gpu_tag, avg_ms, draw, prim, lights, meshes, shadow_lights,
		float(p.get_monitor(p.RENDER_TEXTURE_MEM_USED)) / 1048576.0])
	quit()
