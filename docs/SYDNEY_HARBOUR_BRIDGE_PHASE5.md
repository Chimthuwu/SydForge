# Sydney Harbour Bridge — Phase 5

Implemented in the existing dirty working tree on 2026-11-19. No commit or push.
Open `res://sydney/sydney_bridge_test.tscn` and press **F6**. **N** switches shores
while on foot. F5 project startup remains District Zero.

## Starting state

Phase 3 supplied the Opera House and authored architecture. Phase 4 supplied
shoreline barriers, stair traversal and Circular Quay/Opera House playtest scenes.
Stage A contained flat road ribbons and buildings but no elevated Harbour Bridge.
Its bounds were X −508.5…785.9, Z −1887.3…666.1: the crossing and North Shore
were outside its northern edge. Existing changes in both repositories were
preserved; the Stage A JSON and pipeline were not edited.

## Geographic evidence

Sources used for this phase:

- [Transport for NSW, bridge history and dimensions](https://www.transport.nsw.gov.au/system/files/media/documents/2023/harbour-bridge-history.pdf).
- [Australian Heritage Database assessment](https://www.dcceew.gov.au/sites/default/files/documents/sydney-harbour-bridge.pdf), especially pages 2 and 4–5.
- [Bounded OSM API extract](https://api.openstreetmap.org/api/0.6/map?bbox=151.205,-33.862,151.215,-33.841), retrieved 2026-11-19, cached in `.runtime/phase5/bridge.osm`.
- Existing Sydney pipeline `data/raw/overpass-water-areas.json`, relation
  [1252425](https://www.openstreetmap.org/relation/1252425), reused for the shoreline.

OSM attribution: © OpenStreetMap contributors, ODbL 1.0. Selected original tags,
lon/lat vertices, projected points, source URLs, confidence levels and modelling
assumptions are retained in `sydney/landmarks/harbour_bridge.json`.
`tests/bridge_reference.py` pins the extract; `tests/bridge_prepare.py` derives the
landmark data using Shapely. Rebuilding the game requires neither Python nor a
network connection.

| OSM elements | Use |
|---|---|
| ways 142518160, 142518161, 142518162, 142518163 | SE, SW, NE, NW pylon upper footprints; polygon centroids fix placement |
| ways 171978153, 388949144 | Bradfield carriageways and alignment; first is the route source, shifted 4 m east toward corridor centre |
| ways 1530533294, 1530532875, 1530532878 | Southern continuation into the existing Stage A Bradfield roads |
| ways 1530530701, 1530530700, 1530531824, 1530531818, 388949145, 11900573 | Northern continuation toward the Lavender Street exit |
| ways 142518149, 1579152742 | Eastern Cahill Walk reference; rendered walkway follows the road offset |
| ways 142518151, 142518159 | Western railway reference and 1,435 mm gauge |
| ways 29174822, 1484195095, 1484195094, 279682336, 245334220 | Lavender exit/local connection |
| ways 51365502, 172577516, 1465994632, 1986109 | Alfred Street South connection |
| ways 1465994633, 1011384908, 1011384909, 173190541, 23212436 | Small Fitzroy Street connection area |

The OSM pedestrian way's `ele=141` is rejected: it conflicts with the official
clearance and bridge geometry. Pylon `min_height=59` describes an upper part,
not a tower floating 59 m above the shore. Neither tag is used blindly.

### Projection and placement

Unchanged origin: latitude −33.8730, longitude 151.2080. X east, Y up, Z south,
one unit per metre. Conversion uses Stage A's exact factors:

`X = (longitude − 151.2080) × 92459.893`

`Z = −(latitude + 33.8730) × 111019.656`

The northward bridge axis is **(0.461499, 0, −0.887141)**, approximately 27.5°
east of north. Centre is **(247.303, 0, −2299.566)**. The two pylon-pair centres
are approximately 565.4 m apart. Official 503 m bearing spacing is centred
between those pairs; bearing locations are derived, not surveyed OSM pins.

| Location | Latitude, longitude | Game X, Z (m) |
|---|---|---|
| Southern bearing centre | −33.85429655, 151.20941939 | 131.236, −2076.450 |
| Northern bearing centre | −33.85027716, 151.21193003 | 363.370, −2522.682 |
| SE pylon centre | −33.85463388, 151.20945731 | 134.743, −2039.000 |
| SW pylon centre | −33.85446043, 151.20906840 | 98.784, −2058.257 |
| NE pylon centre | −33.85011408, 151.21228475 | 396.167, −2540.786 |
| NW pylon centre | −33.84993902, 151.21188838 | 359.519, −2560.222 |
| Southern road tie-in | retained in source geometry | −141.540, −1549.432 |
| Northern road tie-in | retained in source geometry | 318.217, −3175.192 |

Confidence: official dimensions high; OSM alignment high for mapping purposes;
derived bearing positions medium; vertical approach profiles, member sections,
pylon detailing and cross-section allocation are authored approximations.

## Dimensions and construction

Published references give a **503 m** span, **49 m** deck width, **134 m** summit,
**89 m** pylons, **49 m** shipping clearance and **1,149 m** including approach
spans. The heritage assessment describes two **28-panel** trusses, **30 m** apart,
with **18 m** crown depth and **57 m** end depth, plus braced approach spans.

The model uses those principal dimensions. Its lower chord is a fitted parabola:
`12 + 104 × (1 − (s / 251.5)²)`. The upper chord adds
`18 + 39 × (s / 251.5)²`. Thus the lower crown is 116 m, upper crown centreline
134 m and bearing level 12 m. These curves and the 104 m lower-chord rise are
authored fits, not digitised fabrication drawings. Member thickness extends
slightly beyond chord centreline elevations.

Both ribs have substantial box chords with flange bands, alternating diagonal
webs, vertical webs and lateral X-bracing. Hangers connect the high lower chord
to cross-girders below the road. Bracing below vehicle clearance is omitted from
the road envelope. Approach spans have paired parallel chords and diagonal webs
on granite-coloured supports. There is no per-frame bridge work.

Deck top is **52 m**, with structural soffit at **49 m** across the harbour.
This is an explicit elevation assumption consistent with the shipping clearance,
not a surveyed deck profile. The 49 m cross-section contains a 24 m road,
western rail corridor and cycle strip, eastern pedestrian strip, separators and
structural clearances. Eight 3 m lanes have a fixed four-plus-four keep-left
arrangement and arrows. Real lane reversals/bus allocation are not simulated.
The pedestrian surface is 0.12 m above the roadway and approximately 6.5 m wide;
this generous clearance and the lateral allocation are gameplay approximations.

Four pylons stand at the mapped centres. Stepped shafts, cornices, observation
window strips and open deck-level portals provide their silhouette. Bases extend
to the local ground. Shaft sections, masonry courses and portals are authored;
the OSM upper outlines establish location/orientation rather than every stone.

Two decorative railway tracks sit west of the roadway, with 1.435 m rail gauge,
sleepers and simple catenary posts. They do not intrude into the playable road or
walkway. No trains, rail simulation, interiors or climbable arch attraction.

## Shore connections and collision

The road follows the mapped Bradfield alignment, resampled at at most 8 m.
Cubic height transitions grade each approach into the existing flat terrain.
These ramps deliberately differ from Sydney's actual terrain and interchange
levels. The playable route includes extra ground tie-ins beyond the published
1,149 m structure length; it must not be described as a surveyed 1,149 m model.

The southern route joins existing Bradfield road geometry in The Rocks. The
eastern pedestrian strip starts at ground level beside it and continues through
the pylon portals. The northern route curves along the mapped approach to the
Lavender exit; selected source street segments provide access toward Alfred
Street and Fitzroy Street in Milsons Point. Local streets use an approximate
12 m width on flat land. No North Shore buildings or suburb generator were added.

The added site is bounded to **X −200…780, Z −3300…−1887.3**. Land and water are
clipped from the existing OSM harbour source, leaving Stage A unchanged. New
shoreline collision follows those water rings; artificial joins at Stage A's
northern seam are not walled off. The original 2.4 m shoreline barrier remains
well below the elevated crossing, so it does not block either route.

One static body holds a batched concave shape for deck sides, approaches,
walkway, barriers, pylons and land, plus **one convex slab** for the long central
road. Decorative steel is excluded from collision. The slab resolves an observed
box-car contact against a coplanar triangle edge at midspan; no vehicle/controller
patch was needed. Shared ribbon cross-sections avoid geometric gaps. Simplified
collision does not reproduce every brace or railing picket.

## Verification

The focused suite is `tests/harbour_bridge_test.gd`. It loads the real F6 scene,
checks geographic anchors, arch profile, pylon count, finite mesh data, unit
normals, winding, zero degenerate triangles and deterministic steel output. It
ray-checks all 244 road and walkway sections and ground beyond both ends. It
then drives the real player with input for the entire northbound and southbound
walk, and the existing ArcadeCar across the full roadway. The test driver sets
heading toward successive waypoints; throttle, gravity and collision remain the
existing vehicle implementation. It also continues onto the local exit.

Regression suites actually executed during Phase 5:

| Suite | Checks | Failures |
|---|---:|---:|
| Sydney geometry | 107 | 0 |
| Sydney scene | 23 | 0 |
| Opera House | 57 | 0 |
| Architecture | 80 | 0 |
| Architecture clearance (Python) | 29 | 0 |
| Water and stair traversal / Sydney physics | 31 | 0 |
| Existing Sydney playtest, windowed | 22 | 0 |
| District Zero integration | 63 | **2 known** |

The two preserved District Zero failures are **`melee damages nearby enemy`** and
**`enemy defeat grants reputation`**. They are not reported as passes. Headless
sandbox runs also print a Windows certificate-store error; several pre-existing
scene suites print eight leaked-object warnings at shutdown. Windowed bridge
captures exit successfully without script errors. These diagnostics are distinct
from assertion results.

Commands (PowerShell, from the project):

```powershell
$env:APPDATA = Join-Path $PWD '.runtime'
& './Godot_v4.7.2-stable_win64_console.exe' --headless --fixed-fps 60 --path . --script res://tests/harbour_bridge_test.gd --log-file tests/harbour_bridge_test.log
& './Godot_v4.7.2-stable_win64_console.exe' --path . --script res://tests/harbour_bridge_visual.gd --log-file tests/harbour_bridge_visual.log
```

## Actual Godot captures

All eight were generated in windowed **Godot 4.7.2**, OpenGL Compatibility on
AMD Radeon RX 6600, and opened for inspection. These are engine captures, not
Python previews. Initial captures exposed omitted batch indices, a blocked Opera
viewpoint and a mismatched water seam; those were corrected and recaptured.

| Capture | Inspection |
|---|---|
| [Aerial](../tests/bridge_aerial.png) | Full alignment, both shores, bounded extension and continuous approaches |
| [Harbour](../tests/bridge_harbour.png) | Deep paired steel arch profile, hangers, four pylons and approach spans |
| [Opera House viewpoint](../tests/bridge_opera.png) | Full arch visible from the western harbour-side edge of Bennelong Point |
| [Road deck](../tests/bridge_road.png) | Marked lanes, overhead bracing and unobstructed drivable corridor |
| [Walkway](../tests/bridge_walkway.png) | Separated path, parapets, rails and pylon portal ahead |
| [Pylon close-up](../tests/bridge_pylon.png) | Grounded shafts, cornices, windows, deck portal and adjacent arch bearing |
| [Milsons Point](../tests/bridge_milsons.png) | Curved northern approach; Opera House and CBD visible across the harbour |
| [Southern approach](../tests/bridge_south.png) | Road/footway continuation from Stage A toward Dawes Point |

Screenshots and logs remain local ignored artifacts under `tests/`, consistent
with previous phases. Re-run the capture script to regenerate them.

## Performance

Final visual build observation: bridge **1,076 ms**, whole Sydney world
**3,043 ms**. Headless focused builds were approximately **180–200 ms** for the
bridge and **1.6–1.8 s** for the world. These are individual observations under
different rendering conditions, not a benchmark or FPS claim.

The six structural/material batches contain **69,918 render triangles** and
**3,051 steel members**. Additional site land, water and local roads have three
mesh nodes. Batched collision contains **18,620 triangles**, plus the central
road box. There is one physics body, no body per brace and no bridge `_process`.

## Files and working tree

Created:

- `sydney/landmarks/harbour_bridge.gd` and `harbour_bridge.json`
- `sydney/sydney_bridge_test.tscn`
- `scripts/sydney_bridge_district.gd`
- `tests/bridge_reference.py`, `tests/bridge_prepare.py`
- `tests/harbour_bridge_test.gd`, `tests/harbour_bridge_visual.gd`
- this report; local `tests/bridge_*.png` captures and test logs

Modified existing files: `sydney/sydney_world.gd`, `docs/SYDNEY_PLAYTEST.md`,
`STATE.md`. Existing user modifications to AGENTS, README, architecture/test
reports, camera, district and player remain. Most Sydney work was already
untracked at takeover; Git therefore reports the whole `sydney/` directory as
untracked rather than a tracked diff for its world script. No reset, clean,
stash, commit or push was performed. The OSM repository was read only.

## Limits and next phase

The landmark is a playable, geographically aligned structural approximation.
It is not a fabrication model: arch chord equations, section sizes, approach
span arrangement, lane allocation, pylon detailing and grades are simplified.
The flat and sparse North Shore connection area intentionally ends at the bounded
site. Local roads are visual ribbons supported by land collision, as in Stage A.
Pedestrian routing is physically continuous but is not added to the export's
pedestrian graph; there are no NPC pedestrians or traffic to route in this phase.
There is no dynamic lane reversal, train service, toll logic, station, lift or
interior. Water remains impassable and the existing Opera House sail geometry is
unchanged. The editor itself was not used to press F6; the exact scene was loaded
and exercised in the engine by the same scene resource path.

Recommended next phase: a focused terrain/elevation pass for the immediate
bridge approaches and pedestrian access, replacing the documented grades with
survey-backed levels before expanding the North Shore. The prior Opera House
sphere-section roof, tile and podium-detail work remains a separate backlog item.
