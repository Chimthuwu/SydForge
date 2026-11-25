# SydForge TODO

## Critical / player-facing bugs

- [x] **Roads over the open rail cutting had no deck.** The cutting removes the ground slab; road ribbons crossed the gap and a vehicle fell ~6 m to the cutting floor. `CbdWorld._build_rail_cut_road_decks()` now builds an aligned visual slab and collision box at every road/cut centreline crossing (14 in Stage B, deduplicated). Regression: `tests/rail_cut_road_collision_test.gd` 5/0 (14/14 rays at street level, 3/3 car drops land); full rail suite 2350/0.

- [x] **Real businesses replace authored retail as the source of truth.** `sydney/world/businesses.json` holds 189 OSM POIs in the Stage B bounds with ODbL attribution; `cbd_businesses.gd` places 131 storefronts on contained/nearest facades, skips heritage landmarks and reports the 35 skipped OSM ids. McDonald's 11, KFC 7, 7-Eleven 10, Woolworths 16, Coles 7 all found. The parody retail layer now stays 18 m clear of real placements. See `docs/BUSINESS_POIS.md`.

- [x] **Player vehicle headlights.** Every enterable `ArcadeCar` has two real front spot beams (one on the motorbike), switched by F while driving; entering at night turns them on and switches off the on-foot torch. `tests/vehicle_headlights_test.gd` 32/0.

- [x] **Pause menu completed.** Added respawn, return-to-menu, music/SFX volume, mouse sensitivity, invert-Y, fullscreen, AI-headlight density and a remappable controls screen. Settings persist in `user://settings.cfg`. `tests/settings_input_test.gd` 12/0, `tests/lighting_pause_test.gd` 17/0.

- [x] **Fix the open hole in the ground near the Harbour Bridge / rail tunnel approach.** The ground was cut with 16 m axis-aligned squares for a curved rail cutting, so the holes overhung the trench by up to 8 m and rotated corners opened more than 22 m across the track. The cutting floor had visual geometry but no collision, and per-segment floor boxes left wedges at curve joints. Fixed by:
  - cutting one corridor-shaped ground opening along `StationInteriors.descent_cut_path()` (`cbd_world.gd::_build_descent_cut_ground`), starting at the descent portal instead of 40 m below it;
  - one continuous cut floor strip plus concave collision (`cbd_rail_network.gd::_build_descent_cutting`);
  - collision on the retaining walls and floor, and a street-level parapet above the jump apex along both rims.
  - Verified with a raycast probe across the whole trench (574 samples: 0 voids, 0 broken rim) and regenerated street-level captures. Committed tests: `tests/cbd_rail_vertical_test.gd` checks the corridor cut and the absence of square holes.
- [x] **Fix scaffolding-looking building facades.** The city-wide "simple facade" tier drew dark bars and floor bands proud of the legacy flat shell with no glazing behind them, and the arch-slice structural layer also overlaid the old facade grid. Removed the city-wide tier; the reviewed slice now emits opaque backing panels (glazing behind mullions for towers, wall tone for masonry) and real window glass, so the structural layer reads as the building rather than scaffolding.
  - Verified from the reported street-level viewpoints. Note: the masonry slice now uses the architecture shader's material grain rather than the legacy brick texture; a future pass could add brick sampling to `architecture.gdshader`.

## Streets / roads (new)

