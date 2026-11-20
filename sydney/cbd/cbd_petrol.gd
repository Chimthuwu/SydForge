extends Node3D

## OSM-anchored petrol stations and the petrol-sniffing interaction.
##
## Station positions come from `sydney/world/fuel_stations.json`, which records
## the OpenStreetMap feature ids and the ODbL attribution. Each station is a
## simple but readable forecourt: canopy, two pump islands, price totem, store
## and bollards. The forecourt is not enterable; the gameplay interaction is the
## G-key sniff at a pump, which asks the player for the temporary trip buff.

const DATA_PATH := "res://sydney/world/fuel_stations.json"
const ArtUtil := preload("res://scripts/art.gd")
const StationRuntime := preload("res://sydney/cbd/petrol_station.gd")

const BRAND_COLORS := {
	"BP": Color("1f6b46"),
	"Shell": Color("c7a21a"),
	"Ampol": Color("c53a2e"),
	"Budget Petrol": Color("24536e"),
}

var stats: Dictionary = {}
var stations: Array[Dictionary] = []


func build() -> void:
	name = "PetrolStations"
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("CbdPetrol: fuel data missing or invalid")
		return
	var data: Dictionary = parsed
	var built := 0
	for row: Dictionary in data.get("stations", []):
		if _build_station(row):
			built += 1
	stats = {
		"stations": built,
		"source": str(data.get("source", "")),
		"attribution": str(data.get("attribution", "")),
		"brands": stations.map(func(station: Dictionary) -> String: return str(station["brand"])),
	}


func _build_station(row: Dictionary) -> bool:
	var x := float(row.get("x", 0.0))
	var z := float(row.get("z", 0.0))
	var brand := str(row.get("brand", row.get("name", "FUEL")))
	var station_name := "%s %s" % [brand, str(row.get("osmId", ""))]
	var color: Color = BRAND_COLORS.get(brand, Color("315b55"))
	var node := Node3D.new()
	node.name = "Petrol_%s" % str(row.get("osmId", stations.size()))
	node.position = Vector3(x, 0.0, z)
	node.set_meta("brand", brand)
	node.set_meta("osm_id", str(row.get("osmType", "")) + "/" + str(row.get("osmId", "")))
	node.set_meta("station_name", station_name)
	node.add_to_group("petrol_station")
	node.set_script(StationRuntime)
	add_child(node)
	stations.append({"node": node, "brand": brand, "name": station_name})

	# Forecourt, tank caps and kerbing.
	ArtUtil.box(node, Vector3(0.0, 0.08, 0.0), Vector3(26.0, 0.16, 20.0), Color("4d5053"))
	for x_offset in [-8.0, 8.0]:
		for z_offset in [-5.0, 5.0]:
			ArtUtil.cylinder(node, Vector3(x_offset, 0.20, z_offset), 0.9, 0.10, Color("34383a"))
	for side in [-1.0, 1.0]:
		ArtUtil.box(node, Vector3(side * 13.2, 0.28, 0.0), Vector3(0.35, 0.34, 20.0), Color("b7b2a6"))

	# Two pump islands under one canopy.
	for island in [-5.4, 5.4]:
		ArtUtil.box(node, Vector3(island, 0.28, 1.2), Vector3(2.2, 0.36, 6.2), Color("c8c2b3"))
		for pump_z in [-1.2, 3.6]:
			var pump := Node3D.new()
			pump.position = Vector3(island, 0.5, pump_z)
			node.add_child(pump)
			ArtUtil.box(pump, Vector3(0.0, 1.1, 0.0), Vector3(1.12, 2.05, 0.72), Color("e7e4da"))
			ArtUtil.box(pump, Vector3(0.0, 1.45, 0.38), Vector3(0.82, 0.38, 0.06), Color("253238"))
			ArtUtil.box(pump, Vector3(0.0, 1.02, 0.40), Vector3(0.82, 0.24, 0.06), color)
			ArtUtil.box(pump, Vector3(0.0, 2.19, 0.0), Vector3(1.30, 0.20, 0.90), color)
			ArtUtil.cylinder(pump, Vector3(0.72, 1.1, -0.10), 0.055, 1.9, Color("252525"))
			ArtUtil.box(pump, Vector3(0.72, 0.28, 0.24), Vector3(0.30, 0.36, 0.20), Color("252525"))
			var sniff_label := ArtUtil.label(pump, Vector3(0.0, 2.62, 0.0), "G  SNIFF", 26)
			sniff_label.modulate = Color("fff0b8")
			sniff_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# Canopy: four columns and a branded fascia.
	for x_column in [-10.5, 10.5]:
		for z_column in [-7.0, 7.0]:
			ArtUtil.cylinder(node, Vector3(x_column, 3.2, z_column), 0.34, 6.4, Color("d5d0c4"))
	ArtUtil.box(node, Vector3(0.0, 6.55, 0.0), Vector3(24.0, 0.55, 16.0), Color("dedad0"))
	ArtUtil.box(node, Vector3(0.0, 6.05, 7.9), Vector3(24.0, 0.9, 0.35), color)
	ArtUtil.box(node, Vector3(0.0, 6.05, -7.9), Vector3(24.0, 0.9, 0.35), color)
	var canopy_sign := ArtUtil.label(node, Vector3(0.0, 6.06, 8.12), brand.to_upper(), 64)
	canopy_sign.modulate = Color("fff8e7")
	canopy_sign.billboard = BaseMaterial3D.BILLBOARD_DISABLED

	# Small shop + price totem.
	ArtUtil.box(node, Vector3(0.0, 2.4, -13.4), Vector3(12.0, 4.8, 6.5), Color("d4cebf"))
	ArtUtil.box(node, Vector3(0.0, 1.9, -10.15), Vector3(9.4, 2.6, 0.14), Color("2d444c"))
	ArtUtil.box(node, Vector3(2.9, 1.35, -10.05), Vector3(1.4, 2.3, 0.12), Color("263238"))
	ArtUtil.box(node, Vector3(0.0, 4.95, -13.4), Vector3(13.0, 0.5, 7.0), color)
	var shop_sign := ArtUtil.label(node, Vector3(0.0, 4.9, -9.88), brand.to_upper() + " FOODARY", 38)
	shop_sign.modulate = Color("fff5d6")
	shop_sign.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	ArtUtil.box(node, Vector3(13.0, 4.0, 8.0), Vector3(2.4, 8.0, 0.45), Color("e8e3d7"))
	ArtUtil.box(node, Vector3(13.0, 7.3, 8.24), Vector3(2.1, 1.5, 0.10), color)
	var totem := ArtUtil.label(node, Vector3(13.0, 7.3, 8.36), "199.9", 52)
	totem.modulate = Color("ffffff")
	totem.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	var totem_name := ArtUtil.label(node, Vector3(13.0, 8.25, 8.36), brand.to_upper(), 28)
	totem_name.modulate = Color("ffffff")
	totem_name.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	for z_bollard in [-8.0, -4.0, 0.0, 4.0, 8.0]:
		ArtUtil.cylinder(node, Vector3(-12.4, 0.55, z_bollard), 0.22, 1.1, Color("d8b33e"), 0.12)
	return true


func sniff(player: Node) -> void:
	if player == null or not player.has_method("sniff_petrol"):
		return
	player.call("sniff_petrol", 18.0)
	var district: Node = player.get("world")
	if district != null and district.has_method("sound"):
		district.call("sound", 240.0, 0.22)
