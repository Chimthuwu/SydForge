# Sydney Opera House landmark — Phase 3

Implemented and tested in the existing working tree; not committed or pushed.
A geographically aligned Opera House now stands on Bennelong Point in the Sydney
Stage A world: an OSM podium, ten authored shell sails derived from the OSM roof
contours, foyer glazing, monumental steps, a forecourt plaza, and collision.
Default District Zero, gameplay, traffic, architecture and the Stage A export are
unchanged.

This is a convincing first landmark, not a surveyed reconstruction. The roof is a
parametric sail surface, not the real sphere-section geometry, and the podium
detail is coarser than the real building. Limitations are listed in section 9.

## 1. What was already present at takeover

The previous agent had exhausted its limit during research. Its work was reused
verbatim and not repeated:

| Artifact | State found | Used for |
|---|---|---|
| `tests/opera_reference.py` | working | retrieved and pinned the OSM extract; left unchanged |
| `tests/opera_prepare.py` | working | first polygon union + plan sketch; left unchanged |
| `.runtime/phase3/bennelong.osm` | downloaded | source of all roof/building-part tags |
| `.runtime/phase3/reference.json` | 385 features | authoritative projected geometry for this phase |
| `.runtime/phase3/reference-audit.txt` | UTF-16 audit dump | confirmed no Opera House rows in Stage A |
| `.runtime/phase3/aerial-reference.jpg` | downloaded | plan layout cross-check (2 groups + restaurant) |
| `.runtime/phase3/osm-roof-plan.png` | generated | showed the shell contours as nested sails |
| `sydney/landmarks/opera_house_reference.json` | generated | provenance record |

No research was redone. The Stage A export was confirmed to contain **no Opera
House building rows** (`Stage A Opera rows: []`), so the landmark is authored and
injected rather than imported.

## 2. What the OSM relations actually are

The relations are **not** independent structures. Each `relation` carries
`building:part=roof`, `layer=3|4|5`, `roof:material=roof_tiles` and a
`comment` such as `layer 5 A roof`. Their member ways polygonise into plan
contours of the same shells at different render layers, so a layer is a stack
level, not a storey. Treating a whole relation as one building would produce a
slab; unioning all of them would produce one giant mass with no shells.

| Relation | Tag evidence | Interpretation | Modelled as |
|---|---|---|---|
| `9596872` | `building=civic`, `landmark=1`, `name=Sydney Opera House`, `building:levels=5`, `comment=base ~10? meters height.`, `roof:shape=many` | The real building outline: the podium / ground footprint | Podium footprint, used **verbatim** (57 vertices, 15,885 m²) |
| `9596878` | `layer=5`, `roof:shape=round`, `colour=white`, `roof:material=roof_tiles` | Roof plan contours — the northern shell row | 4 shell sails |
| `9677509` | `layer=4`, same roof tags | Roof plan contours — the southern shell row | 4 shell sails |
| `9677501` | `layer=4`, `comment=layer 4 c roof` | Bennelong Restaurant shells, south-west tip | 2 shell sails (200 m² pair) |
| `9596873` | `layer=3 A roof`, 22 polygons incl. 2 m² slivers | Lower contours of the same shells plus access slivers | Not modelled separately |
| `9677503` | `layer=3 E roof`, 6–98 m² fragments | Same, lower contours | Not modelled separately |
| `9596874`, `9596876`, `9596880` | `comment=maintance access ... roof` | Roof access surfaces under 60 m² | Not modelled |
| `9596881` | `material=glass`, `comment=glass roof` | Glass roof over the western foyer | Represented by the glazed foyer walls |
| ways `681506197/198`, `690624100/152`, `1427781151`, `1510928430–446` | `building=roof`, `roof:shape=skillion`, `amenity=shelter` | Small shelters and a sun-shade structure, 33–160 m² | Not modelled (not the Opera House) |

Filtering out every polygon under 150 m² removed the access slivers and left
exactly ten shell plans: four for the Concert Hall group (west), four for the
Opera Theatre group (east) and two for the restaurant — the same count as the
real ten-shell roof.

## 3. Placement and coordinate conversion

The landmark is placed in the **existing** world projection; no new projection or
origin was introduced.

- Origin latitude −33.8730, longitude 151.2080; X = east, Z = south, Y = up,
  1 unit = 1 metre (`world.json → coordinateSystem`).
- `tests/opera_reference.py` already projected lon/lat with
  `metersPerDegreeLongitude/Latitude`. Those projected rings are reused
  unchanged, so the landmark and the Stage A mesh share one frame exactly.