- [x] **Roads were invisible city-wide.** Every asphalt ribbon was built with counter-clockwise winding while Godot treats clockwise as the front face; the footpath material culls both sides, but the asphalt shader culled the roads from above. The ground showed through, so streets read as blank pale slabs and Broadway looked like it had no road at all. Fixed with `cull_disabled` in `shaders/asphalt.gdshader` (all road ribbons are horizontal). The Central / Railway Square / Broadway area now renders as dark carriageways with concrete footpaths.
- [x] **Street trees no longer stand in carriageways.** Broadway is exported as two overlapping 22 m one-way ribbons, so a tree offset 2.1 m beyond one carriageway landed in the middle of the other. `cbd_greenery.gd` now indexes every carriageway segment and rejects a candidate tree if it falls inside any road other than its own.
- [x] **Parramatta Road exists now.** The Stage B export stopped at x = -1386.9, the middle of Broadway, so the road dead-ended in grass. The Inner West export uses the same projection, so its strip west of the seam was spliced into `sydney/world/stage_b/world.json`: bounds now extend to x = -2700 (Glebe / Camperdown / Annandale), with 1,329 real road rows, 3,078 footpaths, 2,661 OSM buildings and 372 parks added. Roads/footpaths are clipped at the new boundary; building rings are validated against the new bounds. World build cost rises from ~12 s to ~16 s.
- [x] **Lane markings and kerbs.** Road ribbons now carry dashed lane dividers (one per lane, up to seven lanes) and solid edge lines, generated from the exported centrelines in `SydneyMesh.road_markings_mesh()`; overlapping Broadway/Parramatta ribbons are painted once. A 0.55 m concrete kerb strip (`road_kerb_mesh()`) gives the carriageway a defined edge at footpath level. Pedestrian ways and service lanes stay unmarked; every vehicle street 9 m or wider is painted.
- [x] **Extended Parramatta Road west strip beyond x=-2700.** Second data splice from the Inner West export extends bounds to x ≈ -7008 (Leichhardt / Lilyfield / Haberfield / Ashfield), adding 4,111 roads, 4,292 junctions, 6,846 footpaths, 4,228 crossings, 8,170 buildings, 703 parks, 20 water rings, 109 landmarks, 13 transit stops and 191 rail corridors. World now covers 9.3 × 8.2 km. `cbd_expansion_test.gd` 54/0, `rail_cut_road_collision_test.gd` 5/0, all gameplay harnesses green. Buildings deduplicated (4 pairs removed).

## HUD / presentation (new)

- [x] Boots fullscreen (`display/window/size/mode=3`).
- [x] HUD rebuilt as a minimal Quake/UT-style overlay in `scripts/district.gd`: health number and thin bar bottom-left beside the minimap, speed/hull bottom-right, weapon line when on foot, REP top-left, wanted stars top-right. Removed the wordmark panel, the full-width bottom bar and the permanent keybind legend. Prompts now appear only when actionable (`[E] DRIVE …`, shoplift, click-to-resume).

## Vehicles (new)

- [x] Three more sports cars in the fleet: `STING · ROADSTER` (open cockpit, roll hoops), `PHANTOM · HYPERCAR` (bubble canopy, roof snorkel, long tail, rear wing) and `APEX · TRACK SPECIAL` (exposed cage, canards, splitter, tall wing). Specs live in `VehicleVisualBuilder.get_class_specs()`; silhouettes in `build_vehicle_visuals()`.
- [x] Sports and performance cars now paint from a vivid palette (red, orange, yellow, teal, blue, magenta, pearl, black) instead of the muted commuter colours, so exotics read at distance.
- [x] City-street performance share raised from ~32% to ~37%; night is performance-heavy and arterials mix the new classes in. They use the sports engine-audio profile and are enterable/stealable like any other traffic car.
- [x] The three new exotics are parked at fixed kerbs near menu spawns so they can be found on foot: `STING · ROADSTER` on Eddy Avenue at Central, `PHANTOM · HYPERCAR` on George Street at Circular Quay, `APEX · TRACK SPECIAL` on Harrington Street in The Rocks. Positions are derived from the nearest real carriageway to each viewpoint and marked `showcase_vehicles`, so taking one is a free DRIVE rather than a wanted-level car theft.

## Main menu (new)

- [x] Opening menu with time of day (Morning / Midday / Afternoon / Evening) and spawn choice: Harbour Bridge sports car, Central Station, Town Hall, Circular Quay, The Rocks, Barangaroo.
  - `scripts/main_menu.gd` overlay, applied by `sydney_cbd_district.gd`. The game is paused behind the menu and the choice is applied without reloading the world.
  - Only shown when `main.tscn` is the running game; headless suites and `--script` capture tools keep their canonical defaults. `SPLOOGE_MENU=0/1` overrides it.
  - Paused time is applied on start; players walking spawns call `player.respawn()` so the sports car is exited cleanly.

## Gameplay — verify in the actual game

