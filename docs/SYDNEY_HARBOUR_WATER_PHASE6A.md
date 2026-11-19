# Sydney Harbour water & coastline — Phase 6A

Implemented and tested in the existing working tree on 2026-11-19. No commit or
push. The harbour now renders as one continuous deep-blue water surface that
follows the real coastline around the southern harbour, from Blackwattle Bay
and Darling Harbour in the west, through Barangaroo, Walsh Bay, Sydney Cove,
Farm Cove and Woolloomooloo Bay, under the Harbour Bridge, and along the
eastern harbour to the Potts Point ridge.

Creative direction note: per the relaxed direction for this phase, OSM is used
as a foundation rather than a restriction. The one harbour area missing from
all pipeline data (Blackwattle Bay) is authored rather than left as a hole;
everything else is real OSM coastline geometry, unsimplified.

## 1. Root cause of the missing water

The water renderer was never broken — `SydneyMesh.flat_polygons()` renders the
export's water rings correctly (parks and the old Sydney Cove patch prove it).
The problem was **data scope**:

1. The Stage A exporter clips every water polygon to the tiny CBD slice
   (lat −33.8790…−33.8560, lon 151.2025…151.2165 — `config/sydney.config.json
   → scope.stageA`) and simplifies the result at 2.5 m. What survives inside
   the slice is 16 rings / 0.22 km²: the coarse 66-vertex Sydney Cove ring
   (ring 7), three Barangaroo slivers cut by the slice's north edge, and 12
   inland ponds.
2. Phase 5 added 0.78 km² of corridor water for the bridge site
   (`harbour_bridge.json → waterRings`), correctly seamed to the slice.
3. Everything else in the brief's scope was outside the slice: Darling
   Harbour, Farm Cove's east half, Woolloomooloo Bay, Pyrmont, Blackwattle
   Bay — the whole western and eastern harbour. Those areas render as the
   flat gray ground box (or void beyond it), which reads as "the harbour has
   no water" from most viewpoints. Measured: the game drew 1.003 km² of water
   against ~4.9 km² of real harbour in the phase scope.

## 2. Data sources and geometry approach

Sources (all read-only):

