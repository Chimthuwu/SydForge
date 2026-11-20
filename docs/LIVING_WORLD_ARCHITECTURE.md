# Living Sydney world simulation — ownership and integration

This document describes how the living-world systems fit together in the
canonical scene (`res://scenes/main.tscn` → `scripts/sydney_cbd_district.gd`).
It is an integration record, not a new design: every system below already had
an implementation; the work in this phase wired them together, removed dead
lookups and fixed the places where two systems fought over the same state.

## 1. Composition root and ownership

`scripts/sydney_cbd_district.gd::_initialize_living_ecosystem()` is the only
place that creates living-world managers. It deliberately keeps the original
node names (`WorldTimeManager`, `TrafficManager`, `PedestrianManager`, …) as
**direct children of the scene root** because the regression suites address
them by that exact path.

`WorldSimulationDirector` (`sydney/ecosystem/world_simulation_director.gd`) is
the coordinator. It owns:

- the reusable `ACTIVITY_PROFILES` table (morning / daytime / afternoon /
  evening / night) that drives traffic caps, pedestrian archetypes, event
  selection, emergency bias and ambient audio levels;
- a single `world_event` bus for player/world reactivity;
- district density budgets, applied through `set_density_multiplier()` on the
  traffic and pedestrian managers;
- cross-system reactions (pedestrian alerts, incident dispatch, obstruction
  registration, ambient-scene interruption).

It explicitly does **not** spawn or cull actors, own lights, or build geometry.
There is exactly one of each existing manager; no duplicate manager was added.

| System | Owner | Consumed by |
|---|---|---|
| Clock / sun / sky | `WorldTimeManager` | lights, traffic, peds, wildlife, weather, business, events, director |
| Streetlights / window shade | `CityLightsManager` | time manager `lighting_factor` |
| Road vehicles | `TrafficManager` + `VehicleTrafficController` | director, incidents |
| Footpath population | `PedestrianManager` + `PedestrianController` | director, business, events |
| Wildlife | `WildlifeManager` | time manager |
| Weather / rain / wetness | `WeatherManager` | time manager (factors), ambient audio, events |
| Venues / hours / interactions | `BusinessManager` | director, `district.gd::interact()` |
| Ambient micro-events | `AmbientEventDirector` | director, `district.gd` (via bus) |
| Incidents / responders | `EmergencyIncidentManager` | director, traffic manager |
| Ambient soundscape | `AmbientAudioDirector` | director, weather, time |
| Police / wanted | `WantedSystem` | director (`wanted_changed`) |

## 2. Data flow

1. `WorldTimeManager` emits `activity_period_changed` (five coarse periods)
   alongside the existing detailed `period_changed`. Managers that need
   behaviour rather than lighting listen to the coarse signal.
2. `WorldSimulationDirector` receives the coarse period, applies the matching
   profile, and recomputes district density from `SydneyWorld.district_at()`.
3. Interesting player actions are published once:
   `district.gd::gunshot()` → `WorldSimulationDirector.report_event("gunfire")`.
   The director then fans that out to pedestrians (flee), ambient events
   (interrupt), and incidents (police dispatch with a cooldown).
4. Incidents publish `incident_started`; the director turns that into a road
   obstruction and a distant siren, and the incident manager asks the traffic
   manager for a real responding emergency vehicle.
5. `district.gd::interact()` keeps its original priority — supermarket, then
   vehicle enter/exit — and only then asks `BusinessManager` for a nearby
   venue. A cafe next to a parked car can never steal the E key.

## 3. Fixes to pre-existing defects

- `PedestrianManager._current_hour()` looked for group `world_time` / property
  `current_hour`; the real manager uses `time_managers` / `current_time_hours`.
  Pedestrian archetypes were frozen at 14:00. Fixed.
- `WeatherManager` wrote absolute sun energy every frame and was overwritten by
  `WorldTimeManager`. Weather now supplies `overcast`/`rain` factors and the
  time manager — the single owner of sun and sky — applies them.
- Rain used `RibbonTrailMesh`, which the Compatibility renderer does not
  support, so rain was invisible. Replaced with a billboarded `QuadMesh`.
- `TrafficManager` had an `evening` profile that could never fire because the
  clock emitted `sunset`/`dusk`. It now uses the five coarse activity periods.
- `AudioDirector.play_distant_siren()` set `global_position` before `add_child`,
  producing an engine error whenever a distant siren played.
- The Milsons Point → Wynyard rail bore was built while the track was still at
  road grade (y ≈ 0.15), standing a 6.8 m concrete box on the Bradfield
  Highway. Enclosures now require the roof to be below grade; portals are low
  grade-level markers. See `tests/tunnel_clearance_test.gd`.

## 4. Audio mix

Buses: `Master`, `Music`, `Weapons`, `Movement`, `Vehicles`, `Environment`,
`NPC`, `UI`. `AudioDirector.set_category_volume(category, db)` controls each
category independently. Weapon profile levels were not changed.

The soundscape uses eight shared, crossfaded looping beds (traffic, crowd,
birds, wind, rain, water, construction, nightlife) in `AmbientAudioDirector`,
baked once into static cached streams. One-shot spatial sounds (sirens,
impacts, engines) remain on `AudioStreamPlayer3D`. This keeps the mix at a
fixed eight ambient voices instead of one source per actor.

## 5. Performance note

Headless probe (`tests/living_world_perf_probe.gd`, 240 frames after a 320-frame
fill): 25 AI cars / 45 pedestrians / 14 wildlife, eight ambient voices,
**≈11.8 ms CPU per frame**. The renderer is stubbed in headless mode; draw-call
cost from the new venue tableaux is not included. The pre-existing static city
mesh and actor draw calls remain the dominant GPU cost described in
`PERFORMANCE_AUDIT.md`.

## 6. Tests

| Suite | Result |
|---|---|
| `living_sydney_ecosystem_test.gd` | 51 checks, 0 failures |
| `living_world_integration_test.gd` | 50 checks, 0 failures |
| `tunnel_clearance_test.gd` | 6 checks, 0 failures |
| `cbd_rail_network_test.gd` | 29 checks, 0 failures |
| `train_network_test.gd` | 13 checks, 0 failures |
| `vehicle_handling_test.gd` | 28 checks, 0 failures |
| `sydney_physics_test.gd` | 32 checks, 0 failures |
| `integration.gd` (District Zero) | 63 checks, 0 failures on passing runs; one pre-existing flaky reverse-driving assertion fails intermittently on the untouched baseline too |

`main_game_test.gd` (39 checks / 17 failures) and `wanted_system_test.gd`
(6 checks / 3 failures) were verified to fail identically on a clean `HEAD`
snapshot; they are pre-existing and were not weakened or modified.
