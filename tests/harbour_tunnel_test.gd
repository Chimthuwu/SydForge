extends SceneTree

## Owner bug: trains south of the Harbour Bridge sank into the ground and clipped
## through roads. Walks the real route from the bridge end to Wynyard and checks
## that the train's whole envelope is clear: no street surface passes through it,
## and once it is in the bore it stays below the ground slab.
##
##   ./Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/harbour_tunnel_test.gd

const D := preload("res://scripts/sydney_cbd_district.gd")
const TRAIN_HEIGHT := 4.4  # wheels on the rail to roof

var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)


func _run() -> void:
	var scene = D.new()
	get_root().add_child(scene)
	for i in 15:
		await physics_frame
	var rail = scene.find_child("SydneyRailNetwork", true, false)
	var route: Array = rail.get("main_route_points")
	var bridge: Vector2i = rail.get("_bridge_range")
	var wynyard := int(rail.call("get_station_route_index", "wynyard"))
	var space: PhysicsDirectSpaceState3D = scene.get_world_3d().direct_space_state

	var first_bore := -1
	for i in range(bridge.y, wynyard):
		if rail.call("_is_tunnel_segment", i):
			first_bore = i
			break
	_check(first_bore > 0, "a covered bore exists between the bridge and Wynyard")
	var dist := 0.0
	for i in range(bridge.y, maxi(first_bore, bridge.y)):
		dist += (route[i] as Vector3).distance_to(route[i + 1])
	_check(dist < 100.0, "bore starts at the foot of the bridge (%.0f m of open ramp)" % dist)

	var highest := -INF
	for i in range(first_bore, wynyard - 5):
		highest = maxf(highest, (route[i] as Vector3).y + TRAIN_HEIGHT)
	_check(highest < -1.0, "train roof stays under the ground slab from the bore to Wynyard (max %.2f)" % highest)

	# Anything solid crossing the middle of the train envelope, on both tracks.
	var blocked: Array = []
	for i in range(bridge.y, wynyard - 6):
		var a: Vector3 = route[i]
		var b: Vector3 = route[i + 1]
		var side := Vector3.UP.cross((b - a).normalized()).normalized()
		for step in 4:
			var p := a.lerp(b, step / 4.0)
			for offset in [-2.9, -1.9, -0.9, 0.9, 1.9, 2.9]:
				var base: Vector3 = p + side * offset
				var query := PhysicsRayQueryParameters3D.create(
					base + Vector3.UP * TRAIN_HEIGHT, base + Vector3.UP * 0.7)
				query.hit_from_inside = false
				var hit := space.intersect_ray(query)
				if not hit.is_empty():
					blocked.append("%d %s@%.2f" % [i, hit.collider.name, hit.position.y])
	_check(blocked.is_empty(), "nothing solid passes through the train from the bridge to Wynyard (%d hits %s)" % [blocked.size(), blocked.slice(0, 6)])

	# Covered above ground from a quarter of the way up the bridge: something solid
	# sits over the train roof at every step between the arch and the bore.
	var arch := int(rail.call("gallery_start_index"))
	var share := float(bridge.y - arch) / float(bridge.y - bridge.x)
	_check(arch > 0 and absf(share - 0.25) < 0.03, "tunnel mouth is a quarter of the way up the bridge (%.2f)" % share)
	var gaps: Array = []
	for i in range(arch + 1, first_bore):
		for step in 4:
			var p: Vector3 = (route[i] as Vector3).lerp(route[i + 1], step / 4.0)
			var up := PhysicsRayQueryParameters3D.create(
				p + Vector3.UP * TRAIN_HEIGHT, p + Vector3.UP * 14.0)
			up.hit_back_faces = true
			var hit := space.intersect_ray(up)
			if hit.is_empty() or str(hit.collider.name).begins_with("Bridge"):
				gaps.append(i)
	_check(gaps.is_empty(), "the train is under cover from the arch to the bore (%d open samples %s)" % [gaps.size(), gaps.slice(0, 8)])
	_check(rail.get_node_or_null("RailApproachPortalArch") != null, "stone arch portal marks the entrance")

	# Walk the real player through the tunnel, both ways, with the movement keys:
	# it must arrive, and the floor under it must be the rail floor all the way.
	var player: CharacterBody3D = get_first_node_in_group("player")
	# Regression: track and bore pieces had the route height added twice.
	var deepest := INF
	var tallest := -INF
	for p: Vector3 in route:
		deepest = minf(deepest, p.y)
		tallest = maxf(tallest, p.y)
	for spec in [["RailSteel", deepest, tallest + 0.3], ["RailBallast", deepest - 0.5, tallest], ["RailTunnelWalls", deepest - 0.5, 0.0], ["RailTunnelCeiling", deepest + 5.5, 0.0]]:
		var bounds: AABB = (rail.get_node(spec[0]) as MeshInstance3D).get_aabb()
		_check(bounds.position.y > spec[1] - 0.2 and bounds.end.y < spec[2] + 0.2, "%s is drawn at the track's height (%.1f .. %.1f)" % [spec[0], bounds.position.y, bounds.end.y])

	# The bridge spawn seats the player in a parked car: get out before walking.
	if player.vehicle != null:
		player.vehicle.exit_vehicle()
	for i in 60:
		await physics_frame
	_check(player.vehicle == null, "player is on foot for the walk")
	for gait in [["aim", 4.2], ["", 6.4], ["sprint", 11.2]]:
		for ends in [[arch + 2, first_bore + 4], [first_bore + 4, arch + 2]]:
			for lane in [-3.0, 0.0, 3.0]:
				var step := 1 if ends[1] > ends[0] else -1
				var index: int = ends[0]
				var aside := func(i: int) -> Vector3:
					var forward: Vector3 = (route[i + 1] as Vector3) - (route[i - 1] as Vector3)
					return (route[i] as Vector3) + Vector3.UP.cross(forward.normalized()).normalized() * lane
				player.global_position = aside.call(index) + Vector3.UP * 0.4
				player.velocity = Vector3.ZERO
				player.invulnerable = 999.0
				for i in 20:
					await physics_frame
				var worst := 0.0
				var where := -1
				var ticks := 0
				while index != ends[1] and ticks < 12000:
					ticks += 1
					var target: Vector3 = aside.call(index + step)
					var flat := Vector3(target.x - player.global_position.x, 0.0, target.z - player.global_position.z)
					if flat.length() < 1.0:
						index += step
						continue
					scene.rig.yaw = atan2(-flat.x, -flat.z)
					Input.action_press("forward")
					if gait[0] != "":
						Input.action_press(gait[0])
					await physics_frame
					var a: Vector3 = aside.call(index)
					var span := Vector2(target.x - a.x, target.z - a.z)
					var t := clampf(Vector2(player.global_position.x - a.x, player.global_position.z - a.z).dot(span) / maxf(span.length_squared(), 0.001), 0.0, 1.0)
					var error := player.global_position.y - lerpf(a.y, target.y, t)
					if ticks > 30 and absf(error) > absf(worst):
						worst = error
						where = index
				Input.action_release("forward")
				if gait[0] != "":
					Input.action_release(gait[0])
				_check(index == ends[1] and absf(worst) < 0.75, "player at %.1f m/s stays on the tunnel floor %d -> %d, %+.0f m off centre (reached %d, worst %.2f m at %d)" % [gait[1], ends[0], ends[1], lane, index, worst, where])

	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			var camera := Camera3D.new()
			scene.add_child(camera)
			camera.far = 4000.0
			var mouth: Vector3 = route[arch]
			var uphill: Vector3 = (route[arch - 6] as Vector3) - mouth
			var side := Vector3.UP.cross(uphill).normalized()
			var low: Vector3 = route[bridge.y]
			var deep: Vector3 = route[bridge.y - 6]
			for shot in [["_inside_down", deep + Vector3.UP * 2.2, (route[bridge.y + 4] as Vector3) + Vector3.UP * 1.5],
				["_inside_up", (route[bridge.y + 8] as Vector3) + Vector3.UP * 2.2, (route[bridge.y] as Vector3) + Vector3.UP * 1.8],
				["", mouth + uphill.normalized() * 24.0 + Vector3.UP * 4.5, mouth + Vector3.UP * 3.0],
				["_side", low + side * 95.0 + Vector3.UP * 55.0, low.lerp(mouth, 0.4)]]:
				camera.global_position = shot[1]
				for old in camera.get_children():
					old.free()
				if str(shot[0]).begins_with("_inside"):
					var torch := OmniLight3D.new()
					torch.omni_range = 40.0
					camera.add_child(torch)
				camera.look_at(shot[2], Vector3.UP)
				camera.current = true
				for i in 40:
					await process_frame
				get_root().get_viewport().get_texture().get_image().save_png(arg.substr(7).replace(".png", shot[0] + ".png"))

	print("RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