- Podium centroid: **(658.72, −1763.81)**. Podium bounds
  X 594.26…729.45, Z −1853.47…−1673.02.
- Podium long axis (the 169.7 m rectangle side, not the diagonal):
  **(0.22972, −0.97326)**, i.e. 13.3° east of north.

The landmark data file stores each shell as a world-space OBB (centre, axis,
length, width) plus its source ring. All geometry is generated in world
coordinates; nothing is scaled or repositioned at runtime.

`tests/opera_landmark_data.py` regenerates `sydney/landmarks/opera_house.json`
from `.runtime/phase3/reference.json` deterministically, verifies that no Stage A
building overlaps the podium (result: none) and records the three unnamed service
ways whose vertices fall inside the podium.

## 4. Dimensions: measured versus authored

**Measured from OSM**

- Podium outline: 57 vertices, 15,885.0 m², 169.7 m long, 114 m wide.
- Shell plan centres and long-axis directions (from the contour OBBs).
- Shell contour extents, retained as `contourLengthM` / `contourWidthM`.
- Shell grouping and count (4 / 4 / 2) from the contour positions.

**Authored approximations**

| Quantity | Value | Basis |
|---|---|---|
| Podium top | 12.0 m | `building:levels=5` plus `comment=base ~10? meters height.`; 12 m chosen to suit the 67 m roof maximum. Approximation. |
| Podium tiers | 0…4, 4…8, 8…12 m, insets 0 / 1.7 / 3.3 m | Reads as the podium's layered sandstone bands; not surveyed. |
| Shell plan scale | ×1.25 length, ×2.0 width | The OSM contours are cut above the shell base. Scaling the largest contour (43.1 × 24.2 m) reaches 53.9 × 48.3 m, matching the published ~60 × 40 m shell plan. Approximation. |
| Shell apex heights | 67 / 60.5 / 55 m (Concert Hall), 58 / 52 m (Opera Theatre), 26 m (restaurant) | 67 m is the published roof maximum above the harbour; the rest are fitted to contour area. Approximations. |
| Shell surface | Parametric sail, ridge crease, 0.30 rad backward lean, 1.05 m thickness | The real shells are sections of a 75 m sphere. The 75 m radius is noted but **not** implemented; this is a fitted approximation. |
| Monument steps | 24 × 0.5 m rise, 1.05 m run, clipped to the southern band | Visual choice for silhouette legibility. The real Monument Steps are shallower and wider. |
| Step/forecourt extent | buffer +25 m / +34 m from the outline | Bounded by a clamped mitre buffer, so it cannot run away. |
| Foyer glazing | Vertical curtain under the northern end of each shell | Authored; the glass roof relation is not reproduced. |

## 5. Roof construction

`sydney/landmarks/opera_house.gd` builds each sail from its OSM contour OBB.

- Plan: lens of length `L` and half-width `w(s) = max(W/2·√(1−s²), 0.5)` for
  `s ∈ [−1, 1]`, where `s = −1` is the high south face and `s = +1` the harbour
  tip. The 0.5 m floor prevents zero-area tip triangles at 40 m scale.
- Height: `h(s) = H·sin(π·t^0.74)`, `t = (s+1)/2`. The shell rises steeply off
  the south face, peaks about a third of the way back, and sweeps down to a long
  northern point.
- Cross-section: `p(v) = 1 − |v|^1.6`, a pointed profile with a crisp ridge crease
  at `v = 0`, so surfaces meet at a genuine ridge line instead of a smooth dome.
- Tilt: the apex is sheared back over the harbour by 0.30 rad, which is what turns
  a dome into a leaning sail.
- Lateral lean: ±0.16 × width, outward from the building centre per group.
- Thickness: 1.05 m. The inner surface is the outer surface offset along its own
  normal; at the ridge **both halves offset from the same bisector (`Vector3.UP`)**
  so the inner surfaces meet watertight instead of leaving a slit. A rim ribbon
  closes the lateral edge and both ends.
- The two halves of each shell are tessellated separately (22 × 6 per half), so
  the ridge is a hard crease rather than a smeared average.
- Normals are computed analytically from finite differences of the parametric
  surface, one-sided at the ridge and at the tips, so there is no cross-crease
  smearing and no reliance on `generate_normals()`.
- Degenerate triangles are rejected at emission (`|cross| < 1e-6`), so tips and
  rim slivers cannot produce zero-area faces.

Podium, steps, forecourt and glazing are separate meshes with their own materials
(stone, paving, dark glass), which keeps six draw calls for the whole landmark.

## 6. Podium and site

- Podium: three extruded tiers from the OSM outline (plinth proud by 0.8 m, then
  insets of 1.7 m and 3.3 m), walls plus top faces, plus a pale deck surface.
