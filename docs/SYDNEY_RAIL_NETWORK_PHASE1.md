# Sydney rail corridor — Milsons Point to Redfern

The Stage B CBD world now contains a static double-track rail corridor from
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
track gauge, sleeper layout, tunnel depths and station interiors are authored
presentation. They are not survey-grade elevations or a railway signalling
model.

## Stations and limits

The corridor has station shells/entrance markers for Milsons Point, Wynyard,
Town Hall, Central and Redfern. The Wynyard/Town Hall platforms are below the
flat world surface; their interiors can be inspected with the rail cutaway
capture. The Harbour Bridge and Central station reuse their existing landmarks.

This phase builds infrastructure only: no rolling stock, timetables, signals,
passenger movement or collision for trains. Accurate Tangara/T-set and
Millennium traffic remain a separate TODO.

## Verification

```powershell
& './Godot_v4.7.2-stable_win64_console.exe' --headless --path . `
  --script res://tests/cbd_rail_network_test.gd

& './Godot_v4.7.2-stable_win64_console.exe' --path . `
  --script res://tests/cbd_rail_network_visual.gd
```

The focused suite verifies route endpoints, station order, maximum waypoint
spacing, track meshes, tunnel sections and Harbour Bridge integration.

On Godot 4.7.2, `tests/cbd_rail_network_test.gd` reports **29 checks, 0
failures**. Windowed Stage B world captures were generated and inspected at
`Z:/Temp/opencode/splooge-rail-network/`; the existing bridge rail deck and the
Wynyard platform cutaway are visible. An earlier street-level view obscured the
Wynyard entrance behind nearby buildings; the final entrance-sign refinement has
not yet been recaptured. These are world-content captures, not a full player
playtest.
