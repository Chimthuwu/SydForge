# Sydney Stage A integration

Phase 2 adds seven reviewed modular building treatments while 923 remain
procedural, without changing startup or the geographic shell. See
[architecture pilot and verification](SYDNEY_ARCHITECTURE_PHASE2.md) for the
assembler, asset licence, engine winding correction, captures and current costs.
The per-layer counts and timings below describe the earlier Stage A baseline.

The Sydney prototype is a real OSM-derived CBD slice running inside the existing
Splooge game. Gameplay, vehicles, combat, enemies, camera and HUD are unchanged;
only the world source and spawn points are injected.

## 1. Launch

| Mode | Command |
|---|---|
| District Zero (default, unchanged) | `PLAY.cmd` |
| Sydney Stage A | `PLAY_SYDNEY.cmd`, or `Godot ... --path . -- --sydney` |
| Force Sydney in tests | set `SPLOOGE_SYDNEY=1` |

`district.gd::build_city()` now does three things:

1. builds the shared environment/sun (`build_environment()`);
2. if Sydney is requested, loads `SydneyWorld` and adds it;
3. otherwise, or if loading fails, builds the original 220 m District Zero
   (`build_district_zero()`).

A failed Sydney load logs the reason and falls back to District Zero instead of
leaving an empty scene.

## 2. Adapter seam

`district.gd` remains the composition root and owner of `hud`, `message`,
`hit_time`, `impact()`, `tracer()` and `sound()`. The loader only supplies:

- `player_spawn`, `player_yaw` → `player.spawn`, camera yaw;
- `vehicle_spawns`, `vehicle_yaws` → the four existing `ArcadeCar` scenes;
- `enemy_spawn` → `BoomEnemy.home`;
- `district_name` → HUD message.

The existing player/vehicle/enemy/camera scripts were not modified. The only
other gameplay-side change is `camera.far = 4000` so the city skyline is not
clipped.

## 3. Importer structure

| File | Responsibility |
|---|---|
| `sydney/sydney_world.gd` | JSON load, schema/coordinate validation, spawns, scene nodes, collision |
| `sydney/sydney_mesh.gd` | reusable ArrayMesh builders for ribbons, polygons, crossings, extruded buildings |
| `sydney/world/stage_a/world.json` | the installed, validated export |

The importer:

- rejects a wrong `format`, `formatVersion`, non-1.0 `metersPerUnit`, missing
  bounds, non-finite coordinates, and spawns outside the slice;
- stores the `pedestrianGraph` for future navigation; it does not bake a navmesh
  in this phase;
- tolerates optional missing fields and skips invalid individual records;
- builds one mesh per layer (ground, water, parks, roads, footpaths, crossings,
  buildings) and one vertex-coloured building mesh, keeping draw calls low;
- creates ground box collision and one `ConcavePolygonShape3D` containing all
  building wall/roof triangles — collision follows the footprint instead of an
  oversized bounding circle;
- never reads a sibling repository path at runtime. The JSON is copied into the
  project by the export step.

Current mesh nodes: `Ground`, `Water`, `Parks`, `Roads`, `Footpaths`,
`Crossings`, `Buildings`, plus `GroundCollision` and `BuildingCollision`.
Tunnel roads are skipped in `_build_roads()`, so no at-grade motorway is drawn
through a building. The pedestrian graph is loaded but not rendered; it is the
future navmesh/agent source.

Building walls use signed-area edge normals, so concave footprints are correct
without a centroid test. Roofs are pre-triangulated before walls are emitted;
malformed footprints are skipped, and the same oriented triangles are used for
the rendered mesh and the single building `ConcavePolygonShape3D`. Building
material uses back-face culling now that winding is dependable.

Road ribbons use shared miter cross-sections through safe bends and bevel joins
at acute bends (miter limit 2.5× half-width). Degree ≥ 3 junctions receive a
bounded patch built from the incident roads' kerb corners, rather than a fixed
circle. Crossings are provisional spaced zebra bars; their paint is shifted onto
road approaches so several junction crossings do not stack into one radial mark.
The source crossing centre and walkable footpath are unchanged.

Stage A has no inner rings, so `flat_polygons()` treats each ring as an
independent filled polygon. It does not support holes yet; a future export with
holes needs an explicit API change before it is drawn.

## 4. Stage A content

From `sydney/world/stage_a/world.json`:

- 1,604 road segments / 98.41 km, 1,427 junctions;
- 6,443 derived pedestrian paths / 120.96 km: 2,082 sidewalk ribbons, 1,132
  crossing paths, 3,229 junction connectors; 1,139 crossing markers;
- pedestrian graph: 6,893 nodes / 11,609 edges, 39 components, 86.2% in the main
  network (the road network is 356 components / 67.7%);
- 930 buildings (18 OSM heights, 756 levels-derived, 156 estimated);
- 281 parks, 16 water rings (harbour), 1,242 landmark points, 129 transit stops;
- 1.29 × 2.55 km around the CBD, Hyde Park, The Rocks, Circular Quay and
  Bennelong Point;
- spawn at George Street / Town Hall, district label “Sydney CBD”.

107 tunnel road segments remain in the data but are not drawn as surface
ribbons; their 2D geometry otherwise put motorway polygons through buildings.

## 5. Tests

