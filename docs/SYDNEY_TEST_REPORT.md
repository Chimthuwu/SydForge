# Sydney Stage A test report

Engine: bundled Godot 4.7.2, Compatibility renderer, Windows.
Export source: `Z:\GITHUB\_EXPERIMENTS\Sydney\sydney-osm-world`.
Tree: commit `a8dc2a2` plus uncommitted Stage A/geometry work.

## Current results

| Suite | Command | Result |
|---|---|---|
| Export validation | `python scripts/test_stage_a_export.py` | **162,610 checks, 0 failures** |
| Geometry (production mesh functions, synthetic input) | `godot --headless --script res://tests/sydney_geometry_test.gd` | **107 checks, 0 failures** |
| Importer + game adapter | `SPLOOGE_SYDNEY=1 godot --headless --script res://tests/sydney_scene_test.gd` | **23 checks, 0 failures** |
| Existing gameplay regression | `godot --headless --script res://tests/integration.gd` | **63 checks, 2 failures — unchanged** |
| Rendered capture | `SPLOOGE_SYDNEY=1 godot --script res://tests/sydney_visual.gd` | 6 PNGs written and inspected |

The baseline command was run twice; both runs exited 1 with the same two
failures:

- `melee damages nearby enemy`
- `enemy defeat grants reputation`

They were already recorded on the clean tree in
`docs/BASELINE_VERIFICATION.md`. The historical 63/0 figure in
`docs/TEST_REPORT.md` does not reproduce on this tree. No unrelated gameplay
bug was fixed in this phase, and the Sydney adapter does not run in the default
District Zero path.

The geometry test exit 1 in the continuation handover was stale. Fresh runs on
this tree have no failing assertion. The earlier 98-check failures
(`road junction: patch bounded by incident road widths` and
`crossing: stripes stay within the supplied crossing envelope`) were wrong test
bounds, not production mesh defects; the corrected suite now passes 107/0. A
genuine zero-length path edge case was found separately and fixed: near-zero
segments are simplified instead of dropping the whole path.

## Export validation

Checks include: format/version, retained origin and 1 m units, north = −Z,
finite coordinates (every number walked), road geometry/width/unique IDs,
recomputed road and footpath totals vs `stats`, every road/footpath point inside
the slice, zero duplicate consecutive points, no sidewalk point inside a
carriageway, junction/crossing references, building ring area/height/source
labels and sample-box placement, water/parks rings, and explicit overlap
budgets:

- water covers <0.5% of building area (measured 3.8 m²);
- parks overlap <5% of their area with buildings (measured ~1.55%);
- surface road ribbons overlap <15% of building area (measured 10.45%);
- pedestrian graph ≤60 components and ≥75% main-network share (measured 39 /
  86.2%);
- spawn is on a road, out of water, and >1 m from a building; four vehicle
  spawns exist; Harbour Bridge / Opera House gaps are recorded.

Read-only geometry audit (`scripts/audit_stage_a_geometry.py`): 0 duplicate
consecutive vertices, 0 duplicate closing vertices, 0 zero-length edges, 0
zero-area rings, 0 invalid rings, 386 concave buildings, and **0 hole fields**
in buildings, parks or water. The export was not modified.

## Geometry suite

`tests/sydney_geometry_test.gd` calls the production functions. It verifies:

- clockwise, counter-clockwise, L-shaped and irregular concave buildings;
- outward wall normals using inside/outside probes, including the concave
  reflex edges;
- upward roof normals, finite vertices/normals, no zero-area triangles;
- repeated closing vertex and collinear/degenerate footprint rejection;
- collision triangle count matches rendered triangles;
- straight, 90-degree, acute, narrow, wide, disconnected and repeated road
  ribbons, a sub-millimetre zero-length edge, with a 13 m spike bound;
- T-junction and four-way junction coverage and bounded patches;
- convex, concave, reversed and multiple park/water rings;
- multiple crossing bars and their envelope.

Stage A building result: **930 built, 0 skipped, 0 degenerate triangles**,
17,334 rendered and 17,334 collision triangles. There is no hole support because
the source has no inner rings; this limitation is explicit in
`docs/GEOMETRY_CORRECTION.md`.

## Importer + adapter

Checks: JSON loads, road/building stats, four vehicle spawns, spawn away from
origin, all layer nodes built, ground and building collision created, missing
file fails safely, district switches to Sydney, player settles on ground at the
Sydney spawn, four vehicles and enemy still spawn, HUD still updates, **player
walks on Sydney ground, pistol consumes ammunition and damages an enemy, and a
vehicle enters and accelerates**.

## Rendered result

- `tests/sydney_street.png` — George Street/Town Hall, CBD buildings on both
  sides, road and footpath ribbons, existing car in the street.
- `tests/sydney_overview.png` — CBD skyline with varying real/derived heights,
  Hyde Park green, harbour edge.
- `tests/sydney_circular_quay.png` — harbour water and the still-empty
  Quay/Rocks strip.
- `tests/sydney_road_bend.png` — 1.79 rad bend at the Hyde Park edge, with
  crossing stripes. The green island is the mapped park boundary, not a hole in
  the road mesh.
- `tests/sydney_junction.png` — four-way junction, continuous junction surface,
  stripes on separate approaches rather than a stacked radial pattern.
- `tests/sydney_concave_building.png` — isolated concave footprint diagnostic;
  the aggregate building mesh is hidden for this shot so neighbours do not
  obscure it.

Walls and roofs are visible with back-face culling enabled for buildings. No
obvious missing building faces, filled holes or unconnected junction centres
were found in these views. Thin dark slivers remain on some narrow
road/bridge ribbons in the aerial view.

## Performance record

One windowed capture reported 46,245 road vertices / 15,415 triangles, 61,302
footpath vertices / 20,434 triangles, 83,454 crossing vertices / 27,818
triangles, 52,002 building vertices / 17,334 triangles, and 17,334 collision
triangles. Total world build time was 365.5 ms in the final capture (about
363–377 ms across repeated captures). This is a generation-time and scene-size
sanity check, not a frame-time profile.

## Not verified

- Frame time / GPU performance. No profiler run.
- Collision behaviour along every street; only spawn/ground, scene creation and
  matching collision triangles were asserted.
- Navigation meshes, traffic, pedestrians — not implemented.
- GUI interactive play beyond the automated capture (no human feel test).
- The two pre-existing melee failures were not fixed: they are outside the
  Sydney integration and changing gameplay was out of scope.
