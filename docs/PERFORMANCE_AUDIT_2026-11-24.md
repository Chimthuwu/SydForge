# Performance Audit — 2026-11-24 (SydForge current tree)

**Scope:** read-only investigation of the working tree at HEAD `7592655` plus the
existing uncommitted WIP files. No gameplay, world or renderer code was changed.
**Method:** the project's bundled Godot 4.7.2 console binary; headless CPU probes,
a windowed Compatibility-renderer GPU probe, and temporary in-code section timers
that were removed after measurement. All temporary probes were deleted.
**Previous audit:** `PERFORMANCE_AUDIT.md` (2026-11-20) and its applied fixes
(§11). This report covers what changed since.

---

## TL;DR

The game is still CPU-bound, but the bottleneck has moved. The 2026-11-20 fixes
(actor LOD, shared audio streams, minimap culling, hidden-mesh removal) are
intact. The new dominant cost is **two linear scans that every AI car performs
on every physics tick**:

| Scan | Index size | Measured cost |
|---|---:|---:|
| `crossings` — `should_slow_for_crossing()` | **9,751** | **~11.4 ms/frame** |
| `junctions` — `is_signal_red_for_position()` | **2,517** | **~2.7 ms/frame** |

At only 15–21 cars that is ~14 ms/frame of pure GDScript loop iterations —
roughly **14 million distance checks per second**. Removing either array drops
frame cost accordingly; the whole measured traffic section budget falls from
14.7 ms to 2.5 ms when crossings are empty.

Two other regressions matter:

* **Startup is now ~39 s** of synchronous main-thread build (was ~13 s).
* **~10,200 `MeshInstance3D` nodes / 3,300 draw calls** in the rendered view;
  daytime renders 35.6 M primitives at ~40 ms/frame on this machine.

The renderer is not the primary bottleneck at current populations, but the
static-geometry node count has grown enough that draw-call batching is now the
clear second priority.

---

## 1. Measurements

All timings use `--fixed-fps 60`, so frames run back-to-back: the numbers are a
CPU-cost proxy, not literal in-game FPS. Run-to-run variance in this environment
is high (see §5); the section timers in §2 are the reliable figures.

| Scenario | Result | Source |
|---|---:|---|
| Headless, 13:00, light rain, fixed camera | **18.14 ms/frame** | `perf_compare.gd`, CPU mode |
| Headless, actors filling (25 cars / 38 peds / 14 wildlife) | **27.76 ms/frame** | `living_world_perf_probe.gd` |
| Headless, frozen population (15–21 cars), instrumented | **~26–29 ms/frame** | temporary section probe |
| Windowed GPU, 13:00, light rain, fixed camera | **40.75 ms**, 3,329 draws, **35.6 M prims** | `perf_compare.gd`, GPU mode |
| Windowed GPU, 22:00, light rain, fixed camera | **34.60 ms**, 3,126 draws, **7.6 M prims** | `perf_compare.gd`, GPU mode |
| Scene `_ready()` (synchronous world build) | **39,320 ms** | temporary startup probe |
| Static audio voices after fill | **3 playing / 93 players** | temporary audio probe |

The 2026-11-20 soak log independently shows `frame=0 time=36721ms`, consistent
with the ~39 s startup measurement.

Reproduce:

```
$env:APPDATA=(Resolve-Path '.runtime').Path
.\Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --path . --script res://tests/perf_compare.gd
$env:SPLOOGE_PERF_GPU='1'; $env:SPLOOGE_PERF_TIME='13'
.\Godot_v4.7.2-stable_win64_console.exe --path . --fixed-fps 60 --script res://tests/perf_compare.gd
```

---

## 2. Root cause: O(n) scans in the AI traffic tick

`VehicleTrafficController._physics_process()` calls, for **every** car on
**every** physics tick:

* `_is_approaching_crossing()` → `TrafficManager.should_slow_for_crossing()`,
  which loops all **9,751** crossings.
* `_check_traffic_signals_and_intersections()` →
  `TrafficManager.is_signal_red_for_position()`, which loops all **2,517**
  junctions.

Both arrays are global city-wide records indexed once in `setup()` from the
export. Neither is spatially indexed or cached per vehicle. At 18 cars and
60 Hz that is ~13 M iterations/second.

