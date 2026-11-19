# Performance Audit — Splooge / Sydney CBD

**Date:** 2026-11-20
**Scope:** investigation was read-only; the fixes listed in §11 were applied afterwards.
**Question:** why does the game get laggy?

---

## TL;DR

The game is **CPU-bound before it is GPU-bound**, and the cost is dominated by
the *ecosystem actors* (AI traffic, pedestrians, wildlife), not by the city
geometry.

Measured on the canonical scene (`scenes/main.tscn` → `scripts/sydney_cbd_district.gd`)
in a headless Godot 4.7.2 process, with **no rendering at all**:

| Scenario | CPU ms / frame | implied ceiling |
|---|---:|---:|
| Full caps (40 cars, 50 peds, 40 wildlife) | **25.9 ms** | **~38 FPS** |
| Same actors, managers + bodies disabled | 7.6 ms | ~131 FPS |
| Actors removed entirely | **7.2 ms** | ~139 FPS |

So at population caps the simulation alone already misses a 60 FPS budget
(16.7 ms) with the renderer contributing **zero**. Add 1,931 draw calls,
2.2 M triangles, 105 visible dynamic lights and 132 audio voices, and a normal
machine ends up well below 60.

The five costs that matter, in order:

1. **Per-body simulation cost.** Each AI car / pedestrian / bird is a
   `CharacterBody3D` running `move_and_slide()` at 60 Hz. Measured 0.13 ms
   (car), 0.20 ms (ped), 0.26 ms (bird) each. 130 bodies ≈ 18–25 ms/frame.
2. **Spawn hitches from procedural vehicle construction.** Every new AI car
   costs **~50 ms** (visual tree + three 1-second audio loops baked in GDScript
   + 16-bit encoding). The manager spawns up to **3 per second**, i.e. a
   **~150 ms freeze every second** while traffic fills up (~14 s).
3. **Minimap redraw.** `MiniMap._draw()` walks all **5,154 roads / 28,589
   points** every 0.12 s with no spatial culling: **~27 ms per redraw, ~8×/s
   (~225 ms of CPU per second)** in 27 ms spikes.
4. **Draw-call explosion from hand-built actors.** At caps: **1,931
   MeshInstance3D with 1,931 unique meshes** — every car, pedestrian and bird
   is 10–12 separate primitives, each its own mesh resource. That is ~1,931
   draw calls, roughly doubled by the shadow pass.
5. **Always-on audio mix.** 3 looping `AudioStreamPlayer3D` per car start on
   frame one at −80 dB and **never stop**: 132 playing voices at caps even
   though only 6 cars are meant to be audible.

The city build itself is efficient at runtime (merged meshes, 2 draw calls for
19,600 trees, 18 streetlight spot lights) — but it costs **15.3 s of frozen
startup**, of which **10.1 s is the 9,000-building facade generator**.

---

## 1. What was measured, and how

All numbers below come from temporary headless probes that loaded the real
`scenes/main.tscn`, let it build, and read live timings/counters. The probes
were deleted afterwards. Commands used the project's own binary:

```
Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --path . --script <probe>
```

Because headless mode stubs the renderer:

* **CPU numbers are real** (GDScript, physics server, audio server graph build).
* **GPU numbers are inferred** from submitted geometry, instance counts, light
  counts and material/mesh fragmentation. No GPU profiler run was possible
  here.
* Existing project docs confirm no frame-time/GPU profiling had ever been done,
  so this audit supplies the missing runtime evidence.

One caveat on the frame timings: `--fixed-fps 60` runs frames back-to-back, so
wall-clock per frame is a fair CPU-cost proxy, not a literal in-game FPS.

---

## 2. Startup: a 15.3 s synchronous freeze

`load_world()` and the whole Stage B build run synchronously inside `_ready()`.
Measured:

```
TOTAL_SCENE_READY_MS 15268
```

The world's own `build_times_ms` (sum 12,417 ms) breaks down as:

| Stage | ms | Share |
|---|---:|---:|
| **Buildings** (9,000 rows → 8,988 built) | **10,136** | **81.7 %** |
| Footpaths (27,800 paths) | 655 | 5.3 % |
| Roads (5,154) | 388 | 3.1 % |
| Crossings (3,967) | 367 | 3.0 % |
| Harbour Bridge | 367 | 3.0 % |
| Rail network | 186 | 1.5 % |
| Landmarks | 140 | 1.1 % |
| Parks | 76 | 0.6 % |
| Harbour water | 48 | 0.4 % |
| CBD landmarks | 45 | 0.4 % |
| Water / water collision / ground | 9 | 0.1 % |
| **World subtotal** | **12,417** | |
| Player + 4 cars + HUD + managers + streetlight generation + physics setup | ~2,850 | |

Within buildings, cost is spread fairly evenly (≈1.1 ms per building): 2.49 M
vertices and 830 k triangles are assembled in GDScript `SurfaceTool`s, a second
hidden "night windows" mesh of **423,699 quads (847,398 triangles)** is built and
then made invisible, and an **830,289-triangle concave collision shape** is
converted and handed to the physics server.

Consequences:

* First launch looks like a hang. There is no loading screen or staged build.
* Roughly **711 MB** of static memory is already allocated right after the
  scene's first frame (before ecosystems fill).
* The hidden `NightWindows` mesh costs build time and memory for nothing — the
  facade shader replaced it (the code says so explicitly).
* The merged 830 k-tri building mesh defeats per-building frustum culling later
  (see §5).

---

## 3. Per-frame CPU cost

### 3.1 Whole-frame measurements

| Population | CPU ms/frame | Without managers | Without actors |
|---|---:|---:|---:|
| 17 cars / 22 peds / 6 wildlife | 20.7 | 8.3 | 7.35 |
| 40 / 50 / 40 (caps) | **25.9** | 7.6 | **7.2** |

The baseline 7.2 ms is the city + player + camera + HUD + 4 parked cars. The
ecosystem adds **~18.3 ms/frame at caps** — 71 % of the CPU frame, before
rendering.

### 3.2 Per-body cost

Measured by toggling individual bodies:

| Actor type | ms per body per physics tick | Count at cap | subtotal |
|---|---:|---:|---:|
| AI traffic (`VehicleTrafficController`) | 0.130 | 40 | 5.2 ms |
| Pedestrian (`PedestrianController`) | 0.204 | 50 | 10.2 ms |
| Wildlife (`WildlifeController`, ibis) | 0.259 | 40 | 10.4 ms |
| **Total** | | **130** | **~25.8 ms** |

These are *marginal* costs measured by toggling each population on its own.
Adding them up predicts ~25.8 ms, which is close to the measured 25.9 ms cap
frame; the whole-scene differential (25.9 − 7.6 = 18.3 ms) is smaller because
shared costs (broadphase, physics step, per-frame bookkeeping) overlap and do
not scale perfectly linearly. Treat the per-body numbers as upper bounds on
what each actor type contributes, not as an exact ledger. The important part:
the cost is **linear in actor count** and each actor is individually expensive
because each one is a full `CharacterBody3D` with `move_and_slide()`, gravity,
animation node churn, and per-frame state.

Wildlife is the worst per body despite being the smallest animal, because the
ibis is a physics body and its `_physics_process` runs a state machine plus
`move_and_slide()`; the flying-fox swarm (no physics body) is cheap.

### 3.3 Spawn cost (the hitch generator)

| Spawn call | ms | Bodies created | ms per body |
|---|---:|---:|---:|
| `TrafficManager._spawn_traffic_near_player()` | **143–150** | 3 | **~48–50** |
| `PedestrianManager._spawn_pedestrians_near_player()` | 5.7–6.2 | 4 | ~1.4 |
| `WildlifeManager._spawn_wildlife_near_player()` | ~0.6 | 1 | ~0.6 |