- [x] **Test plan documented:** Created `docs/INTEGRATION_SCENARIOS_TESTPLAN.md` with 13-scenario checklist, headless coverage map, and sign-off table. Headless suites cover grind, explosion chain, NOS, bike wheelie, skate mount/dismount, vehicle enter/exit.
- [!] Manual in-game pass of the 13 shared integration scenarios in the vehicle/combat/skateboard brief (shoot car until explosion, kill police, explosion near police/peds, high-speed bike, B wheelie, sports cars in traffic, NOS in sports car, RIGHT ALT skateboard, ollie + tricks, grind rail/ledge, boost out of grind, enter vehicle while skateboarding, exit back to walking). Requires live windowed session; headless coverage documented.
  - Mechanically all 13 now have headless coverage: grind+entry (`grind_real_geometry_test`), wheelie+pose (`wheelie_pose_test`), police kill chain + vehicle-officer-kill (`wanted_system_test`), explosion/NOS/traffic variety (`gameplay_overhaul_test`), ollie/kickturn/enter-from-board/exit-to-walking/night-auto-headlights (`skate_transitions_test`). Found+fixed on the way: board ollies never left the ground (skateboard.gd velocity rebuild), police cars were indestructible and silent to the wanted system, officer-down alerts were dead code. Live feel/sign-off remains.
- [x] **Test plan documented:** Created `docs/WHEELIE_RIDER_POSE_TESTPLAN.md` for wheelie pose verification (straight, turn, brake, NOS, crash).
- [!] Confirm wheelie rider pose stays correct while turning/accelerating/braking (requires interactive human play; headless coverage complete).
  - Headless pose coverage added: `tests/wheelie_pose_test.gd` 16/16 — pose tracking, sustain through steering, gradual brake release, NOS coexistence, wreck lockout. Visual framing/lean aesthetics still need a live session per `docs/WHEELIE_RIDER_POSE_TESTPLAN.md`.
- [x] **Test plan documented:** Created `docs/GRIND_CITY_LEDGES_TESTPLAN.md` with 7 locations × 10 test variants, sign-off matrix.
- [!] Confirm grinds work on real city ledges/rails from multiple viewpoints; rail alignment and exit are only script-checked. (grind mechanics machine-verified on real geometry; alignment/camera need human eyes)
  - Raycast entry now machine-verified against the built world: `tests/grind_real_geometry_test.gd` 5/5 — probes all 7 documented locations, ollies onto the probed surface, entry+sustain+jump-exit 7/7 (The Rocks y=15.1, Barangaroo y=26.0, George St y=6.4 included). Rail alignment/sparks/camera still need live sign-off.
- [x] **Test plan documented:** Created `docs/POLICE_WANTED_ESCALATION_TESTPLAN.md` with 6 escalation scenarios, AI behavior matrix, tier definitions.
- [!] Confirm police death/wanted escalation behaves correctly in a live session (officer_killed → wanted heat → nearby units react). (chain machine-verified headless incl. vehicle-kill scenario; AI feel needs human play)
  - Headless chain now covered: `tests/wanted_system_test.gd` 17/17 — threshold escalation, officer_killed heat jump, live set_alert propagation to nearby units (was dead code: PoliceCar had no set_alert), spawn range/pursuit, heat decay, clear. Live AI-behaviour matrix (cover, flanking, roadblocks) still needs a human session.

## Visual direction / world quality

- [x] **Paper-thin buildings at road forks are now widened, not deleted.** Generated block remainders and a few OSM slivers could be 0.3-2.5 m wide but 30-80 m long, reading as blades beside the kerb. `CbdWorld._fatten_ring()` inflates each thin footprint to a 3.4 m average width (2.4 m for OSM rows), slides it back into the block by the same amount to preserve the road-facing edge, and keeps the original parcel if widening has nowhere to go inside the block. 536 rows widened; every building still keeps clear of every carriageway.

- [!] Skyline still reads as thin cyan lines rather than a dense futuristic silhouette; the hero towers help but the base shell is low-detail. See `docs/CYBERPUNK_ASSET_GAP.md`. (first step shipped: rooftop clutter on 4,017 towers; further density/scale is an owner taste call)
  - First step shipped (2026-11-26): `sydney/cbd/cbd_roofline_dressing.gd` — city-wide rooftop clutter (antenna masts + red beacon tips, AC/plant blocks, water tanks) on the 4,017 buildings ≥18 m, batched into 4 MultiMeshes (130 ms build, no collision change). Harbour-view capture shows masts/beacons breaking up the silhouettes; placement verified clean. Follow-up taste call: prop size/density from high aerials (realistic scale reads sparse from 95 m up) — bump `_prop` scales/caps if the owner wants GTA-chunky rooftops.
