# Architecture

`scenes/district.tscn` is the composition root. `scripts/district.gd` builds the
district, configures controls, instantiates actors, owns HUD and transient effects.
`Art` caches materials and supplies reusable primitive geometry helpers.

`BoomPlayer`: CharacterBody3D locomotion, health, magazine/reload and combat.
`BoomCamera`: independent follow rig, mouse orbit, pitch limits and SpringArm3D
sphere collision. Excludes the player and occupied vehicle from camera queries.
`ArcadeCar`: CharacterBody3D custom arcade physics and safe enter/exit. Four
scene resources configure stats, colour and styling. No VehicleBody3D dependency.
`BoomEnemy`: line-of-sight pursuit/attack, health and timed respawn.

Collision layer 1 carries world and actors. Occupied players disable collision
and follow their car; safe exits test a capsule before re-enabling collision.
Runtime geometry is constructed in scene scripts; actors have reusable .tscn
entry points. Enemy/player circular references are injected by the composition root.
Tests load the production scene and simulate actual physics/input where applicable.

## Sydney world adapter (Stage A)

`district.gd::build_city()` builds the shared environment, then either loads
`SydneyWorld` (when `--sydney` or `SPLOOGE_SYDNEY=1` is set) or builds the
original 220 m District Zero. `sydney/sydney_world.gd` validates and imports
`sydney/world/stage_a/world.json`, builds one mesh per layer plus ground/building
collision, and exposes spawn points plus the pedestrian graph. Tunnel roads are
kept in the data but skipped by the surface mesh builder. `sydney/sydney_mesh.gd`
owns the mesh builders. The composition root injects `player.spawn`, the four car
transforms and `enemy.home`; player, camera, vehicle, combat, enemy and HUD
scripts are unchanged. The Sydney path is opt-in so the existing regression suite and
District Zero remain the default.