Traffic is the outlier by 30×. One vehicle builds 10 unique meshes/materials,
4 `AudioStreamPlayer3D`s, 2 lights, and bakes **four 22,050-sample audio streams
in GDScript** (engine, tyre, road, horn) including `tanh` synthesis and
`data.encode_s16()` per sample.

With `spawns_to_attempt = mini(3, …)` every second, traffic fill produces a
**~150 ms stall once per second for ~14 seconds**, then a 150 ms stall whenever
enough cars despawn to allow a refill. This is the classic "the game stutters
for the first half-minute, then settles".

### 3.4 Per-frame script work in the HUD (`scripts/district.gd`)

| Work | Frequency | Cost |
|---|---|---:|
| `MiniMap._draw()` over all 5,154 roads / 28,589 points | every 0.12 s | **27 ms** per redraw (≈225 ms/s) |
| `find_nearest_vehicle()` (group fetch + distance checks) | every frame | small, but allocates a `get_nodes_in_group` array each frame |
| `hud.text` / `status.text` / `hint.text` rewritten | every frame | Label re-shaping/relayout each frame |
| Health bar / reload bar updates | every frame | small |

The minimap is the single biggest script spike in the game that is not an
actor. It computes screen coordinates for **every point in the entire Stage B
road network**, then discards all but ~69 segments with a radius test. Drawing
168×176 px of map costs 27 ms of GDScript.

### 3.5 Manager-level scans

| Work | Frequency | Cost |
|---|---|---:|
| Traffic: scan 5,154 roads for spawn candidates + cull list | 1 s | ~4.4 ms |
| Pedestrian: scan node list (27,249 nodes, early-break at 30 candidates) | 1 s | not isolated; worst case a full 27 k walk when the player is in a sparse area (the Harbour Bridge spawn is sparse) |
| City lights: 3,364 street records → 18 active spots | 0.25 s | 0.8 ms |
| City lights: landmark materials | 0.25 s | 0.05 ms |
| Traffic audio focus sort | 1 s | 0.10 ms |

### 3.6 The dusk/dawn lighting storm

`WorldTimeManager` emits `lighting_factor_changed` whenever the factor changes
by >0.0001. Time advances every frame, so **during dawn and dusk this fires
every frame**.

Each emission runs:

* `CityLightsManager._apply_lighting_factor()` — measured **1.28 ms at caps**
  (it also re-runs the nearby-streetlight and landmark updates);
* one callback per AI vehicle, each updating 2 lights + headlight/taillight
  materials.

Net: **~1.3 ms + ~40 callbacks per frame** for the duration of the transition.
It is not the main cost, but it is a reliable extra frame-time bump at exactly
the times of day the game looks best and players stop to look around.

The cycle is fast: `day_length_seconds = 1800`, so one in-game hour is 75 real
seconds and the 1.5-hour dusk window lasts **~112 real seconds**. That is a
~2-minute per-frame lighting storm every 30 minutes of play, plus the same at
dawn.

---

## 4. Rendering: the city is cheap, the actors are not

### 4.1 Geometry submitted (measured)

| Mesh | Triangles | Notes |
|---|---:|---|
| Buildings (merged) | **830,289** | one mesh, always submitted |
| Night windows (hidden) | 847,398 | allocated, invisible, wasted |
| Crossings | 97,918 | merged |
| Footpaths | 86,424 | merged |
| Harbour Bridge | 69,918 | 18,620 collision tris |
| Roads | 49,780 | merged |
| Rail sleepers + steel | 64,800 | merged |
| Opera House | 13,132 | |
| Trees (19,600 multimesh instances) | ~870,000 (residual of the world total) | 2 multimesh nodes (excellent) |
| Streetlights (3,364 records) | poles + heads in 2 multimeshes | 2 multimesh nodes (excellent) |
| **Whole scene (mid-fill sample)** | **2.23 M** | |

