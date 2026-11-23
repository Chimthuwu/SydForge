# SydForge overhaul — measurement baseline

Captured 2026-11-22 on branch `main` at `3f27480` (clean working tree) before any
overhaul edits. This is the "before" column the overhaul report is measured
against; it also records the pre-existing failures so they are not mistaken for
regressions.

## Environment

- Godot 4.7.2 stable, bundled `Godot_v4.7.2-stable_win64_console.exe`
- Windows, headless for logic suites; windowed 1920×1080 for the perf capture
- Machine state: normal desktop load, no other Godot instances
- Rail route: 830 points; bridge indices 17–226; stations
  `milsons-point 0`, `wynyard 358`, `town-hall 479`, `central 660`,
  `redfern 829`

## Suite baseline

| Suite | Result | Notes |
|---|---|---|
| `parse_check.gd` | 138 scripts, 0 failed | |
| `cbd_expansion_test.gd` | 54 checks, 0 failures | |
| `living_sydney_ecosystem_test.gd` | 51 checks, 0 failures | |
| `vehicle_handling_test.gd` | exit 0 | count not printed |
| `cbd_rail_vertical_test.gd` | 16 checks, 0 failures | |
| `cbd_rail_network_test.gd` | 29 checks, 0 failures | |
| `vehicle_airborne_test.gd` | 32 checks, 0 failures | |
| `vehicle_stairs_airborne_test.gd` | 16 checks, **1 failure** | `FAIL: ambulance actually left the stair tread (11.50 -> 9.00)` — 2.5 m drop vs the test's >3.0 m expectation; reproduces on clean HEAD |
| `opera_house_test.gd` | 57 checks, 0 failures | |
| `sydney_physics_test.gd` | 32 checks, 0 failures | |
| `integration.gd` | 72 checks, **2 failures** | `FAIL: four vehicle scenes instantiated`; `FAIL: HUD updates live health` |
| `gameplay_overhaul_test.gd` | 13/13 | |
| `gameplay_regression.gd` | **fails** | `REGRESSION FAIL landing | y settled 52.98` — known occasionally flaky vehicle-exit case |
| `main_game_test.gd` | 39 checks, **17 failures** | stale suite; known baseline, not edited to go green |
| `wanted_system_test.gd` | 6 checks, **3 failures** | stale suite; known baseline, not edited to go green |

## Performance baseline

`tests/perf_compare.gd`, fixed camera / time / weather, two runs per time of day,
fullscreen windowed. Numbers are frame time in milliseconds (lower better).

| Time | Run 1 | Run 2 | Draw calls | Primitives | Lights | Mesh nodes | Sun shadows |
|---|---|---|---|---|---|---|---|
| Day | 214.07 ms | 221.83 ms | 3443 / 3446 | ~28.66 M | 149 / 147 | 8222 | 1 |
| Night | 174.60 ms | 155.35 ms | ~3241 | ~6.7 M | 135 / 129 | 8222 | 0 |

After Phase C (street lamps 18→14, AI headlights capped at the nearest six
within 70 m) the same night probe measured 156.68 ms with 127 lights, inside
the baseline 155.35–174.60 ms range. That is performance-neutral within
run-to-run variance; the Phase C benefit is the bounded light count.

Documented targets in `PERFORMANCE_AUDIT.md` are ~128 ms day and ~54 ms night.
The clean-HEAD build is roughly 1.7× slower by day and 2.9–3.2× slower at night
than those figures, so the overhaul starts from a performance deficit that is
unrelated to collision work. It is recorded here, not silently "fixed" in
Phase A.

## Working-tree state

Clean at `3f27480` (`docs: rebrand the project as SydForge and rebuild the
README`). All overhaul changes are left uncommitted.
