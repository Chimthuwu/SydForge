# Sydney Stage A geometry correction

**Phase 2 correction:** the mathematical outward CCW triangles described below
must be reversed at the Godot render/collision boundary, whose fronts are
clockwise. Real exterior-ray and isolated-render tests exposed this mismatch.
The original 107 assertions remain unchanged and pass. See
[Phase 2 evidence](SYDNEY_ARCHITECTURE_PHASE2.md) for the verified adapter fix;
the historical claim below that the emitted winding alone sufficed is superseded.

Status: implemented in the working tree, uncommitted. The import format and the
installed `world.json` are unchanged.

## 1. Baseline reconciliation

The working tree is commit `a8dc2a2` plus the uncommitted Sydney Stage A work.
The exact existing suite was run twice after the geometry changes:

```bash
cd "Z:/GITHUB/_GAMES/New folder"
APPDATA="$PWD/.runtime" ./Godot_v4.7.2-stable_win64_console.exe \
  --headless --path . --script res://tests/integration.gd \
  --log-file tests/integration-run1.log
```

Both runs exited 1 with **63 checks, 2 failures**:

- `melee damages nearby enemy`
- `enemy defeat grants reputation`

`docs/TEST_REPORT.md` records a historical 63/0 result. That result does not
reproduce on this tree. The two failures were already recorded before the
geometry pass in `docs/BASELINE_VERIFICATION.md`, and the geometry work does not
run in the default District Zero path. They were not fixed in this phase.

### Handover failure reconciliation

The continuation handover reported geometry exit 1 with truncated output. Two
fresh runs on this working tree produced no `FAIL`, `SCRIPT ERROR` or parse
error and ended at **107 checks, 0 failures**, exit 0. The only earlier geometry
failures were at the 98-check stage:

- `road junction: patch bounded by incident road widths` counted the incident
  ribbons' legitimate 50 m endpoints as junction spikes; the assertion was
  corrected to reject only intermediate vertices in the 15–45 m annulus.
- `crossing: stripes stay within the supplied crossing envelope` had the
  walking/road axes transposed; the bar envelope was corrected to 10.2 m across
  the crossing and 11.5 m along the road.

Both were test-expectation defects, not production mesh defects, so no mesh
rewrite was made for them. A separate production gap was found and fixed: a
sub-millimetre edge used to make `_add_path()` drop the entire path. Paths now
simplify near-zero edges before building cross-sections and retain the rest.

## 2. Source-data audit

Read-only diagnostic:

```bash
cd Z:/GITHUB/_EXPERIMENTS/Sydney/sydney-osm-world
python scripts/audit_stage_a_geometry.py
```

Results for the installed export:

| Check | Result |
|---|---|
| Duplicate consecutive vertices (rings and paths) | 0 |
| Duplicate closing vertices | 0 |
| Zero-length edges | 0 |
| Zero-area rings | 0 |
| Invalid/self-intersecting rings | 0 |
| Short rings | 0 |
| Buildings | 930, of which **386 concave** |
| Hole fields in buildings/parks/water | **0** |
| Road endpoint multiplicity | degree 1: 3,133; 2: 2,721; 3: 1,371; 4: 504; 5: 173; 6: 57; 7: 17; 8: 8 |
| Junction degree counts | 2: 1,086; 3: 238; 4: 90; 5: 13 |
| Junction incident widths | 8.0–28.8 m |

The audit's Shapely triangulation reports 3 zero-area roof triangles on the
source polygons. The production `Geometry2D` path skipped **0** building
triangles and built all 930 footprints; the diagnostic triangles are not present
in the rendered mesh. The exporter was not modified.

## 3. Buildings

`sydney_mesh.gd::buildings()` no longer uses centroid-to-midpoint direction.

1. Clean the ring, remove consecutive duplicates and a repeated closing vertex.
2. Reject rings with fewer than three vertices or signed area below 0.5 m².
3. Compute signed area once. For a counter-clockwise ring the outward edge
   normal is `(dz, -dx)`; clockwise reverses it. This is valid for concave
   footprints because it depends only on the edge, not on a centroid.
4. Pre-triangulate the roof before writing walls. A footprint whose roof has no
   non-degenerate triangle is skipped entirely, so a roofless shell cannot be
   emitted silently.
5. Orient every wall/roof triangle to its supplied normal. Building material is
   now `CULL_BACK`; the old global disabled culling is retained only for
   single-sided flat surfaces.
6. Append exactly the same oriented triangles to the collision `faces` array as
   are rendered.

`buildings()` returns `built`, `skipped`, `degenerateTriangles`, rendered
triangle count and collision faces. Stage A: **930 built, 0 skipped, 0
degenerate triangles, 17,334 rendered triangles, 17,334 collision triangles**.

## 4. Road ribbons and junctions

`flat_paths()`/`_add_path()` now build a continuous cross-section at every
vertex:

- each segment gets a left/right offset from its own direction;
- a shared miter cross-section is used when the turn is safe;
- miter scale is limited to 2.5× half-width; acute turns fall back to a bevel
  quad joining the two segment cross-sections;
- ends use butt caps (no arbitrary extension);
- zero-area triangles are discarded.