Two structural problems:

1. **Merged meshes can't be frustum-culled per building.** Godot culls per
   `MeshInstance3D`. The entire 830 k-triangle building shell is drawn whenever
   any part of the city is on screen. Looking at one wall still submits the
   whole CBD, and the shadow pass submits it again. The merge saved draw calls
   at the cost of always drawing everything.
2. **No LOD or occlusion culling anywhere.** Grep of `*.gd`/`*.tscn` found no
   `visibility_range`, `OccluderInstance3D`, or mesh LOD usage. At `camera.far =
   2800` and sun `directional_shadow_max_distance = 320`, distant geometry and
   shadow casters are always in play.

### 4.2 Draw calls are the real GPU problem

At caps, measured live scene contents:

| Counter | Value |
|---|---:|
| Nodes | 3,274 |
| `MeshInstance3D` | **1,931** |
| Distinct mesh resources | **1,931** |
| Distinct materials | 722 |
| `Label3D` | 26 |
| `CharacterBody3D` | 136 |
| Lights | 142 (105 visible) — 86 spot, 55 omni |
| `AudioStreamPlayer3D` | 180 (132 playing) |

**Every mesh instance owns its own mesh** — `Art.box()` / `Art.cylinder()` call
`BoxMesh.new()` / `CylinderMesh.new()` per primitive, and the vehicle builder
does the same for wheels. Nothing is shared, instanced or merged, so:

* ~1,931 opaque draw calls per camera pass,
* roughly doubled by the sun shadow pass (most primitives cast shadows by
  default),
* 26 `Label3D`s (bus destination blinds, "TAXI", "CITY OF SYDNEY WASTE
  SERVICES") each with its own text mesh and transparent material.

A pedestrian is only 276 triangles but costs **12 draw calls**. Traffic is 3,144
triangles for **10 draw calls + 2 lights + 3 audio voices + 1 horn**. The city
is ~2 M triangles for a few dozen draw calls; the 130 actors are ~1,400+ draw
calls. That inversion is why the scene gets heavy as traffic fills.

At mid-fill the audit sample had 952 mesh instances; at caps it is 1,931. This
matches the player experience: **the game gets worse the longer you play**, then
plateaus.

### 4.3 Lights

* The game **opens at 21:00** (`current_time_hours = 21.0`), so night is the
  default experience, not an edge case.
* 40 AI cars × (1 spot + 1 omni) = 80 vehicle lights, visible only within
  110 m/65 m at night, plus 18 streetlight spots, 24 landmark lights and the
  player's lights → **105 visible lights at cap** (measured at the default
  21:00 start). In daylight the vehicle lights hide and the count falls to
  roughly the streetlight/landmark total, so day is meaningfully cheaper than
  night.
* `gl_compatibility` uses forward per-object lighting; every extra light
  increases shader cost and permutations on every affected surface. Dense
  traffic at night stacks many overlapping 28 m spots.
* Lights are shadowless (`shadow_enabled = false`), which is the right call.

### 4.4 Renderer settings

From `project.godot` and the scene:

* `renderer/rendering_method = "gl_compatibility"`
* `msaa_3d = 2` — in Godot 4 that is **4× MSAA**, not 2× (0 = off, 1 = 2×,
  2 = 4×, 3 = 8×); it multiplies bandwidth and resolve cost
* 1280×720 base, `canvas_items` stretch (higher window sizes scale cost)
* `camera.far = 2800`, near 0.2 m
* depth fog enabled (`fog_density 0.0011`) — cheap, but adds full-screen
  shading
* sun shadows to 320 m, bias 0.04
* two large procedural fragment shaders: `facade.gdshader` (per-pixel windows,
  frames, sills, hashes, glass, lit windows over the entire 830 k-tri building
  mesh) and `asphalt.gdshader` (aggregate noise over roads). Both are opaque and
  well written, but they are evaluated over a *lot* of always-submitted
  geometry.

