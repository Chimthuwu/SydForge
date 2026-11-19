"""Read-only clearance diagnostic; distinguishes inherited OSM overlap from ornament."""
import json
import sys
from pathlib import Path
from shapely.geometry import Polygon, LineString
from shapely.ops import unary_union

root = Path(__file__).resolve().parents[1]
world = json.loads((root / 'sydney/world/stage_a/world.json').read_text())
pilot = json.loads((root / 'tests/architecture_pilot.json').read_text())
roads = unary_union([
    LineString(r['points']).buffer(r['widthM'] / 2, cap_style=2, join_style=2)
    for r in world['roads'] if not r.get('tunnel') and len(r['points']) >= 2
])
footpaths = unary_union([
    LineString(r['points']).buffer(r.get('widthM', 2) / 2, cap_style=2, join_style=2)
    for r in world['footpaths'] if len(r['points']) >= 2
])
report = []
walk_and_road = roads.union(footpaths)
if '--candidates' in sys.argv:
    spawn = world['spawn']['player']
    from shapely.geometry import Point
    origin = Point(spawn['x'], spawn['z'])
    candidates = []
    for row in world['buildings']:
        p = Polygon(row['ring'])
        edges = [LineString([a, b]).length for a, b in zip(row['ring'], row['ring'][1:] + row['ring'][:1])]
        if p.area < 20 or not 6 <= row['heightM'] <= 180 or min(edges) < 2.5 or p.convex_hull.area - p.area > .001:
            continue
        distance = p.centroid.distance(origin)
        if distance < 260 and p.buffer(.9, join_style=2).intersection(walk_and_road).area < .001:
            candidates.append({'id': row['id'], 'height': row['heightM'], 'distance': round(distance, 1), 'name': row.get('name')})
    print(json.dumps(sorted(candidates, key=lambda r:r['distance']), indent=2))
    sys.exit()
for row in pilot:
    footprint = Polygon(row['ring'])
    # Conservative envelope, not a claim that ornament fills this entire band.
    ornament = footprint.buffer(.9, join_style=2).difference(footprint)
    report.append({
        'id': row['id'],
        'existing_road_overlap_m2': round(footprint.intersection(roads).area, 3),
        'existing_footpath_overlap_m2': round(footprint.intersection(footpaths).area, 3),
        'ornament_envelope_road_overlap_m2': round(ornament.intersection(roads).area, 3),
        'ornament_envelope_footpath_overlap_m2': round(ornament.intersection(footpaths).area, 3),
    })
print(json.dumps(report, indent=2))
checks, failures = 1, int(len(pilot) != 7)
for row in report:
    for key, value in row.items():
        if key != 'id':
            checks += 1
            if value > 0:
                failures += 1
                print('FAIL:', row['id'], key, value)
print(f'RESULT: {checks} checks, {failures} failures')
sys.exit(1 if failures else 0)