- Monument steps: 24 nested tiers buffered outward from the outline and clipped
  to the southern band (`u ≤ −38 m` local), each extruded as a solid tier so the
  silhouette reads as stepped stone.
- Forecourt: a paved plaza at y = 0.12 buffered 34 m from the outline and clipped
  south of the shell mass.
- The step and podium tiers are all in the collision set, so ground contact is
  solid and the stepped base is physically present.
- Generic Stage A buildings inside the footprint are dropped
  (`OperaHouseLandmark.filtered_buildings`). The check currently removes **none**,
  because the export has no Opera House rows and nothing overlaps.
- Road centre lines that run under the podium are split there
  (`filtered_roads`); three unnamed service ways were split out and no ribbon now
  crosses the footprint. Unrelated roads are untouched (1,604 rows → 1,603).
- Circular Quay, the CBD mesh, the water rings, parks and footpaths are unchanged.

## 7. Scene integration

- `sydney/sydney_world.gd` reads the landmark podium ring before building, filters
  roads and buildings through it, and adds `OperaHouse` after `Buildings`.
- `_build_landmarks()` appends geometry counts and a `Landmarks` build time.
- The landmark is a `Node3D` with six `MeshInstance3D` children (`OperaPodium`,
  `OperaDeck`, `OperaSteps`, `OperaForecourt`, `OperaShells`, `OperaGlazing`) and
  one `StaticBody3D` (`OperaCollision`) holding a single
  `ConcavePolygonShape3D`.
- Winding follows the project convention: geometry is emitted mathematically CCW
  with outward normals, then converted once at the engine boundary through
  `SydneyMesh.engine_building_mesh()`/`engine_building_faces()`. The Opera House
  test asserts that the engine index buffer is clockwise about the stored normals.
- No gameplay, controller, camera, traffic, combat or HUD code was touched.

## 8. Tests and results

| Suite | Result |
|---|---|
| New `tests/opera_house_test.gd` | **57 checks, 0 failures**, exit 0 |
| Existing `sydney_geometry_test.gd` | 107 checks, 0 failures, exit 0 |
| Existing `sydney_scene_test.gd` | 23 checks, 0 failures, exit 0 |
| Existing `architecture_test.gd` | 80 checks, 0 failures, exit 0 |
| Existing `architecture_clearance.py` | 29 checks, 0 failures, exit 0 |
| Existing District Zero `integration.gd` | 63 checks, **2 failures**, exit 1 |

The two District Zero failures are the pre-existing baseline failures, unchanged
by this phase: **`melee damages nearby enemy`** and
**`enemy defeat grants reputation`**. They are independent of the landmark (which
is only built on the Sydney path) and were already failing before this work.

The Opera House suite covers: reference/provenance integrity; podium area, extent
and centroid against the projection; ten shells in a 4/4/2 group split; every
shell plan on the podium; apex range; mesh creation; triangle budget; **zero
degenerate triangles**; no non-finite vertices; unit normals; **clockwise engine
winding about the outward normals**; shell mass rising 55 m and spanning the
podium; deterministic rebuild (identical vertex checksum); a downward physics ray
hitting the roof mass and the southern deck at 12 m; no generic building removed;
no road through the podium; and the world exposing the landmark with a measured
build time.

Regenerate the authored data after any OSM reference change:

```bash
python tests/opera_landmark_data.py          # writes sydney/landmarks/opera_house.json
```

```bash
# Landmark suite (headless)
APPDATA=./.runtime ./Godot_v4.7.2-stable_win64_console.exe --headless --path . \
  --script res://tests/opera_house_test.gd --log-file tests/opera_house.log

# Rendered captures (windowed)
SPLOOGE_SYDNEY=1 APPDATA=./.runtime ./Godot_v4.7.2-stable_win64_console.exe --path . \
  --script res://tests/opera_house_visual.gd --log-file tests/opera_house_visual.log
```

## 9. Captures — inspected

All five PNGs were opened and visually inspected after the final build, not just
generated:

| File | What it shows | Inspection |
|---|---|---|
| `tests/opera_aerial.png` | Bennelong Point from the south-east at 175 m | All ten sails stand on the OSM podium in two groups plus the restaurant; the stepped base and deck are correct; no floating geometry, no missing material. |
| `tests/opera_harbour.png` | From the harbour, 16 m above water | The sails lean over the foyer line, ridge creases and the glazed foyer walls are visible, and the CBD skyline sits behind. Shells read as a sail cluster rather than the exact interlocking roof. |
| `tests/opera_forecourt.png` | Foreshore/forecourt, eye level | Broad stepped apron rising to the podium with the sail cluster above it. The framing is deliberately low and close, so the shells are partly cropped. |
| `tests/opera_roof_detail.png` | Above and east of the shells, 96 m | Overlapping shell surfaces, visible rim thickness, ridge creases and clean shading; no inverted or black faces, no holes. |
| `tests/opera_circular_quay.png` | Circular Quay approach | The clearest reading: the white shell cluster on its broad stepped podium at the point, with the harbour and coastline around it. |

Defects found and fixed during this inspection pass: the shells were originally
upright domes (fixed with the asymmetric height profile and 0.30 rad lean); and
`Geometry2D.offset_polygon` produced a runaway apron that turned the podium into
terrain (replaced with a clamped mitre buffer).

## 10. Performance

Measured in the final rendered run; single observations, not benchmarks.

| Metric | Value |
|---|---|
| Landmark build | 101.3 ms (100–146 ms across runs) |
| World build total | 1,921 ms (headless 1,921–2,096 ms across runs) |
| Landmark vertices | 39,396 |
| Landmark triangles | 13,132 |
| Landmark collision triangles | 13,951 |
| Mesh nodes | 6 render + 1 collision body |
| Per-frame cost | none; geometry is built once at load |

Shells are 11,920 of the triangles (22 × 6 grid per half per shell). Collision is
a coarse 6 × 2 rebuild for the shells plus the podium and steps. The landmark adds
about 13k triangles to a world that already draws ~86k, and six draw calls.

No FPS claim is made: the capture completed and rendered, but no profiled
frame-time measurement on target hardware was run.

## 11. Remaining limitations

- **Roof fidelity.** The shells are a parametric sail surface, not sections of a
  75 m sphere. Silhouettes, count, grouping, placement and relative heights are
  right; the interlocking geometry, the exact ridge curvature and the shell-to-
  shell junctions are approximated. The sails still read as ten distinct forms
  rather than one continuous interlocking roof.
- **Tile surface.** No chevron ceramic tile pattern, no tile ribs, no texture. The
  shells are a flat white material with a slight sheen.
- **Podium detail.** No surveyed frieze, balustrades, railings, lift/parking
  access, awning, or the real Monument Steps profile.
- **Interiors.** None. The concert hall, theatre and foyer volumes are solid.
- **Walkability.** The 0.5 m step risers are solid geometry, but the project's
  `CharacterBody3D` controller has no stair-step resolution, so the deck cannot be
  walked up from the ground. Fly/jump access only.
- **Not modelled.** Stage A has no landform here; the podium sits on the flat
  y = 0 ground plane like the rest of the world.
- **Other OSM detail.** The small `amenity=shelter` roof polygons and the `layer 3`
  lower contours are deliberately not drawn.
- **Draw order.** The glazed foyer curtains intersect the shell undersides where
  shells overlap, which is visible at close range.

## 12. Files and repository state

New files:

- `sydney/landmarks/opera_house.gd` — the landmark builder
- `sydney/landmarks/opera_house.json` — authored, derived geometry (10 shells,
  podium ring, provenance)
- `sydney/landmarks/opera_house_reference.json` — pinned OSM reference (from the
  previous agent's `opera_prepare.py`)
- `tests/opera_landmark_data.py` — deterministic derivation of the JSON
- `tests/opera_house_test.gd` — 57-check focused suite
- `tests/opera_house_visual.gd` — the five captures
- `tests/opera_*.png`, `tests/opera_house*.log` — ignored local artifacts
- this document

Modified files:

- `sydney/sydney_world.gd` — landmark build step, road/building suppression,
  `Landmarks` timing and `OperaHouse` geometry counts
- `STATE.md`

Untouched by this phase: `scripts/*`, `scenes/*`, `sydney/sydney_mesh.gd`,
`sydney/architecture/*`, `sydney/world/stage_a/world.json`, the Sydney pipeline
repository, and the source OSM extract.

The game repository remains dirty with the pre-existing tracked changes
(`AGENTS.md`, `README.md`, `docs/ARCHITECTURE.md`, `docs/TEST_REPORT.md`,
`scripts/camera_rig.gd`, `scripts/district.gd`) and the untracked Stage A work.
Nothing was committed, pushed, reset, stashed or checked out.

## 13. Recommended next step

Re-author the shells as true sphere-section surfaces (75 m radius, two
intersecting arcs per shell, real ridge lines) so the roof interlocks as one
mass, then add the chevron tile pattern and podium detail. The Harbour Bridge
remains the separate next landmark phase and was not started.