The facade shader is doing the work of millions of window triangles, which is a
good trade — until that single merged mesh is always drawn and always shaded.

---

## 5. Audio: 132 voices, most of them inaudible

Per AI vehicle (`scripts/engine_audio.gd`):

* At `_ready`, **four** streams are baked procedurally at 22,050 Hz: engine,
  tyre and road loops (1 s each) plus a 0.55 s horn.
* `engine.play()`, `tyre.play()`, `road.play()` are called immediately at
  **−80 dB**, and are **never stopped**. `set_audible(false)` only fades volume.
* `update_audio()` runs every physics tick per car; when inaudible it still
  writes three `volume_db` properties every frame.

Measured at caps: **180 `AudioStreamPlayer3D`, 132 playing**. That is 120
looping car voices, nearly all silent, plus player and world sounds. Cost per
voice is small on desktop, but it is pure waste and it scales with the traffic
cap. It also means a fully populated street keeps an audio thread busy mixing
silence.

The spawn-time bake is the expensive half: ~50 ms per car, and it is the main
contributor to the traffic spawn hitch in §3.3.

---

## 6. Why it feels the way it does

| Symptom | Cause (measured) |
|---|---|
| Long freeze on launch | 15.3 s synchronous build; 10.1 s in buildings |
| Stutter every second for the first ~15 s | 3 cars/s × 50 ms = 150 ms stall/s while traffic fills |
| Stutter returns after driving around | despawn/refill cycles at 300 m produce the same 150 ms spike |
| Frame rate drops the longer you play | actor count climbs to caps; actors cost 18 ms CPU and ~1,400 draw calls |
| Frame rate is poor even standing still | 25.9 ms CPU at caps + always-submitted 830 k-tri city mesh + 4× MSAA |
| Worse at night | 105 visible lights, 40 cars' lights, lighting-factor callbacks (and night is the default start) |
| Worse at dusk/dawn | `lighting_factor_changed` fires every frame (1.3 ms + 40 callbacks) |
| Periodic 20–30 ms hitch while walking | minimap redraw (27 ms) 8×/s |
| Worse on integrated GPUs | 1,931 draw calls, 2.2 M tris, 4× MSAA, Compatibility renderer |
| Audio cost scales with traffic | 132 mixed voices, 120 of them silent loops |

One more contributing detail: `WildlifeController.setup()` calls
`_build_visuals()` a second time even though `_ready()` already built them, so
every bird spawn builds its visual tree twice (the first copy is `queue_free`d).
That is a measurable slice of the 0.6 ms wildlife spawn cost, and it leaves dead
nodes pending deletion in the same frame.

---

## 7. Ranked root causes

| # | Cause | Evidence | Share of the problem |
|---|---|---|---|
| **1** | 130 `CharacterBody3D`s simulated at 60 Hz | 25.9 ms cap frame vs 7.2 ms without actors; 0.13–0.26 ms/body | ~70 % of CPU frame |
| **2** | 1,931 unique meshes → ~1,900–3,800 draw calls; no LOD/occlusion | live scene counters at caps; no `visibility_range`/occluders in project | main GPU cost |
| **3** | 50 ms per AI car spawn, 3/s | 143–150 ms per spawn call | 150 ms stall/s during fill |
| **4** | Minimap scans the whole road network 8×/s | 27 ms per `_draw`, 5,154 roads / 28,589 points | ~225 ms/s in spikes |
| **5** | Always-submitted merged 830 k-tri building mesh + facade shader | one mesh, 830,289 tris, no culling | constant GPU floor |
| **6** | 132 audio voices, 120 silent loops | 180 players / 132 playing at caps | audio thread + memory, plus spawn bake |
| **7** | 105 dynamic lights at night | 86 spot / 55 omni, 105 visible | night-time GPU cost |
| **8** | Per-frame HUD text + nearest-vehicle scan | every frame in `district.gd` | small but constant |
| **9** | 15.3 s synchronous startup, 711 MB static | build timings | first-run UX, not lag |
| **10** | Dusk/dawn lighting callback storm | every-frame signal, 1.28 ms + 40 callbacks | seasonal spike |