Temporary timers were inserted around these calls, the population was frozen
(cap = current count, effectively infinite despawn radius, cars held stationary
so LOD bands could not drift), and three 180-frame windows were measured. The
instrumentation was reverted afterwards.

| Measured section | Full index | `crossings = []` | `junctions = []` |
|---|---:|---:|---:|
| yield check | 0.09 ms | 0.07 ms | 0.08 ms |
| 3 clearance raycasts | 0.02 ms | 0.02 ms | 0.02 ms |
| junction/signal scan | **2.71 ms** | 2.06 ms | **0.02 ms** |
| crossing scan | **11.43 ms** | **0.02 ms** | 10.19 ms |
| `move_and_slide()` | 0.40 ms | 0.32 ms | 0.37 ms |
| **Sum of measured sections** | **14.66 ms** | **2.49 ms** | **10.68 ms** |

Interpretation: the crossing scan accounts for ~11.4 ms/frame and the junction
scan ~2.7 ms/frame. Physics movement and raycasting together are under
0.5 ms/frame — the cost is the GDScript index scans, not collision physics.

Why this appeared after the previous audit: the crossing index has grown from
3,967 to 9,751 with the Stage B road/rail expansion, and the city junction index
is now 2,517. The per-car scan was never made spatial. Actor LOD reduces the
*number of ticks*, not the *cost of each tick*.

**Fix direction (P0):** bucket crossings and junctions into a spatial hash
(e.g. 100 m cells) once in `setup()`, and have each car query only its current
and neighbouring cells. Alternatively, run the scans in `TrafficManager` at a
low rate (2–5 Hz) for all cars in one pass and cache the nearest result per car.
Both preserve behaviour and remove ~14 ms/frame.

---

## 3. Regression: synchronous startup (~39 s)

`scenes/main.tscn` builds the whole world synchronously in `_ready()`. The
CBD world node (`sydney/cbd/cbd_world.gd`) alone contains **12,343 nodes**:

| Sub-tree | Nodes | Meshes | Bodies | Collision shapes |
|---|---:|---:|---:|---:|
| `BusinessPOIs` | 3,175 | 2,781 | 0 | 0 |
| `StationInteriors` | 2,578 | 1,339 | 591 | 591 |
| `RoadTunnelPortals` | 1,646 | 1,316 | 0 | 0 |
| `SydneyRailNetwork` | 1,481 | 174 | 8 | 1,251 |
| `RetailChains` | 949 | 876 | 0 | 0 |
| `NeonCity` | 571 | 512 | 0 | 0 |
| `Supermarkets` | 525 | 460 | 10 | 10 |
| `PetrolStations` | 385 | 306 | 0 | 0 |
| `SydneyCBDLandmarks` | 462 | 324 | 3 | 3 |
| `Roads / Footpaths / Buildings` (merged) | 3 | 3 | 0 | 0 |

The merged road/footpath/building meshes are still efficient — the cost is the
thousands of individual POI, station, portal and neon props, plus the rail and
station collision shapes. The earlier audit measured ~13 s; the current tree
takes ~39 s before the first interactive frame.

**Fix direction (P1):** merge static props into tiled meshes (or `MultiMesh`
where they share geometry), and/or move the build to a worker thread with a
progress screen. Merging also attacks the draw-call count in §4.

---

## 4. Rendering load

The 2026-11-20 audit measured ~1,931 mesh instances at population caps. The
current scene has **~10,200 `MeshInstance3D`** nodes even at low actor counts.
Windowed GPU metrics at 1280×720:

| Time | Frame | Draw calls | Primitives | Lights | Sun shadows |
|---|---:|---:|---:|---:|---|
| 13:00 (day) | 40.75 ms | 3,329 | 35.6 M | 126 | 1 |
| 22:00 (night) | 34.60 ms | 3,126 | 7.6 M | 126 | 0 |

The 6 ms day/night difference is much smaller than the ~28 M primitive
difference, so **primitive count alone is not the driver** — static draw calls
and the CPU cost in §2 dominate. Texture memory is ~90 MB. Vegetation and
streetlights remain correctly multimeshed; the growth is in small static props.

