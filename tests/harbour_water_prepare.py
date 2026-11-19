"""Phase 6A — generate sydney/harbour/harbour_water.json from the Sydney pipeline.

Sources (read-only):
  * Z:\\GITHUB\\_EXPERIMENTS\\Sydney\\sydney-osm-world\\data\\normalized\\waterways.json
    - relation/15522136 Port Jackson (15,075-pt outer ring, 25 inner rings)
    - relation/1252425  Sydney Harbour
    - relation/17064384 Sydney Cove (bay)
    - relation/19541746 Woolloomooloo Bay (bay)
    - relation/17039612 Nawi Cove (bay)
    All use the game projection already (origin -33.873/151.208,
    92459.893 m/deg lon, 111019.656 m/deg lat, 1 unit = 1 m, north = -Z).
  * sydney/landmarks/harbour_bridge.json — the Phase 5 site land rings; harbour
    water is cut against them so it never covers the bridge site's ground.
  * sydney/world/stage_a/world.json — bounds (ground box), old water rings
    (non-harbour ponds are preserved), buildings (overlap measured).

Emission:
  * waterRings  — harbour water exteriors (holes excluded), y 0.02 in game.
  * islandRings — the water polygon holes (Goat Island etc.), land patches above water.
  * pondRings   — old Stage A water rings that are NOT harbour (fountains/ponds),
    preserved with the legacy flat water look.
  * landRings   — collar land: scope minus water minus ground box minus bridge land.
  * collisionRings — waterRings + islandRings + pondRings for the Phase 4 barrier.

Deterministic: no timestamps, fixed source order, rounding to 1 cm.
"""
import json
from shapely.geometry import Polygon, MultiPolygon, box
from shapely.ops import unary_union

PIPE = r"Z:\GITHUB\_EXPERIMENTS\Sydney\sydney-osm-world\data\normalized\waterways.json"
GAME = r"Z:\GITHUB\_GAMES\New folder"
BRIDGE_JSON = GAME + r"\sydney\landmarks\harbour_bridge.json"
WORLD_JSON = GAME + r"\sydney\world\stage_a\world.json"
OUT = GAME + r"\sydney\harbour\harbour_water.json"

# Southern-harbour scope (game metres). Chosen so every named area in the brief
# is inside (Woolloomooloo Bay ends at X 1624; the authored Blackwattle Bay west
# shore reaches X ~-1265) while North Shore districts stay deferred (north edge
# = the Phase 5 bridge site edge, Z -3300). Rozelle Bay and White Bay stay out
# (Inner West, future phase).
SCOPE_MIN_X, SCOPE_MAX_X = -1400.0, 1700.0
SCOPE_MIN_Z, SCOPE_MAX_Z = -3300.0, 700.0
GROUND_MARGIN = 150.0  # sydney_world.gd _build_ground uses bounds +/- 150 m
POND_COVER_THRESHOLD = 0.8  # old ring superseded when harbour water covers >= 80%
COLLAR_MIN_AREA = 25.0
WATER_Y = 0.02
ISLAND_Y = 0.1

LAT0, LON0 = -33.873, 151.208
MX, MZ = 92459.893, 111019.656

HARBOUR_SOURCES = [
    "relation/15522136",  # Port Jackson
    "relation/1252425",   # Sydney Harbour
    "relation/17064384",  # Sydney Cove
    "relation/19541746",  # Woolloomooloo Bay
    "relation/17039612",  # Nawi Cove
    "relation/2310868",   # unnamed basin east of the Domain (Garden Island side)
]

# Authored extension: Blackwattle Bay is real water but absent from every
# pipeline water feature (verified against raw and normalized payloads), so it
# is approximated here per the relaxed creative direction. The mouth overlaps
# the mapped Johnstons Bay arm so the union is seamless; shores follow the real
# bay (Pyrmont west / Glebe east), ~280 m at the mouth narrowing to ~170 m at
# the Glebe tip.
AUTHORED_BLACKWATTLE = [
    (-1265.0, -520.0), (-1240.0, -600.0), (-1180.0, -660.0), (-1100.0, -680.0),
    (-1020.0, -670.0), (-985.0, -620.0), (-1010.0, -350.0), (-1035.0, -120.0),
    (-1050.0, 80.0), (-1062.0, 220.0), (-1090.0, 300.0), (-1150.0, 312.0),
    (-1195.0, 288.0), (-1222.0, 100.0), (-1240.0, -120.0), (-1255.0, -350.0),
]


def proj(lon, lat):
    return ((lon - LON0) * MX, -(lat - LAT0) * MZ)


