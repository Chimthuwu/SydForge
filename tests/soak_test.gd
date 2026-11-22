extends SceneTree

## Long-session soak test for memory growth and scene-object accumulation.
## Runs the canonical scene for an extended duration and samples metrics periodically.
## Set SPLOOGE_SOAK_FRAMES to override the default frame count (default: 10800 = 3 min at 60 Hz).
## Set SPLOOGE_SOAK_INTERVAL to override the sampling interval (default: 600 frames = 10 s).
## Outputs a CSV line per sample: frame,time_ms,nodes,texture_mem_mb,draw_calls,primitives

var scene: Node3D
var total_frames: int
var sample_interval: int
var samples: Array[Dictionary] = []

func _initialize() -> void:
	var frames_env := OS.get_environment("SPLOOGE_SOAK_FRAMES")
	if not frames_env.is_empty():
		total_frames = int(frames_env)
	else:
		total_frames = 10800  # 3 minutes at 60 Hz
	var interval_env := OS.get_environment("SPLOOGE_SOAK_INTERVAL")
	if not interval_env.is_empty():
		sample_interval = int(interval_env)
	else:
		sample_interval = 600  # every 10 seconds
	call_deferred("_run")

func _frames(n: int) -> void:
	for i in n: await process_frame

func _sample(frame: int) -> void:
	var p = Performance
	var nodes := get_root().find_children("*", "", true, false).size()
	var texture_mem := float(p.get_monitor(p.RENDER_TEXTURE_MEM_USED)) / 1048576.0
	var draw_calls := int(p.get_monitor(p.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var primitives := int(p.get_monitor(p.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var elapsed_ms := Time.get_ticks_msec()
	samples.append({
		"frame": frame,
		"time_ms": elapsed_ms,
		"nodes": nodes,
		"texture_mem_mb": texture_mem,
		"draw_calls": draw_calls,
		"primitives": primitives
	})
	print("SOAK frame=%d time=%dms nodes=%d tex_mem=%.1fMB draw=%d prim=%d" % [
		frame, elapsed_ms, nodes, texture_mem, draw_calls, primitives])

func _run() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(scene)
	await _frames(120)  # let world settle
	
	print("SOAK_START total_frames=%d interval=%d" % [total_frames, sample_interval])
	print("SOAK_HEADER frame,time_ms,nodes,texture_mem_mb,draw_calls,primitives")
	_sample(0)
	
	var frames_done := 0
	while frames_done < total_frames:
		var chunk := minf(sample_interval, total_frames - frames_done)
		await _frames(chunk)
		frames_done += chunk
		_sample(frames_done)
	
	# Summary
	var nodes_start: int = samples[0].nodes
	var nodes_end: int = samples[-1].nodes
	var mem_start: float = samples[0].texture_mem_mb
	var mem_end: float = samples[-1].texture_mem_mb
	var max_nodes: int = 0
	var max_mem: float = 0.0
	for s in samples:
		max_nodes = maxf(max_nodes, s.nodes)
		max_mem = maxf(max_mem, s.texture_mem_mb)
	
	print("SOAK_SUMMARY frames=%d node_delta=%d (start=%d end=%d max=%d) mem_delta=%.1fMB (start=%.1f end=%.1f max=%.1f)" % [
		total_frames, nodes_end - nodes_start, nodes_start, nodes_end, max_nodes,
		mem_end - mem_start, mem_start, mem_end, max_mem])
	
	# Check for concerning growth
	var node_growth: int = nodes_end - nodes_start
	var mem_growth: float = mem_end - mem_start
	# Node growth is expected from ecosystem spawning; flag only excessive growth
	var passed: bool = node_growth < 5000 and mem_growth < 100.0  # generous thresholds for actor churn
	print("SOAK_RESULT %s node_growth=%d mem_growth=%.1fMB" % [passed, node_growth, mem_growth])
	
	quit()