**Fix direction (P2):** tile-merge the static POI/station/portal/neon meshes,
add visibility ranges, then re-measure day and night with `perf_compare.gd`.

---

## 5. Configuration and side findings

* `project.godot` uses `gl_compatibility` with `msaa_3d = 0`; the previous
  audit's 4× MSAA concern is resolved.
* `screen_space_aa = 1` is set but **unavailable on the Compatibility renderer**
  — every run warns "Screen-space AA is only available when using the Forward+
  or Mobile renderer". It has no effect; remove the setting to silence the
  warning (P3).
* The audio fix from the previous audit holds: streams are shared and loops only
  start on audio focus. Only 3 of 93 `AudioStreamPlayer3D` nodes were playing.
* Actor LOD (60/30/15 Hz by distance) is still present and working.
* `tests/perf_compare.gd` GPU mode was **broken**: it assigned the invalid
  properties `SubViewport.render_target_v_flip` and `SubViewport.current`, so
  `_run()` aborted before measuring anything. It now uses a `Camera3D` in the
  real viewport, which is why GPU numbers exist for the first time. This is the
  only source change left in the tree by this audit.
* Variance warning: repeated 180-frame CPU windows drifted by 10–20% even with
  a frozen population. Treat sub-millisecond differences from whole-frame A/B
  windows as noise; the instrumented section totals in §2 are the reliable
  evidence. No GPU trace (RenderDoc) was taken.

---

## 6. Priority summary

| Priority | Action | Expected effect |
|---|---|---|
| P0 | Spatial-index crossings and junctions (§2) | ~14 ms/frame CPU recovered |
| P1 | Thread/stage the world build and merge static props (§3) | ~39 s startup cut, node count reduced |
| P2 | Tile-merge small static meshes, add visibility ranges (§4) | ~3.3k draw calls reduced |
| P3 | Remove no-op `screen_space_aa` setting (§5) | warning removed, no perf change |

Re-run `tests/perf_compare.gd` in both headless and GPU modes after P0/P1 to
confirm the day/night frame time moves. Expected signature: headless CPU drops
from ~18 ms toward ~4 ms at current populations, and the GPU/CPU gap stays
roughly constant since rendering was not changed.

---

## 7. P0 applied — 2026-11-25

Bucketed `junctions`/`crossings` into a 50 m spatial grid in
`TrafficManager._index_junctions_and_crossings()`; `should_slow_for_crossing()`
and `is_signal_red_for_position()` now query only the 3x3 cell neighbourhood
around the car instead of the full city-wide array.

`tests/perf_compare.gd` headless CPU: **18.14 ms → 6.43 ms/frame**. P1/P2
(synchronous startup, draw-call/node count) are still open.

---

## 8. Startup time investigated — 2026-11-25

`tests/cbd_expansion_test.gd`'s `build_times_ms` breakdown (not in the original
§3 measurement) pinpointed the real cost inside the ~36 s world build:

| Step | Before | After |
|---|---:|---:|
| `Buildings` | 15,134 ms | 15,836 ms (unchanged — see below) |
| `RetailChains` | 7,053 ms | **1,908 ms** |
| `Total` | 31,323 ms | 27,432 ms |

**Fixed:** `CbdRetail._nearest_facade()` scanned every one of the 19,429
buildings' every ring edge for each of the 16 retail sites, with no spatial
filter — the real cost behind the `RetailChains` line, not shown in the
original §3 table. Added a cheap one-point distance reject (a building's
footprint is within ~300 m of its own first vertex) before the per-edge scan,
so only nearby buildings pay for it. **−5.4 s**, all 54
`cbd_expansion_test.gd` correctness checks still pass.

**Investigated, not fixed:** `Buildings` (still ~15.8 s) was suspected to be
`SurfaceTool.add_vertex()`/`set_normal()`/`set_color()` call overhead across
the merged mesh's 4.5M vertices. Rewrote `SydneyMesh.buildings()` to batch
into plain arrays and call `add_surface_from_arrays()` once instead — verified
correct (identical vertex/triangle/building counts) but **no measurable
change**. The real cost is the per-building geometry math itself (ring
cleaning, triangulation, per-edge wall-triangle construction) across 19,429
buildings producing 1.5M triangles — i.e. interpreted-GDScript loop overhead
at this scale, not a removable inefficiency. Cutting this further needs one of:
disk-caching the generated static mesh between runs (the city layout is
deterministic from the export file), or moving generation to a background
thread with a loading screen so the ~16 s isn't a frozen window. Scoped as a
follow-up, not attempted here.