Note the ordering: **physics/actor cost is the ceiling; draw calls are the
visual-cost multiplier.** Fixing only rendering will leave the game unable to
hold 60 FPS on the CPU; fixing only the actors will still leave a heavy GPU
frame.

---

## 8. What is *not* the bottleneck (don't waste effort here)

* **Vegetation.** 19,600 tree instances in **2 multimesh nodes** — ~2 draw
  calls. Correctly done.
* **Streetlights.** 3,364 records are culled down to **18 active spot lights**;
  the poles/heads are 2 multimeshes. Cheap.
* **Roads / footpaths / crossings meshes.** Merged into 3 draws; the geometry
  is fine.
* **Facade/water/asphalt shaders by themselves.** Opaque, no transparency, no
  screen-texture reads. The cost is the amount of surface they cover, not the
  shader logic.
* **Traffic manager scans.** 4.4 ms/s is noise next to the 150 ms spawn stall.
* **Audio focus sort.** 0.10 ms/s.
* **Landmark lights.** 0.05 ms per update.

---

## 9. Remediation options (ranked; what was actually implemented is in §11)

Ordered by impact per unit of risk. These are options, not recommendations to
apply blindly.

### Tier 1 — biggest wins, contained changes

1. **Make actor simulation cheap or sparse.**
   * Replace `CharacterBody3D` + `move_and_slide()` for background actors with
     kinematic/`Node3D` movement (no physics body) and only promote the nearest
     few to real bodies. Cars on splines and pedestrians on a graph do not need
     full character physics.
   * Or run actor AI at 20–30 Hz with interpolation, halving or thirding the
     tick cost.
   * Expected: the 18 ms ecosystem CPU cost is the largest single lever;
     removing physics from 100+ actors could recover 10–15 ms/frame.

2. **Stop building a full 3D actor per spawn.**
   * Bake one `ArrayMesh` per vehicle class / pedestrian / bird and instance
     it (or use `MultiMesh` for distant actors), sharing materials.
   * Move audio baking out of `EngineAudio._ready()`: bake once at startup into
     shared `AudioStreamWAV` resources, or generate them offline.
   * Expected: spawn drops from ~50 ms to a few ms; draw calls drop by roughly
     an order of magnitude at caps.

3. **Throttle traffic spawning.**
   * Cap spawns to one per second (or amortize construction across frames) so
     the fill never produces a 150 ms stall.
   * Expected: removes the once-per-second freeze with a trivial change.

4. **Fix the minimap.**
   * Cull roads once per player cell (spatial index / bucket by 100 m grid) and
     only transform the ~50 visible segments; cache the projected polyline and
     redraw only on player movement or at 2–4 Hz.
   * Expected: 27 ms → <0.5 ms; removes the 8×/s hitch.

### Tier 2 — rendering structure

5. **Chunk the merged city for culling.** Split buildings/roads/footpaths into
   spatial tiles (e.g. 250 m) so frustum culling works, or add
   `OccluderInstance3D` for major blocks. Keep the merge *within* a tile.
6. **Add LOD / visibility ranges** for actors and city props; at 2.8 km far
   plane almost nothing needs full detail.
7. **Review MSAA and shadows.** 4× MSAA over a full-screen facade shader is
   expensive on integrated GPUs; 320 m shadow distance with ~2,000 casters may
   not pay for itself. Measure before changing.
8. **Delete the hidden `NightWindows` mesh** (847 k tris of build time and
   memory) if the facade shader is the accepted look.

### Tier 3 — housekeeping

9. Stop silent audio loops (don't `play()`, or `stop()` when faded below a
   threshold); reuse streams across cars.
