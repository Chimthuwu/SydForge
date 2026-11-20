# Sydney rail corridor — Milsons Point to Redfern

The Stage B CBD world contains a continuous double-track rail corridor from
Milsons Point across the Harbour Bridge and south through Wynyard, Town Hall and
Central to Redfern. It is authored from the local OSM railway extract and uses
the same Stage B metre projection as the road/building world.

The tested route is about **5.89 km**, represented by 830 waypoints at no more
than 8 m spacing. It uses 1,435 mm gauge and an authored 3.8 m track-centre
spacing for the parallel pair.

## Source and ownership

- Installed data: `sydney/railway/milsons_redfern.json`.
- OSM railway ways: 449335834, 449335852, 449335855, 449335837, 449335832,
  449335833, 449335847, 136259641 and 136259642.
- The existing authored Harbour Bridge supplies the elevated bridge track
  geometry; the route joins its western rail corridor at the southern approach.
- Attribution: © OpenStreetMap contributors, ODbL 1.0.
- The route source is copied into this project; game startup does not read the
  sibling Sydney data repository.

The source geometry defines one continuous track alignment. The second track,
track gauge, sleeper/ballast/rail layout, tunnel bores, portal structures,
station shells/interiors and elevations are authored presentation. They are not
survey-grade elevations, surveyed tunnel profiles, or a railway signalling
model.

## Implementation

- **Track and alignment:** static double-track meshes (ballast, sleepers, rails)
  follow the authored route, including bridge integration and underground
  elevation transitions (Wynyard/Town Hall corridor).
- **Tunnels:** underground rail segments are enclosed with authored tunnel bore
  geometry (walls, ceiling, collision, and tunnel lighting), with portal/
  emergence structures at key transitions and gaps around station/access areas to
  integrate with station volumes.
- **Stations:** station shells/entrance markers and walkable authored station
  interiors/openings are provided for key stations (including below-surface
  access where applicable). The Harbour Bridge and Central station reuse their
  existing landmarks/context.
- **Trains:** visual K Set consists run along `main_route_points` with basic
  station stop/dwell behavior and distance LOD. Trains remain presentation-only
  (no train physics, no collision with world/traffic/pedestrians, no signaling,
  no timetables, no passenger simulation).
- **Road tunnels:** tunnel-tagged roads are rendered as authored 3D tunnel
  structures below ground (road surface, shell, and portal frames) instead of
  being omitted from the surface road mesh.

## Limits

- Geometry/elevations are authored approximations, not surveyed rail or tunnel
  engineering data.
- No signaling/interlocking, train physics, train-world collision, dispatch/
  timetable system, or passenger boarding simulation.
- Rolling stock/service is simplified visual traffic (K Set consists). Accurate
  mixed K-set and Tangara/T-set traffic remains dependent on licensed/compatible
  assets and further content work; no Millennium trains.

## Verification

```powershell
& './Godot_v4.7.2-stable_win64_console.exe' --headless --path . `
  --script res://tests/cbd_rail_network_test.gd

& './Godot_v4.7.2-stable_win64_console.exe' --path . `
  --script res://tests/cbd_rail_network_visual.gd
```

The focused suite and prior captures verified route/station ordering, spacing,
track/tunnel sections, and bridge integration on Godot 4.7.2. After further
tunnel/portal/traffic and road-tunnel changes, rerun the rail tests and perform
windowed visual inspection/captures for regressions (these are world-content
checks, not a full player playtest).
