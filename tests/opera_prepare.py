"""Pin the retrieved local OSM geometry; derive placement from the source polygon."""
import json, math
from pathlib import Path
from shapely.geometry import Polygon
from shapely.ops import unary_union
from PIL import Image, ImageDraw
ROOT=Path(__file__).resolve().parents[1]
features=json.loads((ROOT/'.runtime/phase3/reference.json').read_text())
main=next(r for r in features if r['id']=='relation/9596872')
p=Polygon(main['ring'])
print('OSM main',p.centroid.wkt,'area',p.area,'oriented box',list(p.minimum_rotated_rectangle.exterior.coords))
image=Image.new('RGB',(900,1000),'#e8e2d5'); draw=ImageDraw.Draw(image)
def pixels(ring): return [((x-550)*4,(z+1890)*4) for x,z in ring]
draw.polygon(pixels(main['ring']),fill='#b9aa91',outline='black')
groups={}
for f in features:
    if f['id'].startswith('relation/') and f['tags'].get('building:part'):
        groups.setdefault(f['id'],[]).append(Polygon(f['ring']))
for index,(key,polygons) in enumerate(groups.items()):
    shape=unary_union(polygons)
    print(key,'union',shape.geom_type,'bounds',shape.bounds,'area',shape.area)
    for poly in ([shape] if shape.geom_type=='Polygon' else shape.geoms):
        draw.polygon(pixels(poly.exterior.coords),fill=['#f7f7f2','#b6c8d1','#ddddcd','#90aab8','#fafaf8'][index%5],outline='#334455')
image.save(ROOT/'.runtime/phase3/osm-roof-plan.png')
dest=ROOT/'sydney/landmarks'; dest.mkdir(exist_ok=True)
result={'id':'landmark/sydney-opera-house','source':'https://www.openstreetmap.org/relation/9596872', 'licence':'ODbL 1.0; OpenStreetMap contributors', 'retrieved':'2026-11-19','sourceGeometry':main,'roofReferences':[f for f in features if f['id'].startswith('relation/') and f['tags'].get('building:part')], 'centerLonLat':list(Polygon(main['lonlat']).centroid.coords)[0]}
(dest/'opera_house_reference.json').write_text(json.dumps(result,indent=2))
