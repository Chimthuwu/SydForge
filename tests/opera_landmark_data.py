"""Derive the authored Opera House landmark data from the pinned OSM extract.

Reads .runtime/phase3/reference.json (already retrieved by opera_reference.py)
and writes sydney/landmarks/opera_house.json. Deterministic; no network access;
never touches the Stage A export or the source .osm file.
"""
import json, math
from pathlib import Path
from shapely.geometry import Polygon, Point

ROOT = Path(__file__).resolve().parents[1]
LENGTH_SCALE = 1.25
WIDTH_SCALE = 2.0
ref = json.loads((ROOT / '.runtime/phase3/reference.json').read_text(encoding='utf-8'))
by_id = {}
for item in ref:
    by_id.setdefault(item['id'], []).append(item)

podium = by_id['relation/9596872'][0]
ring = [[round(x, 3), round(z, 3)] for x, z in podium['ring'][:-1]]
poly = Polygon([tuple(p) for p in ring])
centroid = (poly.centroid.x, poly.centroid.y)

# Podium long axis comes from the 169.5 m rectangle side, not the diagonal.
rect = list(poly.minimum_rotated_rectangle.exterior.coords)[:4]
edges = []
for i in range(4):
    a, b = rect[i], rect[(i + 1) % 4]
    edges.append((math.dist(a, b), a, b))
edges.sort(key=lambda e: -e[0])
long_edge = edges[0]
ax = (long_edge[2][0] - long_edge[1][0], long_edge[2][1] - long_edge[1][1])
length = math.hypot(*ax)
ax = (ax[0] / length, ax[1] / length)
if ax[1] > 0:  # force north (-Z)
    ax = (-ax[0], -ax[1])
perp = (-ax[1], ax[0])  # east side

def local(p):
    dx, dz = p[0] - centroid[0], p[1] - centroid[1]
    return (dx * ax[0] + dz * ax[1], dx * perp[0] + dz * perp[1])

def obb(points):
    p = Polygon(points)
    r = list(p.minimum_rotated_rectangle.exterior.coords)[:4]
    cand = []
    for i in range(4):
        a, b = r[i], r[(i + 1) % 4]
        cand.append((math.dist(a, b), a, b))
    cand.sort(key=lambda e: -e[0])
    l_len, a, b = cand[0]
    d = ((b[0] - a[0]) / l_len, (b[1] - a[1]) / l_len)
    if d[0] * ax[0] + d[1] * ax[1] < 0:  # long axis points north
        d = (-d[0], -d[1])
    n = (-d[1], d[0])
    # Measure the real width from the footprint, not the rotated rectangle's
    # second side (which is unreliable for near-square contours).
    t = [(x * d[0] + y * d[1]) for x, y in points]
    s = [(x * n[0] + y * n[1]) for x, y in points]
    t0, t1, s0, s1 = min(t), max(t), min(s), max(s)
    length = t1 - t0
    width = s1 - s0
    ct = (t0 + t1) * 0.5
    cs = (s0 + s1) * 0.5
    centre = (d[0] * ct + n[0] * cs, d[1] * ct + n[1] * cs)
    return {
        'centre': [round(centre[0], 3), round(centre[1], 3)],
        'axis': [round(d[0], 5), round(d[1], 5)],
        # The relation contours are drawn above the shell base, so the authored
        # sail plan is the published shell size (about 60 x 40 m for the largest
        # shell) rather than the narrower contour extent.
        'contourLengthM': round(length, 2),
        'contourWidthM': round(width, 2),
        'lengthM': round(length * LENGTH_SCALE, 2),
        'widthM': round(width * WIDTH_SCALE, 2),
        'areaM2': round(p.area, 1),
    }

# Layer 4 A and layer 5 A are the two shell rows along the podium length.
# Layer 3 relations are lower, narrower contours of the same shells and are not
# separate structures, so they are not used as extra shells.
SHELL_SOURCES = [
    ('relation/9596878', 'layer 5 A roof'),
    ('relation/9677509', 'layer 4 A roof'),
]
shells = []
for relation_id, layer in SHELL_SOURCES:
    for index, item in enumerate(by_id[relation_id]):
        ring_c = [[round(x, 3), round(z, 3)] for x, z in item['ring'][:-1]]
        p = Polygon([tuple(q) for q in ring_c])
        if p.area < 150.0:
            continue  # access strip, not a shell
        u, v = local((p.centroid.x, p.centroid.y))
        group = 'opera-theatre' if v > 8.0 else 'concert-hall'
        area = p.area
        if group == 'concert-hall':
            apex = 67.0 if area > 600 else (60.5 if area > 300 else 55.0)
        else:
            apex = 58.0 if area > 300 else 52.0
        shells.append({
            'id': '%s/%d' % (relation_id, index),
            'layer': layer,
            'group': group,
            'localUV': [round(u, 2), round(v, 2)],
            'apexAboveGroundM': apex,
            'ring': ring_c,
            'obb': obb([tuple(q) for q in ring_c]),
        })

