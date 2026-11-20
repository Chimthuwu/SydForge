extends Node3D

## Runtime interaction for one OSM petrol station. The forecourt builder attaches
## this script so the player's G-key sniff can find a pump and start the trip.


func _process(_dt: float) -> void:
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	if player.get("vehicle") != null or player.get("in_supermarket") != null:
		return
	if player.global_position.distance_to(global_position) < 9.0:
		var world: Object = player.get("world")
		if world != null:
			world.set("message", "G: HUFF PREMIUM · 18s PETROL TRIP · +35% DAMAGE")


func sniff(player: Node) -> void:
	if player == null or not player.has_method("sniff_petrol"):
		return
	player.call("sniff_petrol", 18.0)
	var district: Node = player.get("world")
	if district != null and district.has_method("sound"):
		district.call("sound", 240.0, 0.22)
