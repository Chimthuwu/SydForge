"""Pin bridge OSM geometry in the existing projection, without changing Stage A."""
import json
import xml.etree.ElementTree as ET
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
world = json.loads((ROOT/'sydney/world/stage_a/world.json').read_text())
cs = world['coordinateSystem']
raw = ROOT/'.runtime/phase5/bridge.osm'
if not raw.exists():
    raw.parent.mkdir(parents=True, exist_ok=True)
    request = urllib.request.Request('https://api.openstreetmap.org/api/0.6/map?bbox=151.205,-33.862,151.215,-33.841', headers={'User-Agent':'Splooge-bridge-reference/1.0'})
    raw.write_bytes(urllib.request.urlopen(request, timeout=90).read())
tree = ET.parse(raw).getroot()
nodes = {n.attrib['id']: [float(n.attrib['lon']), float(n.attrib['lat'])] for n in tree.findall('node')}
def project(p):
    return [(p[0]-cs['origin']['lon'])*cs['metersPerDegreeLongitude'], -(p[1]-cs['origin']['lat'])*cs['metersPerDegreeLatitude']]
features = []
for w in tree.findall('way'):
    tags = {t.attrib['k']: t.attrib['v'] for t in w.findall('tag')}
    coords = [nodes[n.attrib['ref']] for n in w.findall('nd') if n.attrib['ref'] in nodes]
    if not coords:
        continue
    if any(k in tags for k in ('highway','railway','building','man_made','natural','building:part')):
        features.append(dict(id='way/'+w.attrib['id'], tags=tags, lonlat=coords, points=[project(p) for p in coords]))
out = {'source':'https://api.openstreetmap.org/api/0.6/map?bbox=151.205,-33.862,151.215,-33.841', 'license':'OpenStreetMap contributors, ODbL 1.0', 'retrieved':'2026-11-19', 'coordinateSystem':cs, 'features':features}
(ROOT/'.runtime/phase5/reference.json').write_text(json.dumps(out))
for f in features:
    t=f['tags']
    if t.get('man_made')=='bridge' or 'pylon' in str(t).lower() or (t.get('bridge') and (t.get('highway')=='footway' or t.get('railway')=='rail')):
        p=f['points']; print(f['id'],t, 'ends',p[0],p[-1])
