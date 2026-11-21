# Gameplay Overhaul — Handoff (2026-11-22)

## Implemented
- Vehicle weapon damage, escalating damage stages, wrecks, explosion with area damage and chain-reaction guard (`scripts/vehicle_combat.gd`, `scripts/vehicle.gd`).
- Police damage/death/wanted integration and reaction (`sydney/ecosystem/pedestrian_controller.gd`, `scripts/wanted_system.gd`).
- Motorbike player vehicle with visible rider, faster tuning, B-key wheelie (`scenes/vehicles/motorbike.tscn`, `scripts/vehicle.gd`, `scripts/district.gd`).
- More traffic classes (supercar, muscle, performance sedan, coupe), better spawn weights and faster AI (`sydney/ecosystem/vehicle_visual_builder.gd`, `traffic_manager.gd`, `vehicle_traffic_controller.gd`).
- Skateboard traversal with ollie/tricks/grind/boost (`scripts/skateboard.gd`, `scenes/skateboard.tscn`, `scripts/player.gd`, RIGHT ALT).
- NOS full-screen distortion shader and overlay (`shaders/nos_distortion.gdshader`, `scripts/nos_overlay.gd`).

## Tests
- `tests/gameplay_overhaul_test.gd`: 13/13 PASS at last run.
- `tests/gameplay_regression.gd`: 18/18 PASS at last run (occasional flaky traffic-car exit failure).
- Headless canonical scene: 0 script errors.
- Visual captures inspected: motorbike rider, skateboard, NOS distortion, vehicle explosion (`tests/overhaul_v2/`).

## OUTSTANDING — NOT FIXED
- **Open hole in the ground near the Harbour Bridge / rail tunnel approach** still exists. The player can fall through the street into the exposed rail tunnel and die. This was reported with screenshots in `tests/reported_defects/` (`open_tunnel_hole_near_bridge.png`, `open_tunnel_hole_scaffolding_buildings.png`). Approximate area: harbour bridge southern approach / Milsons Point–Wynyard rail corridor. Needs a ground-cover/collision repair near the tunnel portal; it was not addressed in this pass.
- Scaffolding-looking building facades from the same screenshots remain unresolved.

No commits were made during the middle of the work; this handoff records the state at the time of the user-requested commit/reboot.