`tests/gameplay_regression.gd` stayed at 22/23 across repeated runs in this
session, with a *different* single check flaking each time
(`grind_sustain`, then `landing`, then `node_stability`) — confirms §5's
variance warning: this is run-to-run timing noise in the suite, not a
regression from the traffic/retail changes.

---

## 9. Buildings mesh cache — 2026-11-25

§8's "no removable inefficiency" verdict was wrong about *which* builder is
actually in the hot path: `cbd_expansion_test.gd`'s `Buildings` time is
`CbdWorld._build_buildings()`, which uses the district-aware facade builder
`sydney/cbd/cbd_buildings.gd` (per-building windows, roofs, parapets via
`SurfaceTool`) — **not** `SydneyMesh.buildings()`, the plain-extrusion
fallback the §8 rewrite actually touched. That rewrite was correctness-neutral
but inert for the real game, since `SydneyMesh.buildings()` isn't on
`CbdWorld`'s build path at all.

The facade builder's output is still fully deterministic for a given export
file, so it's now cached to disk instead: `CbdWorld._build_buildings()` saves
the built mesh/night-windows mesh/collision shape/stats as a
`CbdBuildingCacheData` resource (`sydney/cbd/cbd_building_cache.gd`) under
`user://cache/`, keyed by a hash of the export JSON text plus a cache-format
version constant. A later launch with the same city data loads the resource
instead of rebuilding it.

| Run | `Buildings` | `Total` build | `WORLD LOAD` |
|---|---:|---:|---:|
| Cold (builds + saves cache) | 15,628 ms | 26,566 ms | 30,634 ms |
| Warm (loads cache) | **6,151 ms** | 16,363 ms | **20,487 ms** |

All 54 `cbd_expansion_test.gd` checks and 23/23 `gameplay_regression.gd`
pass on both cold and warm runs. The remaining 6.2 s on a warm load is the
engine's own cost to deserialize/upload a ~1.5M-triangle mesh resource — not
investigated further here.

Same technique applies directly to `Roads` (now the largest uninvestigated
line, ~4.7 s) if more startup time is wanted later: `SydneyMesh.road_mesh()`
is deterministic from the same export file, so the same cache pattern would
work with the same key.

---

## 10. Roads mesh cache — 2026-11-25

Applied the §9 pattern to `_build_roads()`: `SydneyWorld` now caches the
surface ribbon and both tunnel meshes (`sydney/road_mesh_cache.gd`,
`RoadMeshCacheData`), and `CbdWorld` separately caches its lane-marking and
kerb meshes (`sydney/cbd/cbd_road_dressing_cache.gd`,
`CbdRoadDressingCacheData`) — both keyed the same way as the buildings cache.
Tunnel portal frames (cheap node-tree construction, not mesh generation) are
still rebuilt every run.

| Run | `Roads` | `Buildings` | `Total` build | `WORLD LOAD` |
|---|---:|---:|---:|---:|
| Cold (builds + saves both caches) | 4,506 ms | 15,069 ms | 25,531 ms | 29,689 ms |
| Warm (loads both caches) | **180 ms** | 6,212 ms | **12,347 ms** | **16,343 ms** |

All 54 `cbd_expansion_test.gd` checks pass on both runs.
`gameplay_regression.gd` held at 22/23 (`node_stability` flaked — the same
run-to-run variance noted in §5/§8, not a regression).

**Net effect across §9+§10, cold vs. a previously-uncached §3 baseline run
(~36 s) vs. a fully-warm run: world load is now ~16.3 s, down from ~36 s —
more than 2x.** Remaining candidates for the same treatment, in order of
size: `Footpaths` (~0.8 s), `Crossings` (~0.6 s) — both small enough now that
the §3/§4 node-count and draw-call items (still untouched) are the better
next targets if more is wanted.
