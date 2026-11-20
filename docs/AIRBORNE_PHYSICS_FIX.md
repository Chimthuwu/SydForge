# AI vehicle airborne physics — root cause and fix (21 Nov 2026)

## Reported symptom

An ambulance hijacked from AI traffic and driven off the Opera House stairs
appeared to fly instead of falling.

## Root cause

Two systems, not one:

1. `sydney/ecosystem/vehicle_traffic_controller.gd` overwrote the whole velocity
   vector every physics tick in both driving paths (autonomous route following
   and `_drive_player_controlled`):

   ```gdscript
   velocity = fwd_dir * current_speed * step_scale   # zeroes velocity.y
   velocity.y -= 9.8 * step                          # one frame of gravity only
   move_and_slide()
   ```

   `velocity.y` was therefore never carried between frames. At 60 Hz a falling
   car gained only ~0.16 m/s of downward speed per tick instead of accumulating
   gravity. A/B measurement in `tests/vehicle_airborne_test.gd`: the pre-fix
   formula left a car dropped from 20 m at **y = 19.51 m after 180 frames**;
   the fixed controller lands at **y = 0.00 m**.

2. The Opera House steps (`sydney/landmarks/opera_house.gd::_build_steps()`)
   extruded 23 nested solid prisms from y = 0 to each tread height. They shared
   internal top faces and coplanar side walls at the podium clip plane. A box
   collider idling into that fine concave trimesh was depenetrated upward a
   fraction each tick (observed: y 12.02 → 13.27 while stationary), which read
   as additional "flying".

The player's `ArcadeCar` (`scripts/vehicle.gd`) was **not** faulty: it already
preserved `velocity.y`, applied 24 m/s² gravity before `move_and_slide()`, capped
terminal velocity at −35 m/s and tracked an `airborne` flag. It was verified,
not changed.

## Fixes

- `vehicle_traffic_controller.gd`: added `_move_with_air_physics(horizontal, step)`,
  the single integration point. It writes only x/z from driving, integrates
  `velocity.y` with `AIR_GRAVITY = 9.8` from its previous value, clamps fall and
  launch speed, calls `move_and_slide()`, and zeroes residual vertical velocity
  on floor contact. Both driving paths use it. No-route and LOD-throttled cars
  also integrate gravity while airborne. `floor_snap_length = 0.0` stops the
  body snapping down to the next surface at a ledge.
- `opera_house.gd`: each tread is now a 0.5 m thin slab
  (`_extrude(..., maxf(0, top - rise), top)`) instead of a full-height prism.
  Every walkable tread height, the stepped silhouette and all collision remain
  unchanged; redundant internal/buried faces are gone.

No collision was disabled; no ambulance-only special case was added.

## Verification

| Suite | Result |
|---|---|
| `vehicle_airborne_test.gd` (new) | 32 checks, 0 failures |
| `vehicle_stairs_airborne_test.gd` (new, canonical world) | 16 checks, 0 failures |
| `opera_house_test.gd` | 57 checks, 0 failures |
| `sydney_physics_test.gd` | 32 checks, 0 failures |
| `vehicle_handling_test.gd` | 28 checks, 0 failures |
| `living_sydney_ecosystem_test.gd` | 51 checks, 0 failures |
| `living_world_integration_test.gd` | 50 checks, 0 failures |
| `integration.gd` | 63 checks, 0 failures |

Windowed gameplay run (`tests/airborne_capture.gd`, real OpenGL renderer):
ambulance on the Opera House stairs — frame 0 y=11.50/vy=0, frame 20 y=11.50
(accelerating), frame 45 y=10.95/**vy=−4.25**, frame 75 y=9.00/vy=0 (landed on a
lower tread), frame 110 y=0.50/vy=0 (bottom). Captures:
`tests/airborne_flight_000/020/045/075/110/150.png`.