- `Z:\GITHUB\_EXPERIMENTS\Sydney\sydney-osm-world\data\normalized\waterways.json`
  — the pipeline's normalized water payload, already in the game projection
  (origin −33.873/151.208, 92459.893 m/deg lon, 111019.656 m/deg lat,
  north = −Z; identical to the game's `coordinateSystem`).
  Features used: relation/15522136 **Port Jackson** (the 15,075-point
  harbour multipolygon with 25 inner rings), relation/1252425 Sydney Harbour,
  relation/17064384 Sydney Cove, relation/19541746 Woolloomooloo Bay,
  relation/17039612 Nawi Cove, relation/2310868 (unnamed basin east of the
  Domain).
- `sydney/landmarks/harbour_bridge.json` — the Phase 5 site land rings; the
  harbour water is cut against them so it never covers the bridge site.
- `sydney/world/stage_a/world.json` — bounds (ground box), the old water
  rings (non-harbour ponds preserved), buildings/parks (overlap measured).
- `sydney/landmarks/opera_house.json` — podium ring (overlap measured).

**Authored extension.** Blackwattle Bay is real water but is absent from
every pipeline water feature (checked against the normalized payload, the raw
`overpass-water-areas.json` member ways, and a point-scan of the bay's game
coordinates — the nearest mapped water is the Johnstons Bay arm ending at
Z≈−520). Per the relaxed creative direction it is approximated: a 180,386 m²
bay polygon following the real outline (Pyrmont west shore / Glebe east shore,
~280 m at the mouth narrowing to ~170 m at the Glebe tip), with its mouth
overlapped 60+ m onto the mapped Johnstons Bay arm so the union is seamless.
Rozelle Bay and White Bay remain excluded (Inner West, future phase).

**Scope box** (game metres): X −1400…1700, Z −3300…700. Covers every named
area in the brief (Woolloomooloo Bay ends at X 1624; the authored Blackwattle
west shore reaches X −1265). The north edge equals the Phase 5 bridge site
edge, so no North Shore districts are added. The east edge passes through the
Potts Point ridge land between Woolloomooloo and Elizabeth bays.

**Emission** (`tests/harbour_water_prepare.py` → `sydney/harbour/harbour_water.json`,
deterministic, no timestamps):

- `waterRings` — harbour water polygon exteriors (holes excluded),
  unsimplified, 6 rings / 2,202 vertices / 4.92 km².
- `islandRings` — the water polygon holes (Goat Island 61,253 m² and four
  small islets), emitted as land patches **above** the water plane (y 0.1),
  because a hole-free triangulation would otherwise flood them.
- `pondRings` — the 12 old Stage A water rings that are **not** harbour water
  (ponds/fountains, 6,216 m²), preserved with the legacy look and collision.
- `landRings` — the land collar: scope − water − ground box − bridge land,
  12 parts / 3.05 km², at y 0.0 in the ground colour, so the coastline is
  framed by land everywhere the ground box (bounds ± 150 m) and the bridge
  site end. Water-hole islands are excluded from the collar (they are already
  island patches).
- `collisionRings` — water + island + pond rings for the shoreline barrier.

Measured guarantees baked into the file's `stats`: 0 m² overlap with Stage A
buildings, 0.04 m² with parks, 0 m² with the Opera House podium (1.8 m
clear), 586.8 m² of the old simplified Stage A water not re-covered
(simplification drift, now land), 41.1 m² bridge-water gap (boundary
rounding), and coverage booleans for all 16 named locations.

## 3. The water system

`sydney/harbour/harbour_water.gd` (class `HarbourWater`, a `Node3D`):

- **Surface** — `HarbourWaterSurface`: one mesh, triangles emitted locally
  (the shared `SydneyMesh` builders have no vertex-colour path), winding
  oriented to the up normal, degenerates rejected, at y 0.02 as before.
  Material: `harbour_water.gdshader` — deep blue `#1e5678`, two slow crossing
  wave trains tilting the normal a few degrees (no textures, no scrolling, no
  transparency, no SSR), roughness 0.38 / specular 0.32 for a restrained sun
  glint (tuned down from the first pass, which glittered too broadly), and
  per-vertex brightness variation (±7%, ~100 m and ~270 m sine fields plus a
  slight green shift) for gentle patchiness.
- **Islands** — `HarbourIslands` at y 0.1 in the ground colour.
- **Ponds** — `HarbourPonds` at y 0.02, legacy `2b6f86` flat look.
- **Land collar** — `HarbourLand` at y 0.0 (shared cached ground material,
  coincident-edge joins with the ground box and bridge land, no overlap), plus
  **`HarbourLandCollision`** — a floor collision body (concave shape from the
  same triangulation) because the Stage A ground box stops at bounds ± 150 m;
  without it the player would fall through Pyrmont and the eastern shore.
- **Barrier** — `HarbourWaterCollision`: the Phase 4 mechanism exactly (one
  `StaticBody3D`, one `ConcavePolygonShape3D` with `backface_collision`, one
  vertical quad per ring edge from y 0 to 2.4 m, edges < 5 cm dropped), built
  from the same rings that are rendered. Visual water and the physical
  boundary remain separate systems; water is impassable everywhere it is
  drawn, including the new bays.

**Supersede.** When the module enters the tree it hides the Stage A `Water`
mesh (same plane — both would z-fight), frees the Stage A `WaterCollision`
body (hiding a body does not disable physics; the harbour barrier replaces it
at the real shoreline), and hides the bridge's `HarbourExtension` water mesh
(same plane, its collision is baked into the bridge body and stays). The
Opera House, bridge structure, roads, buildings and ponds are untouched. If
the harbour data file is missing, none of this happens and the Stage A water
remains the whole harbour — the world falls back to the Phase 4/5 behaviour.

## 4. Files changed

New (Phase 6A owned):

- `sydney/harbour/harbour_water.gd` — the harbour water module
- `sydney/harbour/harbour_water.gdshader` — the restrained water shader
- `sydney/harbour/harbour_water.json` — generated geometry + provenance
- `tests/harbour_water_prepare.py` — deterministic generator (Python +
  shapely, pipeline files read-only)
- `tests/harbour_water_test.gd` — 82-check focused suite
- `tests/harbour_water_visual.gd` — the ten windowed captures
- `tests/phase6a_before_*.png` — baseline captures of the pre-fix harbour
- `tests/phase6a_*.png` — post-fix captures
- this document

Modified (smallest isolated change possible; nothing rewritten):

- `sydney/sydney_world.gd` — **additive only**: one `_build_harbour_water()`
  call + timing entry in `_build()` (after the bridge step), and the new
  10-line `_build_harbour_water()` function that preloads the module and adds
  it when its data is present. No existing line changed. This is the only
  integration point; if the integration lead prefers another hook, deleting
  the function and the two call lines reverts the world exactly.
- `tests/sydney_physics_test.gd` — the Phase 4 water section now asserts the
  harbour barrier (`HarbourWater/HarbourWaterCollision`) and the module's
  ring coverage/triangle budget, and `_rings()` prefers the harbour module's
  rings with the export rings as fallback. All behavioural checks are
  unchanged.
- `STATE.md` — phase summary updated.

Untouched: the Stage A export, the OSM pipeline repository, `sydney_mesh.gd`,
shared road/building geometry, the landmarks, the main scene, player,
camera, vehicles, HUD, District Zero.

## 5. Tests and results

| Suite | Checks | Failures | Notes |
|---|---:|---:|---|
| New `harbour_water_test.gd` | 82 | 0 | data integrity, coverage of 16 named locations, determinism, supersede, mesh audit, barrier audit, walk/jump behaviour at Sydney Cove, Darling Harbour and Blackwattle Bay, landmarks intact |
| `sydney_physics_test.gd` (updated water section) | 32 | 0 | Phase 4 behaviour preserved against the new shoreline; player stops 0.35 m from the rendered water edge (Phase 4 measured 1.42 m) |
| `sydney_scene_test.gd` | 23 | 0 | |
| `opera_house_test.gd` | 57 | 0 | |
| `harbour_bridge_test.gd` | 25 | 0 | bridge crossing, driving and shore checks all pass with the harbour module loaded |
| `sydney_playtest_test.gd` (windowed) | 22 | 0 | |
| `sydney_geometry_test.gd` | 107 | 0 | |
| `architecture_test.gd` | 80 | 0 | |
| `architecture_clearance.py` | 29 | 0 | |
| `sydney_scene_test.gd` with the harbour data absent | 23 | 0 | fallback path verified: the world logs one warning per build and renders the Stage A water unchanged |
| District Zero `integration.gd` | 63 | 2 | the two pre-existing baseline failures (`melee damages nearby enemy`, `enemy defeat grants reputation`), unchanged — verified in a clean run without `SPLOOGE_SYDNEY` |

(Exact per-suite figures are from the runs logged in `tests/phase6a_*.log`.)

Highlights from the harbour suite: the player stops **0.35 m** from the
rendered shoreline at all three tested shores (Phase 4 measured 1.42 m);
jumping cannot cross; Pyrmont collar land is walkable (the new floor
collision holds); a rebuild of the module is bit-identical.

## 6. Performance

Single observations (not benchmarks; no FPS claim is made):

- Harbour module build: **38.5 ms** windowed / **36.7 ms** headless.
- Adds **2,190 water triangles** (one draw call), the land collar visual +
  **1,029 land-floor collision triangles**, and a **2,424-edge /
  4,848-triangle shoreline barrier** — two physics bodies total
  (`HarbourWaterCollision`, `HarbourLandCollision`).
- Whole world build incl. the harbour step: 3,043 ms windowed (the Phase 5
  observation was 3,043 ms for less water; build times vary run to run on
  this machine).
- No per-frame cost: all geometry is built once at load; the water shader is
  a handful of ALU per pixel (two sine wave trains, no textures, no SSR).

## 7. Actual Godot launch and captures

The project was launched in windowed Godot 4.7.2 (OpenGL Compatibility, AMD
Radeon RX 6600) with `tests/harbour_water_visual.gd` — exit 0, no errors.
Ten captures were written, opened and inspected (pixel-classification and
ASCII renderings), with `tests/phase6a_before_*.png` kept as the pre-fix
baseline of the same ten viewpoints (taken with the harbour data temporarily
absent, which exercises the fallback path):

| Capture | Viewpoint | Inspection |
|---|---|---|
| `phase6a_quay_east.png` | Circular Quay promenade looking east across Sydney Cove at the Opera House | deep water in the foreground, a restrained sun-sparkle band toward the horizon, the white sails above; no cartoon blue |
| `phase6a_quay_west.png` | same spot looking west along the shore to Barangaroo and Darling Harbour | the former gray strip now reads as harbour shoreline and water to the horizon |
| `phase6a_opera_north.png` | Opera House forecourt looking north across the harbour at the bridge | continuous water from the forecourt seawall to the bridge, no seam at the old Stage A boundary |
| `phase6a_bridge_water.png` | beside the arch looking down at midspan | the harbour fills the view under the bridge with gentle wave shading |
| `phase6a_farm_cove.png` | over the Botanic Garden looking east at Farm Cove | Farm Cove is water to its real shoreline; the gray void east of the old slice edge is gone |
| `phase6a_woolloomooloo.png` | looking east at Woolloomooloo Bay from the Domain | the bay and its shoreline now render (waterish pixels 42% → 62%) |
| `phase6a_darling.png` | high over the CBD west edge looking down at Cockle Bay | Darling Harbour reads as a proper bay narrowing south to Haymarket, CBD skyline behind |
| `phase6a_barangaroo.png` | high over the quay looking north-west along Barangaroo | continuous waterfront from Barangaroo through Walsh Bay toward the corridor |
| `phase6a_aerial.png` | high aerial over the southern harbour | one continuous deep-blue harbour around the bridge, east to the Potts Point ridge |
| `phase6a_aerial_west.png` | aerial over Darling Harbour / Blackwattle Bay | both western bays render with their real shapes (waterish pixels 3.6% → 36.9%) |

Quantitative before/after (sampled pixel classification, "waterish" = blue
hue band with green clearly above red; note the sky shares the band, so the
absolute numbers include sky): aerial 20.8%→44.1%, aerial_west 3.6%→36.9%,
bridge_water 74.7%→76.8% (already water — colour improved), woolloomooloo
42.4%→62.0%, farm_cove 41.7%→49.8%, darling 33.8%→49.1%, barangaroo
32.4%→39.9%. The rendered water reads around RGB (31,104,132) with the
sparkle band near (72,152,178) — deep blue, not the old flat (14,54,74) and
not bright cartoon blue.

Water-on-land check across the same captures: no water over roads, the
promenade, podium surfaces or buildings. The one pre-existing quirk is
unchanged: three unnamed Stage A pedestrian ribbons at the quay overlap the
water polygon by 1,992 m² (2,039 m² overlapped the OLD Stage A water), and
those ribbons render above the water plane as before.

## 8. Remaining limitations

- **Straight scope edges.** The water ends at straight lines mid-water on the
  west (X −1400, in the Johnstons/White Bay arm), north (Z −3300, matching the
  Phase 5 site edge) and east (X 1700, north of the Potts Point ridge). These
  are the documented boundaries of the phase; Rozelle/White Bay, Elizabeth
  and Rushcutters bays, the North Shore and the open harbour beyond the scope
  are future phases.
- **Blackwattle Bay is authored**, not surveyed: the shores follow the real
  bay outline but no parcel boundaries were chased; Rozelle Bay is not drawn.
- **Fort Denison and other small islands** are not holes in the OSM Port
  Jackson polygon, so they are covered by water.
- **Wharves and piers** have no geometry (unchanged from Stage A); the water
  polygon runs beneath them, which is correct when they are built.
- **No swimming, boats or wading** — water remains impassable via the 2.4 m
  invisible barrier (Phase 4 behaviour preserved, now at the real shoreline).
- The land collar is deliberately bare flat land; urbanising Pyrmont, Glebe
  and the eastern shore is future CBD/Inner West work.
- The Stage A `Water` mesh and `WaterCollision` body are still built first
  and then superseded (~1 ms), keeping the fallback path intact.

## 9. Integration instructions

- The only shared-file change is the additive `_build_harbour_water()` step
  in `sydney/sydney_world.gd` (see section 4). It runs after the bridge step,
  preloads `res://sydney/harbour/harbour_water.gd`, adds it when its data is
  present, and records `geometry_counts["HarbourWater"]` and
  `build_times_ms["HarbourWater"]`.
- Regenerate the data after any pipeline water change:
  `python tests/harbour_water_prepare.py` (deterministic; the output diff is
  the geometry change).
- The module supersedes the Stage A water at runtime; to revert the phase,
  remove the two call lines + function from `sydney_world.gd` (or temporarily
  rename `sydney/harbour/harbour_water.json`) — the world falls back to the
  Phase 4/5 water exactly.
- Future CBD/Inner West phases should extend the scope box in the prep
  script and regenerate; the module itself is data-driven and hardcodes no
  geography.