def ring_out(coords):
    """Round to 1 cm and drop consecutive duplicates; drop the closing vertex."""
    pts = []
    for x, z in coords:
        p = (round(float(x), 2), round(float(z), 2))
        if not pts or abs(pts[-1][0] - p[0]) + abs(pts[-1][1] - p[1]) > 0.001:
            pts.append([p[0], p[1]])
    while len(pts) > 1 and abs(pts[0][0] - pts[-1][0]) + abs(pts[0][1] - pts[-1][1]) <= 0.001:
        pts.pop()
    return pts


def polys_of(item):
    rings = item.get("rings") or {}
    outers = [Polygon([proj(p[1], p[0]) for p in ring]) for ring in rings.get("outer", [])]
    inners = [Polygon([proj(p[1], p[0]) for p in ring]) for ring in rings.get("inner", [])]
    out = []
    for o in outers:
        if not o.is_valid:
            o = o.buffer(0)
        holes = [h for h in inners if o.contains(h.representative_point())]
        if holes:
            try:
                o = Polygon(o.exterior, [h.exterior for h in holes])
            except Exception:
                pass
        if o.area >= 40.0:
            out.append(o)
    return out


def parts_of(geom):
    if geom.is_empty:
        return []
    if isinstance(geom, MultiPolygon):
        return [g for g in geom.geoms if g.area > 0.0]
    return [geom]