# Bennelong Restaurant: the two south-west shells of relation/9677501.
restaurant = []
for index, item in enumerate(by_id['relation/9677501']):
    ring_c = [[round(x, 3), round(z, 3)] for x, z in item['ring'][:-1]]
    p = Polygon([tuple(q) for q in ring_c])
    if p.area < 100:
        continue
    restaurant.append({
        'id': 'relation/9677501/%d' % index,
        'layer': 'layer 4 c roof',
        'group': 'restaurant',
        'localUV': [round(v, 2) for v in local((p.centroid.x, p.centroid.y))],
        'apexAboveGroundM': 26.0,
        'ring': ring_c,
        'obb': obb([tuple(q) for q in ring_c]),
    })

shells.extend(restaurant)

# Which existing Stage A generic buildings would sit inside/overlap the podium
# and therefore in the landmark footprint? The export is expected to have none,
# but the check is recorded rather than assumed.
world = json.loads((ROOT / 'sydney/world/stage_a/world.json').read_text())
overlapping = []
for row in world['buildings']:
    bp = Polygon([tuple(q) for q in row['ring']])
    if bp.intersects(poly):
        overlapping.append(str(row.get('id')))
road_hits = 0
road_names = []
for road in world.get('roads', []):
    for point in road.get('points', []):
        if poly.covers(Point(float(point[0]), float(point[1]))):
            road_hits += 1
            road_names.append(road.get('name') or road.get('id'))
            break
print('road vertices inside podium:', road_names)

out = {
    'format': 'splooge-authored-landmark',
    'formatVersion': 1,
    'landmark': 'sydney-opera-house',
    'units': 'metres, Y up, X east, Z south',
    'provenance': {
        'derivation': 'tests/opera_landmark_data.py from .runtime/phase3/reference.json',
        'osmObjects': {
            'relation/9596872': 'Sydney Opera House building outline (podium / ground footprint)',
            'relation/9596878': 'layer 5 A roof - shell plan contours, northern row',
            'relation/9677509': 'layer 4 A roof - shell plan contours, southern row',
            'relation/9677501': 'layer 4 c roof - Bennelong Restaurant shells (south-west)',
        'planScale': 'Shell plan scaled from the OSM contour to the published shell size (x%.2f length, x%.2f width) because the contours are cut above the base.' % (LENGTH_SCALE, WIDTH_SCALE),
            'relation/9596873': 'layer 3 A roof - lower contour of the same shells; not modelled separately',
            'relation/9596874, 9596876, 9596880': 'maintenance access surfaces; not modelled',
            'relation/9596881': 'glass roof over the western foyer; represented by glazed walls',
        },
        'licence': 'OpenStreetMap contributors, ODbL 1.0',
        'retrieved': '2026-11-19',
    },
    'podiumRing': ring,
    'podiumAreaM2': round(poly.area, 1),
    'centreXZ': [round(centroid[0], 3), round(centroid[1], 3)],
    'axisXZ': [round(ax[0], 6), round(ax[1], 6)],
    'podiumLongAxisM': round(length, 2),
    'shells': shells,
    'overlapBuildingIds': overlapping,
    'roadVerticesInsidePodium': road_hits,
}
dest = ROOT / 'sydney/landmarks/opera_house.json'
dest.write_text(json.dumps(out, indent=1))
print('podium area %.0f m2, long axis %.1f m, axis %s' % (poly.area, length, ax))
print('shells:', len(shells))
for s in shells:
    print('  %-34s %-14s uv=(%6.1f,%6.1f) L=%.1f W=%.1f area=%6.0f apex=%.0f' % (
        s['id'], s['group'], s['localUV'][0], s['localUV'][1],
        s['obb']['lengthM'], s['obb']['widthM'], s['obb']['areaM2'], s['apexAboveGroundM']))
print('overlapping Stage A buildings:', overlapping)
print('roads with a vertex inside the podium:', road_hits)
