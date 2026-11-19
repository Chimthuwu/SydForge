"""Inspect a tightly scoped OSM reference; never edits the Stage A export."""
import json
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path
from shapely.geometry import Polygon, Point, LineString
from shapely.ops import polygonize, unary_union

ROOT = Path(__file__).resolve().parents[1]
TEMP = ROOT / '.runtime/phase3'
TEMP.mkdir(parents=True, exist_ok=True)
path = TEMP / 'bennelong.osm'
if not path.exists():
    url = 'https://api.openstreetmap.org/api/0.6/map?bbox=151.2135,-33.8585,151.2168,-33.8550'
    request = urllib.request.Request(url, headers={'User-Agent': 'Splooge-landmark-reference/1.0'})
    path.write_bytes(urllib.request.urlopen(request, timeout=45).read())
tree = ET.parse(path).getroot()
nodes = {n.attrib['id']: [float(n.attrib['lon']), float(n.attrib['lat'])] for n in tree.findall('node')}
world = json.loads((ROOT / 'sydney/world/stage_a/world.json').read_text())
cs = world['coordinateSystem']
def project(p):
    return [(p[0]-cs['origin']['lon'])*cs['metersPerDegreeLongitude'], -(p[1]-cs['origin']['lat'])*cs['metersPerDegreeLatitude']]

features = []
ways = {w.attrib['id']: w for w in tree.findall('way')}
for relation in tree.findall('relation'):
    tags = {t.attrib['k']: t.attrib['v'] for t in relation.findall('tag')}
    if not tags.get('building') and not tags.get('building:part'):
        continue
    lines = []
    members = []
    for member in relation.findall('member'):
        if member.attrib['type'] != 'way' or member.attrib.get('role') == 'inner':
            continue
        way = ways.get(member.attrib['ref'])
        if way is None:
            print('MISSING member', member.attrib)
            continue
        points = [nodes[n.attrib['ref']] for n in way.findall('nd')]
        lines.append(LineString(points))
        members.append('way/'+way.attrib['id'])
    polygons = list(polygonize(lines))
    for polygon in polygons:
        coords = list(polygon.exterior.coords)
        item = {'id':'relation/'+relation.attrib['id'], 'version':relation.attrib.get('version'), 'tags':tags, 'memberIds':members, 'lonlat':coords, 'ring':[project(p) for p in coords]}
        features.append(item)
        p = Polygon(item['ring'])
        print(item['id'], tags.get('name',tags.get('comment')), 'points',len(coords),'center',tuple(p.centroid.coords)[0], 'bounds',p.bounds)
for way in tree.findall('way'):
    tags = {t.attrib['k']: t.attrib['v'] for t in way.findall('tag')}
    if not any(k in tags for k in ('building','building:part','natural','highway','man_made')):
        continue
    coordinates = [nodes[n.attrib['ref']] for n in way.findall('nd') if n.attrib['ref'] in nodes]
    item = {'id': 'way/'+way.attrib['id'], 'version': way.attrib.get('version'), 'tags': tags, 'lonlat': coordinates, 'ring': [project(p) for p in coordinates]}
    features.append(item)
    if tags.get('building') or tags.get('building:part') or tags.get('natural') == 'coastline':
        print(item['id'], tags, 'points', len(coordinates))
        if len(coordinates)>3 and coordinates[0] == coordinates[-1]:
            polygon = Polygon(item['ring'])
            print('  center', tuple(polygon.centroid.coords)[0], 'bounds', polygon.bounds)
(TEMP/'reference.json').write_text(json.dumps(features, indent=2))
print('Stage A Opera rows:', [r['id'] for r in world['buildings'] if 'opera' in (r.get('name') or '').lower()])
print('Stage A nearby buildings:', len([r for r in world['buildings'] if Polygon(r['ring']).centroid.distance(Point(675,-1798)) < 200]))
print('Nearby road names:', sorted({r.get('name') or '' for r in world['roads'] if any((x-675)**2+(z+1798)**2 < 300**2 for x,z in r['points'])}))
