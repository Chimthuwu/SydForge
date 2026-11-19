class_name InnerWestCharacter
extends RefCounted

## Neighbourhood character and architecture style rules for the Inner West
## district (Phase 6C).
##
## This is a stylised creative layer, not survey data: OSM supplies footprints,
## heights where tagged, and the neighbourhood name; this table decides what a
## "Glebe terrace", a "Marrickville warehouse" or a "King Street shopfront"
## look like. All choices are deterministic from the footprint id so the city
## is stable between runs.


## Wall palettes are lists of hex colours; the pick is hash-driven per building.
const PALETTES := {
	"brick_dark": ["7d4a37", "8a5040", "6f3f2e", "96573f", "7a4a38"],
	"brick_red": ["9b5d43", "a2654a", "8a5040", "a05a3f"],
	"brick painted": ["cfc5ae", "b9c2b5", "d8c9a8", "c9b7a0", "c2ccc4", "d3c2a4"],
	"federation": ["8a4a35", "7d4433", "96543c", "6f3f2e"],
	"render": ["c8c3b8", "b5ada0", "d0cbc0", "bfb6a6", "cdc5b3"],
	"warehouse_brick": ["7d5340", "715046", "6b4a3f", "835c49"],
	"corrugated": ["8b9196", "9aa0a4", "7f858a"],
	"apartment": ["c8c3b8", "b5ada0", "d0cbc0", "a9b4b8", "c2a48e", "b9a7a0"],
	"sandstone": ["c9b79a", "d8c7a8", "bfae92", "cfc0a2"],
	"glass_commercial": ["8fa3ad", "9fb0b8", "7e94a0", "a8b7bd"],
}

const ROOF_COLOURS := {
	"slate": "5f646a",
	"terractotta": "b0664a",
	"corrugated_iron": "767c82",
	"flat_dark": "6b6f74",
	"tar": "4e5257",
}

## Neighbourhood -> dominant style classes with weights. Any style not listed
## for a neighbourhood falls back to the global mix. Classes:
##   terrace_victorian, house_federation, house_detached, shopfront, pub,
##   warehouse, apartment, commercial, church, civic, university, shed
const NEIGHBOURHOOD_MIX := {
	"pyrmont": {"apartment": 0.55, "warehouse": 0.25, "commercial": 0.12, "terrace_victorian": 0.08},
	"ultimo": {"apartment": 0.4, "commercial": 0.25, "university": 0.15, "terrace_victorian": 0.2},
	"glebe": {"terrace_victorian": 0.78, "pub": 0.06, "shopfront": 0.08, "apartment": 0.08},
	"forest lodge": {"terrace_victorian": 0.8, "house_federation": 0.1, "warehouse": 0.1},
	"annandale": {"house_federation": 0.45, "terrace_victorian": 0.45, "shopfront": 0.1},
	"balmain": {"terrace_victorian": 0.82, "pub": 0.08, "warehouse": 0.1},
	"balmain east": {"terrace_victorian": 0.82, "pub": 0.08, "warehouse": 0.1},
	"rozelle": {"warehouse": 0.35, "terrace_victorian": 0.4, "shopfront": 0.15, "house_federation": 0.1},
	"lilyfield": {"warehouse": 0.3, "terrace_victorian": 0.5, "house_federation": 0.2},
	"leichhardt": {"shopfront": 0.3, "terrace_victorian": 0.5, "apartment": 0.2},
	"haberfield": {"house_federation": 0.9, "shopfront": 0.1},
	"newtown": {"shopfront": 0.3, "terrace_victorian": 0.55, "pub": 0.05, "apartment": 0.1},
	"enmore": {"shopfront": 0.2, "terrace_victorian": 0.65, "warehouse": 0.15},
	"stanmore": {"terrace_victorian": 0.5, "house_federation": 0.4, "apartment": 0.1},
	"petersham": {"terrace_victorian": 0.5, "house_federation": 0.35, "shopfront": 0.15},
	"marrickville": {"warehouse": 0.35, "terrace_victorian": 0.35, "apartment": 0.2, "house_detached": 0.1},
	"camperdown": {"terrace_victorian": 0.4, "university": 0.25, "apartment": 0.2, "warehouse": 0.15},
	"chippendale": {"apartment": 0.35, "terrace_victorian": 0.3, "commercial": 0.2, "warehouse": 0.15},
	"redfern": {"terrace_victorian": 0.45, "apartment": 0.25, "shopfront": 0.2, "commercial": 0.1},
	"erskineville": {"terrace_victorian": 0.6, "house_detached": 0.25, "apartment": 0.15},
	"alexandria": {"warehouse": 0.45, "apartment": 0.4, "commercial": 0.15},
	"st peters": {"warehouse": 0.5, "terrace_victorian": 0.3, "apartment": 0.2},
}

