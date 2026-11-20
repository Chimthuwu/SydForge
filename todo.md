# Splooge TODO

## Finish current gameplay pass
- Verify the new shotgun: equip keys, model, pellet spread, damage, reload, and sound.
- Make bullet impacts visibly splatter and break apart hostile and pedestrian bodies; inspect a rendered capture.
- Verify the night-start clock, city lighting, and animated flying foxes; check that foxes hide during daytime.
- Re-run the ecosystem suite and canonical scene startup. The District Zero integration suite still has the two documented melee/reputation failures.

## Sydney transport and places
- [x] Add Wynyard and Town Hall underground stations, a continuous double-track rail route from Milsons Point through to Redfern, authored enclosed tunnel bores/portals for underground segments, and basic visual train service with station stops. See [rail-network phase 1](docs/SYDNEY_RAIL_NETWORK_PHASE1.md).
- [x] Render tunnel-tagged roads as 3D tunnel structures (road surface, shell, portals) instead of omitting them from the surface.
- Add accurate K-set and Tangara/T-set train traffic/service detail (no Millennium trains): inspect supplied model archives for license/compatibility, improve consists/variation, and add richer scheduling/behavior beyond current visual dwell service.
- Add rail simulation depth as needed (signaling/interlocking, train-world interaction/collision constraints, passenger/timetable systems) if gameplay requires it; current implementation is authored presentation/service, not surveyed or fully simulated.
- Build the missing CBD-to-bridge overpass and connect it to Anzac Bridge without overlapping or breaking the canonical world.
- Add Luna Park and authored Kings Cross nightlife/people, and refine Town Hall, QVB, and Hyde Park.

## Art and remaining project work
- Inspect and integrate selected commercially permitted Devil's Work.shop car assets; use additional verified CC0 MegaKit building modules where they improve the existing city.
- Find a licensed 3D weapon asset if one becomes available; the indexed weapon archives were absent from the shared library.
- Finish the non-overlapping Walsh Bay/Fort Denison harbour work and the vehicle-overhaul captures/human drive-through notes.
