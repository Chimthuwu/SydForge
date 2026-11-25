extends SceneTree

## L89 bounded step — produce the visual-capture material for the human
## sign-off in docs/VISUAL_CAPTURE_TESTPLAN.md: storefront street views
## (five major brands, day and night), night headlights for four vehicle
## shapes, and the pause menu. Windowed run (renders only exist with a
## viewport):
##   Godot_v4.7.2-stable_win64_console.exe --path . \
##     --script res://tests/capture_l89_visuals.gd
## The captures land in tests/captures/l89/. Judging legibility/layout is
## still the human's job; this only produces the evidence.

const OUT_DIR := "res://tests/captures/l89"
const BRANDS := ["McDonalds", "KFC", "7-Eleven"]
const SUPERMARKETS := ["Woolworths", "Coles"]

var scene: Node3D
var camera: Camera3D

func _initialize() -> void:
	call_deferred("_run")

func _frames(n: int) -> void:
	for i in n: await process_frame

func _set_time(hour: float) -> void:
	var tm = scene.get_node_or_null("WorldTimeManager")
	if tm != null:
		tm.set_time(hour)

func _capture(file: String, label: String) -> void:
	for i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(OUT_DIR + "/" + file)
	print("CAPTURED %s -> %s (%dx%d)" % [label, file, img.get_width(), img.get_height()])

func _look(from: Vector3, at: Vector3) -> void:
	camera.global_position = from
	camera.look_at(at, Vector3.UP)

func _shop_sign(brand: String) -> Dictionary:
	for shop in get_nodes_in_group("business_poi"):
		if shop.name.begins_with("Business_" + brand + "_"):
			var sign: Node3D = shop.get_node_or_null("BrandSign")
			if sign != null:
				return {"shop": shop, "sign": sign}
	return {}

func _capture_shop(brand: String, night: bool) -> void:
	var found := _shop_sign(brand)
	if found.is_empty():
		print("NOTE %s: no placed storefront found" % brand)
		return
	var sign: Node3D = found["sign"]
	var pos := sign.global_position
	var basis := sign.global_transform.basis
	for side: float in [1.0, -1.0]:
		var eye: Vector3 = pos + basis.z * 14.0 * side + Vector3(0.0, 1.6, 0.0)
		_look(eye, pos + Vector3(0.0, 0.4, 0.0))
		var tag := ("night" if night else "day") + ("_posz" if side > 0.0 else "_negz")
		await _capture("storefront_%s_%s.png" % [brand.to_lower().replace("-", ""), tag], "%s %s" % [brand, tag])


## Woolworths/Coles are placed by the supermarket system (group "supermarket",
## name Store_<short>), not the business_poi layer — shoot their entrance.
func _capture_supermarket(short: String, night: bool) -> void:
	var store: Node3D = null
	for s in get_nodes_in_group("supermarket"):
		if s.name.begins_with("Store_" + short):
			store = s
			break
	if store == null:
		print("NOTE %s: no supermarket store found" % short)
		return
	var door: Node3D = store.get_node_or_null("Entrance")
	var target: Vector3 = door.global_position if door != null else store.global_position
	for side: float in [1.0, -1.0]:
		var basis: Basis = store.global_transform.basis
		var eye: Vector3 = target + basis.z * 14.0 * side + Vector3(0.0, 2.0, 0.0)
		_look(eye, target + Vector3(0.0, 1.0, 0.0))
		var tag := ("night" if night else "day") + ("_posz" if side > 0.0 else "_negz")
		await _capture("supermarket_%s_%s.png" % [short.to_lower(), tag], "%s %s" % [short, tag])

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	scene = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(scene)
	await _frames(90)
	camera = Camera3D.new()
	camera.fov = 65.0
	scene.add_child(camera)
	camera.make_current()
	var player: Node3D = scene.get_node_or_null("Player")

	# --- 1. Storefronts, day ---
	_set_time(13.0)
	await _frames(20)
	for brand in BRANDS:
		await _capture_shop(brand, false)
	for short in SUPERMARKETS:
		await _capture_supermarket(short, false)

	# --- 2. Storefronts, night (emissive signs) ---
	_set_time(22.0)
	await _frames(30)
	for brand in ["McDonalds", "7-Eleven"]:
		await _capture_shop(brand, true)
	for short in SUPERMARKETS:
		await _capture_supermarket(short, true)

	# --- 3. Night headlights: enter one vehicle of each available shape and
	# shoot a front view plus a rear three-quarter view down the beams.
	# Note: set_headlights() must be CALLED — setting the property directly
	# skips _apply_headlights() and the spots stay invisible.
	var vehicles: Array = scene.get("vehicles") if "vehicles" in scene else []
	var shot := {}
	for v in vehicles:
		if v == null or not is_instance_valid(v):
			continue
		var bike: bool = bool(v.get("is_motorbike"))
		var key := "motorbike" if bike else "car%d" % shot.size()
		if shot.has(bike) or (not bike and shot.size() >= 4):
			continue
		if player == null:
			break
		if v.call("enter", player):
			shot[key] = v
			v.call("set_headlights", true)
			await _frames(10)
			var basis: Basis = v.global_transform.basis
			# Front view: the lens quads and the car's face.
			var front: Vector3 = v.global_position - basis.z * 9.0 + Vector3(3.0, 2.2, 0.0)
			_look(front, v.global_position + Vector3(0.0, 0.5, 0.0))
			await _capture("headlights_%s_front.png" % key, "headlights front " + key)
			# Beam view: from behind and above, looking down the road ahead.
			var rear: Vector3 = v.global_position + basis.z * 8.5 + Vector3(0.0, 3.2, 0.0)
			_look(rear, v.global_position - basis.z * 16.0 + Vector3(0.0, 0.2, 0.0))
			await _capture("headlights_%s_beam.png" % key, "headlights beams " + key)
			v.call("exit_vehicle")
			await _frames(6)

	# --- 4. Pause menu ---
	if player != null and scene.has_method("_open_pause_menu"):
		scene.call("_open_pause_menu")
		await _frames(10)
		await _capture("pause_menu.png", "pause menu")
		var pm = scene.get("pause_menu")
		if pm != null:
			pm.call("close")
		await _frames(6)

	print("RESULT: captures complete")
	quit(0)