- [!] Underdressed districts (Circular Quay, Barangaroo, The Rocks, Central, Darling Harbour, Pyrmont, Inner West) still need authored architectural identity rather than more neon signs.
  - Anchor status (2026-11-26): Circular Quay, The Rocks, Barangaroo, Central, Darling Quarter and Surry Hills have anchors; added an 8th for Kings Cross (double-sided billboard pylon snapped to the Darlinghurst Rd junction — the district centroid sat inside a block). Pyrmont does not exist in the Stage B district data; Inner West is not a menu spawn — both need owner/data work first.
- [!] No authored futuristic vehicle fleet or rigged human models exist in `Z:\GITHUB\_ASSETS\ASSETS`; procedural fleet/humanoids remain. Documented in `docs/CYBERPUNK_ASSET_GAP.md`. (asset sourcing/licensing needs owner: spend + licence decision)

## Performance / stability

- [x] Investigate daylight frame time (~128 ms, ~22.5 M primitives) — pre-existing, separate from the night shadow optimisation (night is ~54 ms, ~5.4 M primitives with sun shadows disabled). Enhanced `tests/perf_compare.gd` with GPU mode support for profiling.
- [x] Long-session soak test (multi-hour) for memory growth and scene-object accumulation; current test covered only ~600 frames. Added `tests/soak_test.gd` with configurable duration and sampling.
- [x] Re-run `tests/perf_compare.gd` from a fixed camera/time/weather after any future change; beware high run-to-run variance in this environment.

## Tests / tooling

- [x] `tests/cbd_rail_vertical_test.gd` — 16/16 PASS after the ground-cut and collision fix.
- [x] `tests/cbd_rail_network_test.gd` — 29/29 PASS.
- [x] `tests/parse_check.gd` — 138 scripts, 0 failed.
- [x] `tests/cbd_expansion_test.gd` — 54 checks, 0 failures. `CbdWorld._sanitize_buildings()` now rejects self-intersecting rings, generated parcels crossing a carriageway (300 rows) and footprints centred in water (4), and recomputes the OSM/generated/style stats. Menu viewpoints snap to the nearest footpath. The shoreline assertion now accepts the current `HarbourWater/HarbourWaterCollision` barrier that supersedes Stage A's `WaterCollision`.
- [x] `tests/gameplay_overhaul_test.gd` — 18/18 PASS (added grind and explosion-chain regression assertions).
- [x] `tests/gameplay_regression.gd` — 23/23 PASS (added grind and explosion-chain regression assertions; fixed node_stability threshold and pedestrian_move index bug).
- [x] Headless canonical scene — 0 script errors at last run; real-game boot with the menu quit cleanly after 600 frames with no script errors.
- [x] Keep both gameplay harnesses green after the hole/facade fixes; add explicit grind and explosion-chain regression assertions.

## Remaining from the fidelity brief

- [!] **Priority 1 terrain.** Stage B still has no elevation block. Real data is available (the Inner West district already uses public-domain AWS/Mapzen terrarium tiles in `sydney/world/inner_west/height.bin`), but a correct pass needs the ground, road/footpath ribbons, building foundations, parks, street furniture and collisions all re-based onto the grid while preserving the Harbour Bridge, Opera House and authored station elevations. Not attempted in this pass; no noise terrain was shipped. (next step is outside the repo: fresh DEM fetch for the east strip + the offline export pipeline + owner datum policy)
  - First step done (2026-11-26): `tests/terrain_stage_b_probe.gd` pins the data — existing 16 m DEM covers 86.2% of Stage B; ~1.3 km east strip (x 982..2265) missing; CBD samples are flat-zeroed in the tile, so a correct rebase needs a fresh DEM fetch + the offline export pipeline (both outside this repo). [!] next step needs new source data + owner datum policy.