```bash
# Export validation (Python)
cd Z:/GITHUB/_EXPERIMENTS/Sydney/sydney-osm-world
python scripts/test_stage_a_export.py

# Read-only geometry audit (Python)
python scripts/audit_stage_a_geometry.py

# Importer + game adapter (Godot, headless)
cd "Z:/GITHUB/_GAMES/New folder"
SPLOOGE_SYDNEY=1 ./Godot_v4.7.2-stable_win64_console.exe --headless --path . \
  --script res://tests/sydney_scene_test.gd --log-file tests/sydney_scene.log

# Geometry builders with synthetic rings/paths (Godot, headless)
./Godot_v4.7.2-stable_win64_console.exe --headless --path . \
  --script res://tests/sydney_geometry_test.gd --log-file tests/sydney_geometry.log

# Existing gameplay regression (unchanged baseline)
./Godot_v4.7.2-stable_win64_console.exe --headless --path . \
  --script res://tests/integration.gd --log-file tests/integration.log

# Rendered capture (windowed)
SPLOOGE_SYDNEY=1 ./Godot_v4.7.2-stable_win64_console.exe --path . \
  --script res://tests/sydney_visual.gd
```

See `docs/SYDNEY_TEST_REPORT.md` for results.

## 6. Regenerating the world

The Sydney repository owns the data. The game only owns the installed copy.

1. Edit `sydney-osm-world/config/sydney.config.json` (`scope.stageA`) if the
   area changes.
2. Run `python scripts/build_stage_a.py --install-to "<game>/sydney/world/stage_a"`.
3. Run `python scripts/test_stage_a_export.py`.
4. Run the Godot importer test.

Do not hand-edit `sydney/world/stage_a/world.json`; it is generated.

## 7. Adding a district

The current export is one Stage A file. To add a district:

1. Add its bbox under `scope` in the Sydney config, keeping the **same origin**.
2. Add a generator mode that emits `export/<district>/world.json` with the same
   format and a `districtId`.
3. Install each export to `sydney/world/<district>/world.json`.
4. Extend `SydneyWorld` to accept a district id and load/unload district nodes;
   keep landmarks persistent.
5. Add the district to the streaming ring (see next section).

All districts must share the origin and projection, or seams will not line up.

## 8. Next-phase architecture

### Streaming and chunks

Stage A is ~2.1 MiB of JSON and one mesh per layer. For Greater Sydney:

- split each district export into 300–500 m chunks (denser in the CBD);
- one `.glb`/`ArrayMesh` per chunk per material class, plus a JSON manifest;
- load a 3×3 chunk ring with `ResourceLoader.load_threaded_request()`;
- free chunks outside two rings; keep the Harbour Bridge and Opera House loaded;
- budget by measurement, not an arbitrary draw-call target.

### Navigation

- **Pedestrians:** bake `NavigationRegion3D` from footpath ribbons, plazas, parks
  and crossings per chunk; stitch at chunk edges. The current derived footpaths
  already form a mostly connected ribbon network at junctions.
- **Vehicle traffic:** build a lane graph from the exported roads. Reuse the
  legacy rules: junction-to-junction runs, 9 m geometric crossing cuts,
  nearest-point-on-polyline handovers, multiple exits, one-way filtering, unique
  run names. Do not use navmesh for cars.
- **Enemies:** `NavigationAgent3D` on the pedestrian mesh, retaining the
  existing line-of-sight attack logic.

### Landmarks

- **Harbour Bridge:** authored asset, aligned to `Bradfield Highway`; vehicle
  deck (6+ lanes), rail corridor, steel arch with hangers, four pylons, approach
  spans, separated pedestrian/cycle path, LOD. Deck and barriers collide; the
  arch does not.
- **Opera House:** authored shell segments on the Bennelong Point podium, with
  forecourt and steps; coarse collision on podium/shells.
- Both are listed in the export under `authoredLandmarksRequired` with real
  coordinates and a `not-modelled` status. OSM cannot supply their structures.

### Terrain

No DEM is present. Before terrain, import a licensed DEM and flatten road
corridors. Until then all geometry is flat at y = 0 and the engine labels that
limitation rather than faking noise.

## 9. Cost and performance

Stage A renders as ~9 mesh nodes (7 visual + 2 collision bodies) rather than
thousands of per-road/per-building nodes. Building walls/roofs are one
vertex-coloured mesh; roads and footpaths are one ribbon mesh each.

Measured in one windowed capture:

| Layer | Vertices | Triangles |
|---|---:|---:|
| Water | 414 | 138 |
| Parks | 3,507 | 1,169 |
| Roads + junction patches | 46,245 | 15,415 |
| Footpaths | 61,302 | 20,434 |
| Crossings | 83,454 | 27,818 |
| Buildings | 52,002 | 17,334 |
| Building collision | — | 17,334 |

World build time was 365.5 ms in the final capture (about 363–377 ms across
repeated captures; Roads 81.7, Footpaths 112.1, Crossings 78.9, Buildings
78.7 ms). No frame-time claim is made here: the rendered capture completed, but
a profiled frame-time measurement on target hardware has not been run.

## 10. Attribution

Data © OpenStreetMap contributors, ODbL 1.0. The installed JSON is a Derivative
Database. Keep attribution in the game credits and do not present invented
geometry (estimated heights, derived footpaths, provisional crossings) as OSM
facts.