def main():
    payload = json.load(open(PIPE, encoding="utf-8"))["payload"]["water"]
    features = {item["id"]: item for item in payload}

    harbour = unary_union(
        [p for key in HARBOUR_SOURCES for p in polys_of(features[key])]
        + [Polygon(AUTHORED_BLACKWATTLE)])
    scope = box(SCOPE_MIN_X, SCOPE_MIN_Z, SCOPE_MAX_X, SCOPE_MAX_Z)

    bridge = json.load(open(BRIDGE_JSON, encoding="utf-8"))
    bridge_ref = bridge.get("reference", bridge)
    bridge_land = unary_union(
        [Polygon([(p[0], p[1]) for p in ring]) for ring in bridge_ref["landRings"]])
    bridge_water = unary_union(
        [Polygon([(p[0], p[1]) for p in ring]) for ring in bridge_ref["waterRings"]])

    world = json.load(open(WORLD_JSON, encoding="utf-8"))
    b = world["bounds"]
    ground = box(b["minX"] - GROUND_MARGIN, b["minZ"] - GROUND_MARGIN,
                 b["maxX"] + GROUND_MARGIN, b["maxZ"] + GROUND_MARGIN)

    water = harbour.intersection(scope).difference(bridge_land)

    # ---- water rings (exteriors) and island rings (holes) ------------------
    # Islands (water polygon holes) are emitted separately as land patches
    # ABOVE the water plane; the water exteriors fill them, so they must not
    # also be emitted as collar land at y 0 (invisible under water).
    water_rings, island_rings, island_polys = [], [], []
    water_area = 0.0
    for part in parts_of(water):
        if part.area < 12.0:
            continue
        water_area += part.area
        ring = ring_out(part.exterior.coords)
        if len(ring) >= 3:
            water_rings.append(ring)
        for hole in part.interiors:
            hp = Polygon(hole)
            if hp.area >= 25.0:
                island_rings.append(ring_out(hole.coords))
                island_polys.append(hp)

    # ---- preserve non-harbour Stage A water (ponds, fountains) -------------
    pond_rings = []
    for ring in world["water"]["rings"]:
        poly = Polygon([(p[0], p[1]) for p in ring])
        covered = water.intersection(poly).area / max(poly.area, 1e-6)
        if covered < POND_COVER_THRESHOLD and poly.area >= 40.0:
            pond_rings.append(ring_out(poly.exterior.coords))
    pond_area = sum(Polygon([(p[0], p[1]) for p in r]).area for r in pond_rings)

    # ---- land collar --------------------------------------------------------
    # collar = scope - water - ground box - bridge land. Interiors of collar
    # parts are areas already covered by other systems (water rings, the ground
    # box or bridge land), so holes are ignored: emitting them would duplicate
    # the small water rings and z-fight coincident triangles.
    collar = scope.difference(water).difference(ground).difference(bridge_land)
    land_rings = []
    for part in parts_of(collar):
        if part.area < COLLAR_MIN_AREA:
            continue
        if any(ip.contains(part.representative_point()) for ip in island_polys):
            continue  # water-hole island: already emitted above the water plane
        land_rings.append(ring_out(part.exterior.coords))
    land_area = sum(Polygon([(p[0], p[1]) for p in r]).area for r in land_rings)

    # ---- measurements -------------------------------------------------------
    buildings = [Polygon([(p[0], p[1]) for p in row["ring"]]) for row in world["buildings"]]
    building_overlap = water.intersection(unary_union(buildings)).area
    parks = [Polygon([(p[0], p[1]) for p in ring])
             for park in world.get("parks", []) for ring in park.get("rings", [])]
    park_overlap = water.intersection(unary_union(parks)).area if parks else 0.0
    old_water = unary_union([Polygon([(p[0], p[1]) for p in ring])
                             for ring in world["water"]["rings"]])
    old_uncovered = old_water.difference(unary_union(
        [water] + [Polygon([(p[0], p[1]) for p in r]) for r in pond_rings])).area
    bridge_gap = bridge_water.difference(water).area
    opera = json.load(open(GAME + r"\sydney\landmarks\opera_house.json", encoding="utf-8"))
    podium = Polygon([(p[0], p[1]) for p in opera["podiumRing"]])
    podium_overlap = water.intersection(podium).area

    def cover(x, z):
        return water.contains(Polygon([(x, z), (x + 0.01, z), (x, z + 0.01)]).centroid)

    checks = {
        "SydneyCove": cover(500.0, -1780.0),
        "CircularQuay": cover(340.0, -1790.0),
        "FarmCove": cover(800.0, -1730.0),
        "WoolloomoolooBay": cover(1150.0, -1500.0),
        "DarlingHarbour": cover(-650.0, -300.0),
        "BlackwattleBay": cover(-1150.0, 0.0),
        "BlackwattleTip": cover(-1150.0, 280.0),
        "GlebeLandDry": not cover(-1350.0, 0.0),
        "PyrmontLandDry": not cover(-950.0, -150.0),
        "UnderBridgeMidspan": cover(250.0, -2300.0),
        "EastHarbour": cover(1200.0, -2200.0),
        "OperaPodiumDry": not cover(658.7, -1763.8),
        "ForecourtDry": not cover(632.1, -1650.9),
        "QuaySpawnDry": not cover(219.9, -1755.7),
        "BotanicGardenDry": not cover(700.0, -1420.0),
        "TownHallDry": not cover(-42.8, -466.5),
    }

    data = {
        "format": "splooge-harbour-water",
        "formatVersion": 1,
        "units": "meters",
        "scope": {"minX": SCOPE_MIN_X, "maxX": SCOPE_MAX_X,
                  "minZ": SCOPE_MIN_Z, "maxZ": SCOPE_MAX_Z},
        "waterY": WATER_Y,
        "islandY": ISLAND_Y,
        "waterRings": water_rings,
        "islandRings": island_rings,
        "pondRings": pond_rings,
        "landRings": land_rings,
        "provenance": {
            "source": "OpenStreetMap via sydney-osm-world normalized waterways",
            "license": "ODbL 1.0 (OSM parts); authored parts original",
            "features": HARBOUR_SOURCES,
            "authored": {
                "blackwattleBay": "absent from all pipeline water features; approximated "
                                  "from the real bay outline, mouth overlapped onto the "
                                  "mapped Johnstons Bay arm",
            },
            "pipelineFile": "data/normalized/waterways.json",
            "projection": "equirectangular about -33.873/151.208; 92459.893 m/deg lon, 111019.656 m/deg lat; north = -Z",
            "clippedAgainst": ["scope box", "harbour_bridge.json landRings"],
            "stageAWater": "superseded except pondRings (non-harbour ponds preserved)",
        },
        "stats": {
            "waterRings": len(water_rings),
            "waterAreaM2": round(water_area, 1),
            "waterVertices": sum(len(r) for r in water_rings),
            "islandRings": len(island_rings),
            "pondRings": len(pond_rings),
            "pondAreaM2": round(pond_area, 1),
            "landRings": len(land_rings),
            "landAreaM2": round(land_area, 1),
            "collisionRings": len(water_rings) + len(island_rings) + len(pond_rings),
            "buildingOverlapM2": round(building_overlap, 2),
            "parkOverlapM2": round(park_overlap, 2),
            "podiumOverlapM2": round(podium_overlap, 2),
            "oldStageAWaterUncoveredM2": round(old_uncovered, 1),
            "bridgeWaterGapM2": round(bridge_gap, 1),
            "coverageChecks": checks,
        },
    }
    with open(OUT, "w", encoding="utf-8") as fh:
        json.dump(data, fh, separators=(",", ":"))
    print("wrote", OUT)
    print(json.dumps(data["stats"], indent=1))


if __name__ == "__main__":
    main()