const GLOBAL_MIX := {
	"terrace_victorian": 0.45, "apartment": 0.15, "warehouse": 0.12,
	"house_federation": 0.1, "shopfront": 0.1, "commercial": 0.05,
	"house_detached": 0.03,
}


static func neighbourhood_mix(name_lower: String) -> Dictionary:
	if NEIGHBOURHOOD_MIX.has(name_lower):
		return NEIGHBOURHOOD_MIX[name_lower]
	for key: String in NEIGHBOURHOOD_MIX:
		if key.is_subsequence_of(name_lower) or name_lower.is_subsequence_of(key):
			return NEIGHBOURHOOD_MIX[key]
	return GLOBAL_MIX


## Assign a style class to one building from its OSM tags, venue flags and
## neighbourhood. Tags win where they are specific; otherwise the
## neighbourhood mix decides, deterministically from the id hash.
static func style_class(building: Dictionary, neighbourhood_name: String, id_hash: int) -> String:
	var tag: String = String(building.get("building", "yes"))
	if building.get("pub", false):
		return "pub"
	match tag:
		"church", "cathedral", "chapel", "mosque", "synagogue", "temple", "shrine":
			return "church"
		"school", "kindergarten":
			return "civic"
		"university", "college":
			return "university"
		"hospital":
			return "civic"
		"warehouse", "industrial", "factory", "hangar", "barn":
			return "warehouse"
		"commercial", "office":
			return "commercial"
		"retail":
			return "shopfront"
		"apartments", "residential", "dormitory":
			if float(building.get("heightM", 8.0)) >= 9.5 or (building.get("levels") != null and float(building.get("levels")) >= 3.0):
				return "apartment"
			return "terrace_victorian"
		"house", "detached", "bungalow", "semidetached_house":
			return "house_detached" if id_hash % 3 == 0 else "house_federation"
		"terrace":
			return "terrace_victorian"
		"shed", "garage", "garages", "hut", "roof", "carport", "greenhouse", "service":
			return "shed"
		"hotel":
			return "apartment"
		"station", "train_station", "transportation":
			return "civic"
	if building.get("shop", false):
		return "shopfront"
	# area-driven heuristics for the generic yes/building tag
	var area := float(building.get("areaM2", 100.0))
	if area > 1400.0 and float(building.get("heightM", 8.0)) <= 12.0:
		return "warehouse"
	if area > 900.0 and float(building.get("heightM", 8.0)) >= 14.0:
		return "commercial"
	if area < 70.0:
		return "shed"
	# neighbourhood mix (deterministic)
	var mix := neighbourhood_mix(neighbourhood_name.to_lower())
	var roll := float(absi(id_hash) % 1000) / 1000.0
	var cumulative := 0.0
	for style: String in mix:
		cumulative += float(mix[style])
		if roll <= cumulative:
			return style
	return "terrace_victorian"