10. Update HUD labels only when their values change.
11. Emit `lighting_factor_changed` at a fixed low rate (e.g. 4–10 Hz) instead
    of on every 0.0001 change; update vehicle lights inside the city-lights
    manager once per tick instead of via per-vehicle signals.
12. Move world build to a thread + progress screen, or accept a one-time cost
    but show that it is happening.

---

## 10. How to confirm on real hardware

Suggested follow-up (not done here):

1. Run the game windowed with Godot's **Debugger → Profiler** and capture:
   * `Performance.TIME_PROCESS`, `TIME_PHYSICS_PROCESS`,
   * `RENDER_TOTAL_DRAW_CALLS_IN_FRAME`,
   * `RENDER_TOTAL_PRIMITIVES_IN_FRAME`.
   At spawn, after 30 s, at night, and while looking at the skyline.
2. Use **Monitors → Physics 3D** active bodies/pairs and **Audio → voices**.
3. Capture a GPU trace (RenderDoc) of one skyline frame to separate draw-call
   overhead from fragment cost.
4. Re-run the population scaling test: 10/10/10, 20/25/20, 40/50/40 and plot
   frame time. The linear slope is the actor cost; the intercept is the city.

Expected signature if this audit is right: frame time scales with actor count,
draw calls track actor count, and CPU time exceeds GPU time at caps.

---

## Appendix — raw measurements

```
TOTAL_SCENE_READY_MS            15268
BUILD_TIMES                    Buildings 10136.108, Footpaths 655.371, Roads 388.377,
                               Crossings 366.607, HarbourBridge 366.566, Rail 185.868,
                               Landmarks 140.44, Parks 76.21, HarbourWater 48.039,
                               CBDLandmarks 44.718, Water 4.059, WaterCollision 3.537,
                               Ground 1.125, Total 12417.043
MEM_STATIC (after first frame) 711,548,149 bytes
GEOMETRY                       Buildings 830,289 tris / 2,490,867 verts / 423,699 window quads
                               Footpaths 86,424 tris; Crossings 97,918; Roads 49,780;
                               Bridge 69,918; Opera 13,132; Vegetation 9,800 trees
FRAME 17/22/6                  20.7 ms   (managers off 8.3; actors off 7.35)
FRAME 40/50/40                 25.95 ms  (managers+bodies off 7.64; actors freed 7.18)
SPAWN traffic                  143.3 / 139.9 / 150.1 ms per 3-car call
SPAWN pedestrian               5.65 / 6.15 / 5.73 ms per 4-ped call
SPAWN wildlife                 2.37 ms per 4 calls
CAP SCENE                      3,274 nodes; 1,931 MeshInstance3D; 1,931 unique meshes;
                               722 materials; 136 CharacterBody3D; 26 Label3D;
                               142 lights (105 visible, 86 spot / 55 omni);
                               180 AudioStreamPlayer3D (132 playing)
LIGHTING apply                 1.283 ms; nearby streetlights 0.800 ms; landmarks 0.053 ms
AUDIO focus                    0.104 ms
MINIMAP draw                   80.7 ms / 3 iterations ≈ 27 ms per redraw @ 8.3 Hz
```

---

## 11. Fixes applied after the audit

All changes are CPU-side and behaviour-preserving; no art, scene, MSAA or shadow
setting was touched. Verified in the same headless setup (`--fixed-fps 60`).

### 11.1 What changed