`road_mesh()` adds bounded junction surfaces for degree ≥ 3. For each incident
road it finds the nearest point on that road, takes the two kerb corners at the
junction using the road's own width, and triangulates the convex hull of those
corners. The patch is bounded by incident road widths, not a fixed circle. It is
drawn 4 mm below the ribbons to avoid z-fighting. Degree-2 joins are already
covered by the overlapping ribbons. Stage A has 341 degree ≥ 3 junctions
(238 three-way, 90 four-way, 13 five-way).

## 5. Crossings

The exporter's crossings are **derived-provisional junction crossings**, not
surveyed zebra markings. `crossings()` now emits spaced bars instead of one
solid rectangle:

- bar length 3.0 m parallel to the road;
- bar width 0.55 m, gap 0.55 m;
- repeated across the supplied crossing length (road width + 1 m).

Because the exporter puts every crossing at the junction centre, four markings
at one intersection previously stacked into a radial target. `SydneyWorld`
shifts only the **paint** along each road approach by `road_width/2 + 2 m`.
The crossing centre in the JSON and the walkable footpath are unchanged. These
dimensions and the offset are presentation assumptions, not OSM facts.

## 6. Polygon holes

The Stage A export has **no inner rings** for buildings, parks or water. The
water export explicitly says it is a clipped union with holes ignored. Therefore
`flat_polygons()` continues to treat every supplied ring as an independent
filled polygon and does not claim hole support. If a future export adds holes,
the mesh API must be extended before that data is drawn; silently passing an
inner ring would fill the hole.

## 7. Tests

| Suite | Command | Result |
|---|---|---|
| Geometry (synthetic) | `godot --headless --script res://tests/sydney_geometry_test.gd` | **107 checks, 0 failures** |
| Export validation | `python scripts/test_stage_a_export.py` | **162,610 checks, 0 failures** |
| Importer/game | `SPLOOGE_SYDNEY=1 godot --headless --script res://tests/sydney_scene_test.gd` | **23 checks, 0 failures** |
| District Zero baseline | `godot --headless --script res://tests/integration.gd` | **63 checks, 2 failures (unchanged)** |

The geometry suite uses the production mesh functions, not copied algorithms.
It covers clockwise/counter-clockwise rectangles, a concave L, an irregular
concave footprint, duplicate closing vertex, degenerate polygon, outward wall
probes, roof normals, collision parity, straight/90°/acute/narrow/wide/
disconnected/repeated roads, a sub-millimetre zero-length edge, T and four-way
junctions, convex/concave/reversed polygons, two separate rings, and crossing
bar count/envelope.

## 8. Rendered verification

Six captures were written and inspected:

| File | View |
|---|---|
| `tests/sydney_street.png` | George Street / Town Hall street level |
| `tests/sydney_overview.png` | aerial CBD |
| `tests/sydney_circular_quay.png` | harbour / Circular Quay |
| `tests/sydney_road_bend.png` | 1.79 rad bend at the Hyde Park edge |
| `tests/sydney_junction.png` | four-way junction with approach stripes |
| `tests/sydney_concave_building.png` | isolated concave footprint diagnostic |

Observed: walls and roofs are present with back-face culling; junction surfaces
connect the approach ribbons; crossing bars appear as separate ladder stripes
rather than one block or a radial target. The green island in the bend capture is
the mapped Hyde Park boundary (nearest park ring distance 0.0 m), not an
uncovered road triangle. The concave capture hides the aggregate building mesh
and shows one footprint so neighbours cannot obscure it.

Remaining visual limitations:

- The Rocks / Circular Quay still have almost no buildings because the source
  building sample is CBD-only. This is a data-scope gap, not a mesh defect.
- Some narrow road/bridge ribbons read as thin dark slivers in the aerial view.
- The terrain is flat at y = 0; there is no DEM.
- Crossings are inferred and their bar dimensions are not surveyed.
- No LOD or chunk streaming exists yet.

## 9. Performance sanity check

Measured once during the windowed capture on the bundled Godot 4.7.2
Compatibility renderer:

| Layer | Vertices | Triangles |
|---|---:|---:|
| Water | 414 | 138 |
| Parks | 3,507 | 1,169 |
| Roads (including junction patches) | 46,245 | 15,415 |
| Footpaths | 61,302 | 20,434 |
| Crossings | 83,454 | 27,818 |
| Buildings | 52,002 | 17,334 |
| Building collision | — | 17,334 |

Build time: **365.5 ms** in the final capture (Ground 1.4, Water 3.5, Parks 9.1,
Roads 81.7, Footpaths 112.1, Crossings 78.9, Buildings 78.7 ms); repeated
captures ranged about 363–377 ms. The world is still one aggregated mesh node
per layer; no per-building nodes were introduced. No frame time or GPU profiler
result is claimed.

## 10. Left for the next phase

1. Recover real OSM footways/crossings (Overpass TLS is still unavailable) and
   replace the derived layers.
2. Bake the pedestrian graph into a navmesh and add navigation-aware enemies.
3. Add the Rocks/Circular Quay footprints and the authored Harbour Bridge /
   Opera House assets (CC0 MegaKit remains a separate phase).
4. Add chunk streaming, LOD and terrain before expanding geographic scope.
