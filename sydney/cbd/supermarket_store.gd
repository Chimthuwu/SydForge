extends Node3D

## Runtime behaviour for one enterable Woolworths/Coles store. The
## `cbd_supermarkets.gd` builder attaches this script so district E presses can
## enter, steal and leave through the same node.


func interact(player: Node3D) -> void:
	if player == null:
		return
	if player.get("in_supermarket") == self:
		if player.global_position.distance_to(get_meta("interior_exit")) < 3.2:
			leave(player)
		else:
			steal(player)
		return
	if player.global_position.distance_to(global_position) < 8.0:
		enter(player)


func enter(player: Node3D) -> void:
	if player.get("in_supermarket") != null:
		return
	set_meta("saved_transform", player.global_transform)
	player.set("in_supermarket", self)
	player.set("vehicle", null)
	player.global_position = get_meta("interior_spawn")
	player.velocity = Vector3.ZERO
	var world: Object = player.get("world")
	if world != null:
		world.set("message", "%s · E AT SHELF: SHOPLIFT · E AT DOOR: LEAVE" % get_meta("store_name"))
		if world.get("rig") != null:
			world.get("rig").set("yaw", PI)


func leave(player: Node3D) -> void:
	var saved: Transform3D = get_meta("saved_transform")
	player.global_position = saved.origin + Vector3.UP * 0.25
	player.velocity = Vector3.ZERO
	player.set("in_supermarket", null)
	var world: Object = player.get("world")
	if world != null:
		world.set("message", "%s · come again" % get_meta("store_name"))


func steal(player: Node3D) -> void:
	if player.get("in_supermarket") != self:
		return
	var nearest: Node3D = null
	var nearest_distance := 3.2
	for shelf: Node3D in get_meta("shelves"):
		var distance: float = player.global_position.distance_to(shelf.global_position)
		if distance < nearest_distance:
			nearest = shelf
			nearest_distance = distance
	if nearest == null:
		return
	var product: Node3D = null
	for child: Node in nearest.get_children():
		if child.is_in_group("shop_product") and child.visible:
			product = child as Node3D
			break
	if product == null:
		return
	product.visible = false
	var value: int = 7 + (absi(int(get_meta("steals"))) * 6 + int(Time.get_ticks_msec()) % 17)
	var total: int = int(get_meta("loot")) + value
	set_meta("loot", total)
	set_meta("steals", int(get_meta("steals")) + 1)
	if player.has_method("add_shoplift"):
		player.call("add_shoplift", value)
	if int(get_meta("steals")) >= 3 and not bool(get_meta("alarm")):
		set_meta("alarm", true)
		var world: Node = player.get("world")
		if world != null:
			world.set("message", "ALARM! SECURITY IS COMING · GET TO THE DOOR")
			if world.has_method("sound"):
				world.call("sound", 780.0, 0.35)


func _process(_dt: float) -> void:
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var world: Object = player.get("world")
	if world == null:
		return
	if player.get("in_supermarket") == self:
		if player.global_position.distance_to(get_meta("interior_exit")) < 3.2:
			world.set("message", "E: LEAVE %s" % get_meta("store_name"))
		elif bool(get_meta("alarm")):
			world.set("message", "SHOPLIFTED $%d · ALARM · E NEAR SHELF TO GRAB MORE" % int(get_meta("loot")))
		else:
			world.set("message", "%s · SHOPLIFTED $%d · E NEAR SHELF" % [get_meta("store_name"), int(get_meta("loot"))])
	elif player.global_position.distance_to(global_position) < 8.0:
		world.set("message", "E: ENTER %s" % get_meta("store_name"))