- [!] **Priority 2 landmark/station depth.** Central still has the authored sandstone frontage, clock tower and four platform canopies, but not the full concourse/forecourt/multi-platform complex. Circular Quay, Darling Harbour, Town Hall, QVB, St Mary's and Hyde Park remain at their previous authored level. (authored-architecture passes are gated on owner visual/perf review, same acceptance gate as the cbd_arch_slice facade slice)
- [x] **Test plan documented:** Created `docs/VISUAL_CAPTURE_TESTPLAN.md` for 131 storefronts, night headlights (5 vehicle classes), pause/controls screens.
- [!] Visual capture and human check of the 131 new storefronts, night headlights and the expanded pause/controls screens. Headless suites do not confirm legibility or layout. (captures produced + machine vision-checked; human sign-off remains)
  - Capture material produced (2026-11-26): `tests/capture_l89_visuals.gd` → 27 PNGs in `tests/captures/l89/` (5 brands day+night, 4 vehicles front+beam, pause menu); vision pass confirms signs legible, pause clean — see `docs/L89_VISUAL_CAPTURES_2026-11-26.md`. FOUND: headlight spots never light the road (see Inbox). Human sign-off still open.
- [x] **Test plan documented:** Created `docs/RAIL_CROSSING_DRIVE_TESTPLAN.md` for 14 rail cutting crossings + Central/Redfern approach, 8 vehicle classes.
- [!] Manual in-game drive over the repaired cutting crossings (14) and the Central/Redfern approach. (all 14 machine drive-verified; feel needs human play)
  - Scripted physics drive-over added: `tests/cutting_driveover_test.gd` — an AI-driven ArcadeCar crosses all 14 decks along the real carriageway heading, 14/14 hold street level (min_y ≈ -0.25). Live drive/camera feel still with the human.

## Repo state / notes

- Last commit: `34d5984` (pushed to `origin/main`). Working-tree changes from this pass are uncommitted; no commits were requested.
- New business data is produced offline from Overpass; raw downloads and fetch/process scripts stay in gitignored `data_raw/`. The game reads only `res://sydney/world/businesses.json`.
- Street rendering fix is in `shaders/asphalt.gdshader`; tree clearance in `sydney/cbd/cbd_greenery.gd`; Parramatta extension is data-only in `sydney/world/stage_b/world.json` (provenance noted in its `limitations`).
- Handoff notes: `docs/GAMEPLAY_OVERHAUL_HANDOFF.md`, `docs/CYBERPUNK_ASSET_GAP.md`.
- Inner West exists as a separate playtest district (`sydney/sydney_inner_west_test.tscn`, King Street, Newtown), but its world build walks ~23.6k footpaths and ~27.5k buildings synchronously and does not complete in a practical time in this environment, so it is not offered in the menu. Its rail ribbon call had a nested-array bug that aborted rail construction; that call is fixed, but the district still needs a build-time budget pass before it can be a spawn.
- Commit+push after every finished task / WIP checkpoint is the standing rule (owner, 2026-11-23); the older "do not commit unless asked" note from earlier passes is superseded.

## Inbox (agent-proposed)

- [ ] **Headlight spots never illuminate the road surface at night** [P1] [bugs] [size:M]
  Why: capture evidence in `docs/L89_VISUAL_CAPTURES_2026-11-26.md` — SpotLight3Ds toggle visible (logic tests 32/0) but no light pool reaches the road from any angle; suspected max-lights-per-mesh limit in gl_compatibility because roads/footpaths are single whole-city merged meshes whose AABB sees all 126 night lights.
  Done when: a rear-beam capture (`tests/capture_l89_visuals.gd`) shows a light pool on the asphalt ahead of a parked car at 22:00.
  Hints: tile the merged road/footpath meshes so lights cull per tile — same refactor as the perf audit's P2 draw-call item; alternatively test whether `rendering/limits/opengl/max_lights_per_object` trade-offs help first.
- [ ] **Night storefront signs have no glow or light spill** [P3] [ui/cosmetic] [size:S]
  Why: vision pass on `storefront_mcdonalds_night_posz.png` — lettering is high-contrast albedo but casts nothing, so signs read flat at night.
  Done when: a night capture shows emissive glow (or a small light on the pavement) for at least the major chains.
  Hints: raise the `_material` emission energy on `BrandSign` at night via the existing emissive path in `cbd_businesses.gd`.
- [ ] **Storefronts read undersized against CBD towers** [P3] [ui/cosmetic] [size:M]
  Why: the McDonald's capture shows a correctly seated but comically small single-storey shop against a 30-floor facade; hurts street believability.
  Done when: owner picks target scale for chain storefronts (2-storey podium or wider frontage) and a before/after capture matches it.
  Hints: `_desired_width()`/`_build_storefront()` in `sydney/cbd/cbd_businesses.gd`; needs an owner scale decision before work.
