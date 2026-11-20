extends SceneTree

## Rendered inspection of the rebuilt landmarks, retail and civic services.

var game: Node3D
var camera: Camera3D


func _initialize() -> void:
	call_deferred("run")


func settle(count: int) -> void:
	for _index in count:
		await process_frame


func capture(label: String, position: Vector3, target: Vector3, fov: float = 58.0) -> void:
	camera.position = position
	camera.fov = fov
	camera.look_at(target)
	camera.current = true
	await settle(5)
	await RenderingServer.frame_post_draw
	var path := "res://tests/civic_" + label + ".png"
	var error := root.get_texture().get_image().save_png(path)
	print("CAPTURED: ", label, " -> ", path, " error=", error)


func run() -> void:
	game = load("res://scenes/main.tscn").instantiate() as Node3D
	root.add_child(game)
	await settle(12)
	camera = Camera3D.new()
	camera.near = 0.2
	camera.far = 3000.0
	game.add_child(camera)
	camera.current = true

	await capture("town_hall", Vector3(-69.0, 10.0, 22.0), Vector3(-168.0, 15.0, 22.0), 64.0)
	await capture("town_hall_aerial", Vector3(-168.0, 205.0, 60.0), Vector3(-168.0, 8.0, 22.0), 55.0)
	await capture("hyde_park", Vector3(332.0, 4.0, -205.0), Vector3(332.0, 4.0, -178.0), 62.0)
	await capture("park_ground", Vector3(300.0, 2.2, -260.0), Vector3(348.0, 3.0, -225.0), 68.0)
	await capture("circular_quay", Vector3(250.0, 26.0, -1490.0), Vector3(270.0, 3.0, -1370.0), 62.0)
	await capture("darling_harbour", Vector3(-718.0, 48.0, -286.0), Vector3(-612.0, 2.0, -540.0), 60.0)

	var shops := get_nodes_in_group("retail_shop")
	if not shops.is_empty():
		var shop := shops[0] as Node3D
		var outward: Vector3 = shop.get_meta("outward", Vector3.FORWARD)
		await capture("retail", shop.global_position + outward * 15.0 + Vector3.UP * 3.0, shop.global_position + Vector3.UP * 3.0, 52.0)
		await capture("retail_wall", shop.global_position + outward * 8.0 + Vector3.UP * 2.0, shop.global_position + Vector3.UP * 4.0, 58.0)
	var markets := get_nodes_in_group("supermarket")
	if not markets.is_empty():
		var market := markets[0] as Node3D
		var outward := Vector3(sin(market.rotation.y), 0.0, cos(market.rotation.y))
		await capture("woolworths", market.global_position + outward * 18.0 + Vector3.UP * 5.0, market.global_position + Vector3.UP * 3.5, 52.0)
		var player: Node3D = get_first_node_in_group("player")
		if player != null:
			market.call("enter", player)
			var interior: Vector3 = market.get_meta("interior_spawn")
			await capture("woolworths_interior", interior + Vector3(0.0, 1.0, 0.5), interior + Vector3(0.0, 1.1, -10.0), 66.0)
			market.call("leave", player)
	var stations := get_nodes_in_group("petrol_station")
	if not stations.is_empty():
		var station := stations[0] as Node3D
		await capture("petrol", station.global_position + Vector3(28.0, 14.0, 28.0), station.global_position + Vector3.UP * 4.0, 58.0)

	game.queue_free()
	await process_frame
	quit()