| # | Area | Change | File |
|---|---|---|---|
| 1 | Actors | Distance LOD for AI traffic: 60 Hz within 40 m, 30 Hz to 90 m, 15 Hz beyond. Velocity is scaled by the accumulated step so speed is unchanged. | `sydney/ecosystem/vehicle_traffic_controller.gd` |
| 2 | Actors | Same LOD for pedestrians (30/70 m) and wildlife (25/60 m), with speed-correct integration. | `sydney/ecosystem/pedestrian_controller.gd`, `sydney/ecosystem/wildlife_controller.gd` |
| 3 | Audio | Streams are baked once into a static cache and shared by every vehicle instead of re-synthesised per spawn (~50 ms each). | `scripts/engine_audio.gd` |
| 4 | Audio | Engine/tyre/road loops start only when the vehicle is audible and stop after the fade; horn timing no longer depends on the audible branch. | `scripts/engine_audio.gd` |
| 5 | Audio | AI engine updates at 10 Hz (full rate while player-driven). | `sydney/ecosystem/vehicle_traffic_controller.gd` |
| 6 | Minimap | Per-road `Rect2` bounds cache, rebuilt only when the road array changes; roads outside the 340 m map window are skipped before any point is transformed. | `scripts/district.gd` |
| 7 | HUD | Labels are only re-assigned when their text changes. | `scripts/district.gd` |
| 8 | HUD | Nearest-vehicle scan throttled from every frame to 10 Hz. | `scripts/district.gd` |
| 9 | Lighting | `lighting_factor_changed` emission capped at 10 Hz (still forced on `_ready`/`set_time`). Sun/sky still update every frame. | `sydney/ecosystem/world_time_manager.gd` |
| 10 | Startup | Stopped generating the always-invisible `NightWindows` mesh (423,699 quads / 847,398 tris). | `sydney/cbd/cbd_buildings.gd` |
| 11 | Wildlife | `setup()` no longer frees and rebuilds the visual tree when the species is unchanged. | `sydney/ecosystem/wildlife_controller.gd` |

### 11.2 Measured result (headless, CPU only)

| Metric | Before | After |
|---|---:|---:|
| Full caps frame (40/50/40) | **25.95 ms** | **6.2 – 7.6 ms** |
| Scene startup (`main.tscn` ready) | 15,268 ms | 12,950 ms |
| — Buildings build | 10,136 ms | 8,123 ms |
| `NightWindows` node | 847,398 tris | not created |
| Minimap: roads / points transformed per redraw | 5,154 / 28,589 | 29 / 307 |
| Minimap: transform cost per redraw (replicated loop) | 20 – 25 ms | 1.0 – 1.2 ms |
| Playing `AudioStreamPlayer3D` at caps | 132 | **0** (180 players exist, silent) |
| Traffic spawn, warm (3 cars) | 143 – 150 ms | ~36 ms (~12 ms/car) |
| Traffic spawn, first call (cold stream bake) | 143 ms | ~70 ms |

Component budget at caps in one run: 6.84 ms total, of which traffic 0.37 ms,
pedestrians 1.65 ms, wildlife 3.56 ms, everything else 1.26 ms.

LOD band sample at caps: 34 of 40 cars beyond 90 m (15 Hz), 6 at 30 Hz, 0 at full
rate; 48 of 50 pedestrians beyond 70 m.

### 11.3 Behaviour checks

* Normal 900-frame run with no probe: no script errors, parse errors or warnings.
* Cars: `enter()` works, engine loops start on audio focus (3 voices), `honk()`
  plays and stops after 0.55 s, `exit_vehicle()` releases the car and the loops
  fade out and stop.
* Movement over 60 frames: car 7.6 m while accelerating 0 → 14 m/s (correct),
  pedestrian 1.8 m at 1.4 m/s, bird ~2.1 m. LOD did not scale speeds.
* Minimap still draws the same roads near the player (29 roads / 307 points in
  the sampled view), so the cull only removes off-screen geometry.

### 11.4 Still open (deliberately not changed)

* 1,918 MeshInstance3D / ~1,931 draw calls: batching actors into per-class meshes
  or `MultiMesh` is the remaining rendering cost.
* MSAA 4× and 320 m shadow distance: measurable GPU cost, but changing them
  alters image quality, so they were left alone.
* Startup is still ~13 s of frozen main-thread build; threading the build or a
  progress screen is the next startup fix.
* Traffic still spawns in bursts; amortising construction across frames would
  remove the remaining ~70 ms first-call and ~36 ms later hitches.

