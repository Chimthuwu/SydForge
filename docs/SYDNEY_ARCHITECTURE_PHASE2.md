# Sydney architecture pilot — 19 November 2026

Implemented and tested in the existing working tree; not committed or pushed.
Seven reviewed CBD footprints have modular facades; 923 remain procedural.
All 930 retain their original geographic shell and footprint collision. This is
a proven architecture pilot, not a finished recognisable reconstruction of Sydney.
Default District Zero, the Sydney opt-in switch and gameplay code are unchanged.

## Assets and provenance

Verified the actual archive at
`Z:/GITHUB/_ASSETS/ASSETS/3D/Buildings-Shops/Downtown City MegaKit[Standard].zip`.
SHA256: `5B1A945576D54CDBB4CCC9C3D52711E6D530DA74C74C586407ECC28B165335DA`.
The included `License_Standard.txt` identifies Quaternius and CC0 1.0 Universal.
The [author's page](https://quaternius.com/packs/downtowncitymegakit.html)
also identifies CC0 and describes the Boston/NYC origins of the kit. The full
commercial/source edition's model count and custom shaders are not claims about
this Standard archive. The archive has 153 native Godot glTF modules.

Only eight glTF files, eight binary buffers and twelve referenced PNG textures
were extracted, together with the licence (29 source files, approximately 45 MiB).
`tests/extract_architecture.ps1` records the selection and refuses to overwrite
existing assets. The shared library was read-only. No FBX, complete example
buildings, street pieces, HDR environments or unrelated pack content was imported.
The adjacent `inventory.json` records source nodes, position bounds and materials.

| Imported module | Native dimensions, metres (X/Y/Z) |
|---|---|
| Brick_Window_Square_Single | 2 / 3 / 0.271 |
| Brick_Window_CurvedDouble | 4 / 3 / 0.261 |
| Trim_Window | 2 / 3 / 0.240 |
| Trim_FirstFloor_Window_Columns | 2.147 / 2.337 / 0.092 |
| Metal_FullWindow | 2 / 3 / 0.231 |
| Metal_FirstFloor_Window | 2 / 3 / 0.259 |
| Cornice_Trim_Center | 2 / 0.998 / 0.628 |
| Prop_ACUnit | 0.893 / 0.600 / 0.347 |

Axes are X across, Y up, **+Z exterior**, confirmed from the source normal buffer
and rendered inspection. Most facade pivots are bottom-centred. The ground-floor
column piece starts at y=0.590091; bounds-based normalization corrects this.
The AC pivot has a negligible negative y offset, covered by its roof offset.
Every selected model is a single identity-transform mesh node, verified in glTF.
The loader's single-mesh assumption is intentionally limited to this selection.

Textures are shared BaseColor/Normal/ORM sets for brick, trim, metal/concrete and
ornaments. Dependencies resolve locally. Godot 4.7.2 imported all eight models
and their materials; real Compatibility renders ran on the RX 6600. Pale stone
overrides the trim wall material; fake-interior placeholders become dark backing.
The paid edition's interior shaders are not included or imitated.

## Assembly and integration

`sydney/architecture/assembler.gd` separates a deterministic placement plan from
render assembly. Identity hashing controls style, bay composition, fascia colour,
glass bands and rooftop equipment. Callers can explicitly supply
`architectureStyle` (`brick`, `stone`, `glass`) without modifying exported OSM.

- Bays follow each actual convex footprint edge; no axis-aligned replacement box.
- Ground floors are up to 4.2 m; remaining floors divide the exact exported height.
- Widths fit integer bay counts, with corner margins and procedural piers.
- Both ring windings produce upright, right-handed transforms, facing outward.
- Three families supply brick arches, pale masonry/cornices and glass office grids.
- Shop glazing/fascia, parapets, corner piers and roof AC complete the shell.
- AC footprints are checked inside the roof before placement.
- Instances batch by mesh with MultiMesh. Original mesh materials remain shared.
- Concave rings, holes, short edges, degenerate footprints and unsupported heights
  are rejected by the plan. The world retains its existing procedural shell.

Facade backing is offset 0.32 m outside the exact shell so recessed windows are
not hidden by it. Cornices project farther; the clearance audit conservatively
tests a 0.9 m buffer. Ornament is visual only; collision remains the exact OSM
shell, with no individual window/cornice colliders. Interiors are not accessible.

The pilot is an explicit reviewed ID allowlist, further checked for supported
geometry and proximity to the existing George Street/Town Hall-labelled spawn.
Initial nearest-building candidates overlapped derived road/footpath ribbons.
They were excluded instead of changing OSM, roads or gameplay. The GPO landmark
was also excluded because it requires an authored facade. Do not expand the list
without running the clearance diagnostic again after data changes.

| OSM ID | Family | Height | Floors | Facade bays |
|---|---|---:|---:|---:|
| way/620819399 | pale stone | 17.0 m | 5 | 140 |
| way/448339172 | pale stone | 16.0 m | 5 | 210 |
| way/335699128 | glass | 48.0 m | 15 | 615 |
| way/386563353 | glass | 41.6 m | 13 | 286 |
| way/1176087505 | brick | 9.6 m | 3 | 66 |
| way/547758509 | glass | 44.8 m | 14 | 280 |
| way/173542968 | glass | 102.4 m | 32 | 1,216 |

These are illustrative architectural treatments, not surveyed facades or claims
that each family's assignment matches the actual named building.

## Verified foundation defect corrected

The isolated prototype revealed missing outer walls/roofs, and four initial
wall-ray probes missed. Existing geometry emits mathematical CCW triangles with
outward cross products; Godot uses clockwise fronts. Prior tests verified the
mathematics but did not verify this engine boundary.

`SydneyMesh.engine_building_mesh()` reverses the render indices, while
`engine_building_faces()` applies the identical reversal to collision triangles.
Normals, positions, topology and geographic coverage are unchanged. Normal
back-face culling remains enabled. All original assertions are unchanged.
New tests check clockwise winding, render/collision parity, exterior wall rays
and roof rays. An interim culling-only workaround caused visible shadow artefacts
and was replaced; final captures no longer show those artefacts.
See [Godot's winding convention](https://docs.godotengine.org/en/stable/classes/class_surfacetool.html).

## Verification

| Suite | Final result |
|---|---|
| Existing `test_stage_a_export.py` | 162,610 checks, 0 failures; exit 0 |
| Existing `audit_stage_a_geometry.py` | exit 0; 0 invalid rings/zero edges; 386 concave buildings; same 3 Shapely-only degenerate diagnostic roof triangles |
| Existing `sydney_geometry_test.gd` | 107 checks, 0 failures; exit 0 |
| Existing `sydney_scene_test.gd` | 23 checks, 0 failures; exit 0 |
| New `architecture_test.gd` | 80 checks, 0 failures; exit 0 |
| New `architecture_clearance.py` | 29 checks, 0 failures; exit 0 |
| Existing District Zero `integration.gd` | 63 checks, **2 failures**; exit 1 |

The unchanged District Zero failures are `melee damages nearby enemy` and
`enemy defeat grants reputation`. No existing test was weakened or removed.
The architecture suite covers imports/materials, five compositions, dimensional
fit, orientation, height, determinism, reverse winding, unsupported fallback,
engine triangle parity, all 930 shells, and wall/roof physics for each pilot row.
The clearance suite reports zero existing and zero additional envelope overlap
against exported road and footpath ribbons for all seven selected footprints.
It is not a surveyed pedestrian accessibility assessment.

Known diagnostics: restricted headless runs print the existing root certificate
store warning; the importer test deliberately logs a missing-file error; gameplay
suites can report eight ObjectDB instances leaked at shutdown. These were not
treated as clean diagnostics or fixed by changing unrelated systems.

Run from the game directory with the bundled console executable, local test
`APPDATA=.runtime`, `--headless --path . --script res://tests/<test>.gd` and a
distinct `--log-file`. Set `SPLOOGE_SYDNEY=1` only for the Sydney scene test and
visual script. Clear it for District Zero. Python 3.11 with the already-installed
Shapely ran the export/audit/clearance checks. No tools were installed.
The installed gda launcher failed before execution (`uv trampoline failed to
canonicalize script path`); bundled Godot was the verified fallback.

## Personally inspected rendered evidence

All eight final PNGs were opened and visually inspected, not merely generated:

| File under `tests/` | Inspection |
|---|---|
| architecture_prototype.png | five compositions, varied heights, roof coverage, glass tower |
| architecture_prototype_detail.png | shopfronts, brick/stone contrast, corner alignment and ground contact |
| architecture_george_street.png | existing spawn street, road/footpaths; mostly fallback buildings remain here |
| architecture_town_hall.png | spawn-area context and nearby pilot among retained shells; no authored Town Hall |
| architecture_aerial.png | CBD density, limited pilot coverage, surrounding fallback skyline |
| architecture_facade.png | five-storey pale masonry frontage, cornice and ground glazing |
| architecture_corner.png | adjacent shell contact and edge treatment; neighbour partially limits side view |
| architecture_tall.png | full 102.4 m pilot glass tower, roofline, ground contact and adjacent streets |

No floating pilot, missing roof or missing material was observed. The isolated
chamfered prototype supplies a clearer corner view than the dense in-world shot.
The city remains visually dominated by 923 plain shells. Regular window grids,
simple glass and undecorated shop signs remain evident; this is not final art.
Captured with `tests/architecture_visual.gd`; screenshots are local ignored test
artifacts under the existing `.gitignore`, and are reproducible.

## Measurements and limits

Final headless architecture run: **422.193 ms** total world build, including
**130.036 ms** building work. Final rendered run: **1,586.069 ms** total,
including **1,284.658 ms** buildings (asset loading/material/GPU startup included).
These are individual observations, not controlled benchmarks. No FPS improvement,
steady-state frame-time, memory budget or target-hardware performance claim.

The five-building prototype is `sydney/architecture/prototype.tscn`. It includes
small, medium, tall, chamfered corner and alternate composition examples, with
building collision, light and camera. Its floor is a visual presentation plane.
No terrain, traffic, pedestrians, navigation, streaming or landmark reconstruction
was added. Existing inferred road overlaps elsewhere remain outside this pilot.
The project has no existing save implementation according to its baseline docs;
none was introduced or changed.

## Files and repository state

New authored files: `sydney/architecture/assembler.gd`, `prototype.gd`,
`prototype.tscn`, the selected `megakit/` assets/licence/inventory,
`tests/extract_architecture.ps1`, `architecture_test.gd`, `architecture_visual.gd`,
`architecture_clearance.py`, generated `architecture_pilot.json`, this report,
`STATE.md` and `PITFALLS.md`. Godot also generated import metadata and script UIDs.

Existing files changed by this phase: `sydney/sydney_world.gd`,
`sydney/sydney_mesh.gd`, `AGENTS.md`, `docs/SYDNEY_INTEGRATION.md`,
`docs/GEOMETRY_CORRECTION.md`, `docs/SYDNEY_ASSET_COMPATIBILITY.md`.

Game repository remains dirty. Pre-existing tracked changes to `README.md`,
`docs/ARCHITECTURE.md`, `docs/TEST_REPORT.md`, `scripts/camera_rig.gd` and
`scripts/district.gd` were preserved without edits by this phase. Stage A was
already untracked (`sydney/`, launch script, Sydney docs/tests); new work remains
untracked too. See `tests/phase2_git_status.txt` for the final status listing.

Sydney pipeline repository remains exactly at its initial dirty status:
modified `sydney-osm-world/config/sydney.config.json`; untracked `docs/`,
`sydney-osm-world/docs/STAGE_A_EXPORT.md`, `sydney-osm-world/export/`, and
`scripts/{audit_stage_a_geometry,build_stage_a,test_stage_a_export}.py` under
`sydney-osm-world/`. No pipeline source/data change was made in this phase.
No commit, push, reset, checkout or global Git configuration change was made.
