"""Derive a bounded landmark reference from pinned OSM, retaining provenance."""
import json, math
from pathlib import Path
from shapely.geometry import Polygon, LineString, box
from shapely.ops import polygonize, unary_union
ROOT=Path(__file__).resolve().parents[1]
src=json.loads((ROOT/'.runtime/phase5/reference.json').read_text())
features={f['id']:f for f in src['features']}
cs=src['coordinateSystem']
def project(p):
    return [(p['lon']-cs['origin']['lon'])*cs['metersPerDegreeLongitude'], -(p['lat']-cs['origin']['lat'])*cs['metersPerDegreeLatitude']]
def feature(i): return features['way/'+str(i)]
pylons=[feature(i) for i in range(142518160,142518164)]
centers=[list(Polygon(p['points']).centroid.coords)[0] for p in pylons]
south=[(centers[0][i]+centers[1][i])/2 for i in range(2)]
north=[(centers[2][i]+centers[3][i])/2 for i in range(2)]
length=math.dist(south,north); axis=[(north[i]-south[i])/length for i in range(2)]
mid=[(south[i]+north[i])/2 for i in range(2)]
bearings=[[mid[i]+sign*251.5*axis[i] for i in range(2)] for sign in [-1,1]]
raw=Path('Z:/GITHUB/_EXPERIMENTS/Sydney/sydney-osm-world/data/raw/overpass-water-areas.json')
water_src=json.loads(raw.read_text())
relation=next(e for e in water_src['payload']['elements'] if e['id']==1252425)
lines=[LineString([project(p) for p in m['geometry']]) for m in relation['members'] if m.get('geometry') and m.get('role')=='outer']
polys=list(polygonize(unary_union(lines)))
print('water polygons',len(polys))
clip=box(-200,-3300,780,-1887.3)
water=unary_union(polys).intersection(clip)
land=clip.difference(water)
def rings(g):
    return [list(p.exterior.coords) for p in (list(g.geoms) if hasattr(g,'geoms') else [g]) if isinstance(p,Polygon)]
print('water area',water.area,'land',land.area)
# Main bridge centre from two pylon pairs; 503 m pin spacing from official reference.
# Approach road follows actual OSM northbound centreline, shifted 4 m east to
# the corridor centre shared with the southbound carriageway.
road=feature(171978153)
east=[-axis[1],axis[0]]
road_points=[[p[0]+4*east[0],p[1]+4*east[1]] for p in road['points']]
# Southern tie-in follows source carriageway all the way to the existing flat
# road at z=-1550. Vertical profile is authored for the flat Stage A terrain.
south_extra=[]
for i in [1530533294,1530532875,1530532878]:
    south_extra += feature(i)['points'][:-1]
road_points=[[p[0]+4*east[0],p[1]+4*east[1]] for p in south_extra]+road_points
road_points += [[p[0]+4*east[0],p[1]+4*east[1]] for p in feature(1530530701)['points'][1:]]
road_points += [[p[0]+4*east[0],p[1]+4*east[1]] for p in feature(1530530700)['points'][1:]]
for i in [1530531824,1530531818,388949145]:
    road_points += [[p[0]+4*east[0],p[1]+4*east[1]] for p in feature(i)['points'][1:]]
road_points += [[p[0]+4*east[0],p[1]+4*east[1]] for p in feature(11900573)['points'][1:3]]
local_ids=[29174822,1484195095,1484195094,279682336,245334220,51365502,172577516,1465994632,1465994633,1011384908,1011384909,173190541,23212436,1986109]
local_streets=[feature(i) for i in local_ids]
selected=[*pylons,road,feature(388949144),feature(142518149),feature(1579152742),feature(142518151),feature(142518159),feature(1986109)]
selected += [feature(i) for i in [1530533294,1530532875,1530532878,1530530701,1530530700,1530531824,1530531818,388949145,11900573]]
def unproject(p):
    return {'lon':cs['origin']['lon']+p[0]/cs['metersPerDegreeLongitude'],'lat':cs['origin']['lat']-p[1]/cs['metersPerDegreeLatitude']}
out=dict(source=src['source'],license=src['license'],retrieved=src['retrieved'],coordinateSystem=cs,
    sourceFeatures=selected,pylonCenters=centers,axis=axis,centre=mid,bearings=bearings,
    roadPoints=road_points,localStreets=local_streets,landRings=rings(land),waterRings=rings(water),
    waterSource='OSM relation/1252425, existing overpass-water-areas.json',
    measured={'pylonPairSpacingM':length},
    bearingLonLat=[unproject(p) for p in bearings],pylonLonLat=[unproject(p) for p in centers],
    confidence={'OSM plan':'high for mapped alignment; not a survey','official dimensions':'high','bearing positions':'medium: official span centred on OSM pylon pairs','elevations and sections':'authored approximation','approach gradients':'gameplay adaptation to flat terrain','local street widths':'12 m approximation'},
    official={'spanM':503,'widthM':49,'summitM':134,'pylonTopM':89,'clearanceM':49,'overallLengthM':1149,'archRibsSpacingM':30,'panels':28},
    assumptions={'deckTopM':52,'bearingM':12,'archLowerCrownM':116,'pylonFootprints':'OSM top outlines extended to base with authored taper','approachElevation':'Graded to flat Stage A at south and bounded Milsons Point landing; not surveyed','walkEle141':'Rejected OSM ele=141 as inconsistent with official deck clearance'},
    sources=['https://www.transport.nsw.gov.au/system/files/media/documents/2023/harbour-bridge-history.pdf','https://www.dcceew.gov.au/sites/default/files/documents/sydney-harbour-bridge.pdf'])
(ROOT/'sydney/landmarks/harbour_bridge.json').write_text(json.dumps(out,indent=2)+'\n')
print('axis',axis,'centre',mid,'bearings',bearings,'pylons',centers,'road ends',road_points[0],road_points[-1])
