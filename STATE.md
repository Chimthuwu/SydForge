# STATE — Splooge

_Cross-session daily report; durable design details live in project docs._

- **Phase/milestone:** Canonical Sydney world, unified living-world simulation, and corrected vehicle airborne physics.
- **Last session:** Fixed the "flying ambulance": AI traffic now integrates vertical velocity across frames in both autonomous and hijacked driving paths, no-route/LOD cars still fall, and `floor_snap_length` no longer glues them to a surface. Rebuilt the Opera House step collision as thin slabs to remove overlapping full-height prisms that depenetrated a box collider upward. Verified the player ArcadeCar already had correct airborne integration and left it unchanged.
- **Experience:** A/B measurement: legacy formula left a car at y=19.51 after 180 frames from 20 m; fixed controller lands at y=0.00. New `vehicle_airborne_test.gd` 32/0 and `vehicle_stairs_airborne_test.gd` 16/0 (real Opera House geometry); opera house 57/0, Sydney physics 32/0, vehicle handling 28/0, ecosystem 51/0, living world 50/0, integration 63/0. Windowed capture showed vy=−4.25 in free fall and clean landings on lower treads. See `docs/AIRBORNE_PHYSICS_FIX.md`.
- **Next up:** Human drive-through of a hijacked ambulance down the Opera House steps and a second listen to siren/impact audio; confirm no low-speed depenetration creep remains when idling into other dense concave collision (e.g. BuildingCollision near Circular Quay).
- **Backlog:**
  - Improve street-level capture framing; scripted CBD viewpoints sometimes face a facade. _(since 2026-11-20)_
  - Audit the remaining OSM `BuildingCollision`/`OperaCollision` overlaps near Circular Quay; a stationary car against them can still be pushed upward fractionally. _(since 2026-11-21)_
  - Human audio audition of ambient beds and emergency sirens. _(since 2026-11-20)_
  - Stale `main_game_test.gd` (39/17) and `wanted_system_test.gd` (6/3) baselines fail identically on clean HEAD. _(since 2026-11-20)_

_Updated: 2026-11-21_