## Visual specification resolved per building: wall colour, roof style, roof
## colour, trim colour, ground band, chimneys, awning, floor bands.
static func visual_for(style: String, id_hash: int, height: float, area: float, has_shop: bool) -> Dictionary:
	var palette_name := "render"
	var roof_kind := "parapet"
	var roof_colour := Color(ROOF_COLOURS["flat_dark"])
	var chimney := false
	var floor_bands := false
	var ground_band := false
	var awning := false
	var trim := Color("ffffff") * 0.0

	match style:
		"terrace_victorian":
			palette_name = "brick painted" if id_hash % 10 < 4 else "brick_dark"
			roof_kind = "parapet"
			roof_colour = Color(ROOF_COLOURS["slate"])
			chimney = true
			trim = Color("efe6d2")
			ground_band = false
		"pub":
			palette_name = "brick painted" if id_hash % 6 < 3 else "brick_dark"
			roof_kind = "parapet"
			roof_colour = Color(ROOF_COLOURS["slate"])
			chimney = true
			ground_band = true
			trim = Color("e8d9be")
		"house_federation":
			palette_name = "federation"
			roof_kind = "gable" if id_hash % 5 < 3 else "hip"
			roof_colour = Color(ROOF_COLOURS["terractotta"])
			chimney = true
			trim = Color("e3d7bd")
		"house_detached":
			palette_name = "brick painted" if id_hash % 4 < 2 else "brick_dark"
			roof_kind = "gable"
			roof_colour = Color(ROOF_COLOURS["terractotta"]) if id_hash % 3 == 0 else Color(ROOF_COLOURS["slate"])
			chimney = true
		"shopfront":
			palette_name = "brick painted" if id_hash % 8 < 4 else "render"
			roof_kind = "parapet"
			roof_colour = Color(ROOF_COLOURS["tar"])
			ground_band = true
			awning = true
			trim = Color("f2ead6")
		"warehouse":
			palette_name = "warehouse_brick" if id_hash % 3 < 2 else "corrugated"
			roof_kind = "sawtooth" if area > 700.0 and id_hash % 4 == 0 else "flat"
			roof_colour = Color(ROOF_COLOURS["corrugated_iron"])
			trim = Color("5c6066")
		"apartment":
			palette_name = "apartment"
			roof_kind = "flat"
			roof_colour = Color(ROOF_COLOURS["tar"])
			floor_bands = true
			trim = Color("9aa39d")
		"commercial":
			palette_name = "glass_commercial"
			roof_kind = "flat"
			roof_colour = Color(ROOF_COLOURS["tar"])
			floor_bands = true
		"university":
			palette_name = "sandstone"
			roof_kind = "flat"
			roof_colour = Color(ROOF_COLOURS["slate"])
			trim = Color("b7a586")
			floor_bands = true
		"civic":
			palette_name = "sandstone"
			roof_kind = "gable"
			roof_colour = Color(ROOF_COLOURS["slate"])
			trim = Color("c4b394")
		"church":
			palette_name = "sandstone"
			roof_kind = "gable"
			roof_colour = Color(ROOF_COLOURS["slate"])
		"shed":
			palette_name = "corrugated"
			roof_kind = "gable"
			roof_colour = Color(ROOF_COLOURS["corrugated_iron"])
		_:
			palette_name = "render"

	var palette: Array = PALETTES.get(palette_name, PALETTES["render"])
	var wall := Color(String(palette[absi(id_hash) % palette.size()]))
	# gentle per-building variation so rows of terraces are not uniform
	wall = wall.lightened((id_hash % 7 - 3) * 0.012)

	var spec := {
		"style": style,
		"wall": wall,
		"roofKind": roof_kind,
		"roof": roof_colour,
		"trim": trim if trim.a > 0.0 else wall.darkened(0.18),
		"chimney": chimney and height < 14.0,
		"floorBands": floor_bands and height > 9.0,
		"groundBand": ground_band,
		"awning": awning,
		"parapet": roof_kind == "parapet",
	}
	if has_shop and (style == "terrace_victorian" or style == "house_detached"):
		# shop in the ground floor of a terrace: give it a shopfront band
		spec["groundBand"] = true
		spec["awning"] = true
	return spec
