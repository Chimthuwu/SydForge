# Rail corridor collision — root cause (Phase A)

## Reported symptom

Bodies entering the Sydney rail corridor fell through the world, and the view
inside the bore ended at a flat grey wall. The repository also carries four
first-hand captures in the project root (`train tunnel glitch.png`,
`train tunnel glitch2.png`, `wall inside the train tunnel glitch3.png`,
`wall inside the train tunnel glitch4.png`).

## How it was reproduced

Temporary probes (`tests/_collision_probe*.gd`, since deleted) loaded the real
`CbdWorld` and:

1. dropped a 1.2 m `RigidBody3D` on the route at 24 sample indices;
2. cast rays down from 25 m above each sample and forward 45 m inside the bore;
3. ran a shape query at head height.

Results on clean HEAD, before any edit:

| Route section | Index | Result |
|---|---|---|
| Harbour Bridge | 220–228 | rests on `BridgeCollision` |
| Descent / open cut | 271–326 | rests on the cut floor (working) |
| Wynyard platform | 358 | rests on station body at −9.61 |
| Bore, south of Wynyard | 386 | **fell to −12.58** (track −10.0) |
| Bore, south of Wynyard | 364 | **fell to −15.92** |
| Bore, south of Wynyard | 378 | **fell to −12.58** |
| Town Hall south | 485 | **fell to −13.79** (track −9.59) |
| Town Hall south | 499 | **fell to −10.30** (track −8.88) |
| Central platform / surface | 660, 666 | rests on station body |
| Redfern approach | 829 | downward ray hit `BuildingCollision` at y = 11.10 |

Forward ray from route 760 hit `BuildingCollision` 19.5 m ahead, closing the
line of sight out of the Central tunnel.

## Root causes

### 1. The tunnel bore had walls and a ceiling but no floor

`cbd_rail_network.gd::_build_tunnel_enclosures()` built two wall colliders and a
ceiling collider per enclosure segment. It never built a bed collider, and the
ballast is a visual mesh only. The open cut had its own floor, which is why
indices 271–326 worked and hid the defect: only once the route entered the bore
did a body have nothing underneath. This is the fall-to-void failure.

### 2. The shallow Central ascent is geometrically too shallow for the bore

`_is_tunnel_segment()` only encloses a segment once its midpoint is at or below
`TUNNEL_MIN_TRACK_Y = −7.25` (6.8 m wall + 0.6 m roof under the street slab).
The authored route rises from −10.0 at Town Hall to +0.1 at Central over roughly
180 indices. Between those points there is neither bore nor open cut: the track
runs under the city ground slab with no enclosure and, before this pass, no
floor. Shape queries at indices 560 (−5.53), 600 (−3.20) and 640 (−0.98)
intersected `GroundCollision`, confirming the slab sits over the running line.
The authored station elevations are preserved; this section is flagged as
remaining terrain/profile work rather than silently re-profiled.

### 3. The open-cut floor was a zero-thickness triangle strip

The cut's visual and collision floor is one triangle strip. A `CharacterBody3D`
moving at road speed can complete a physics step on the far side of a
zero-thickness surface without registering a contact, so the strip alone is not
a dependable barrier. The cut also had floor collision only at its own indices;
it did not continue into the bore.

### 4. The building-clearance corridor stopped at Wynyard

`cbd_world.gd` clears buildings near the rail reserve using
`RAIL_CORRIDOR_POLYLINE`, whose last point is Wynyard. South of Wynyard the
filter did nothing. In addition, the test was centroid-plus-radius (18 m), not
footprint-based, so it could both miss a block that straddles the track and
over-clear a block merely near it. A single generated parcel
(`gen/central/24/6`, a block whose ring encloses the Redfern station point)
built a wall across the running line at y = 11.10. The OSM alignment itself
stops ~60 m short of the Redfern platform, so even extending the polyline along
the way would have left the station connector uncovered.

## Fix applied

- `_build_below_grade_floor()` adds a solid `RailTrackBedCollision` StaticBody
  with one overlapping box per non-bridge segment whose track midpoint is below
  −0.8 m. The bed top is 0.04 m below rail level (the ballast top), width 11 m,
  thickness 1.2 m; boxes overlap 0.8 m at joints so there is no seam to fall
  through. It covers the bore, station approaches and the shallow ascent.
- `_build_descent_cutting()` now adds a 1.5 m thick box slab under the existing
  continuous cut triangle strip (top 0.25 m below the strip, width 13.2 m,
  1 m overlap). The strip remains the exact walking surface; the slab is the
  structural floor and catches a body that steps past the strip.
- `cbd_world.gd` adds a footprint-based `SOUTH_RAIL_CORRIDOR` filter. It loads
  `way/136259642` from `sydney/railway/milsons_redfern.json`, trims it at the
  nearest point to Redfern, appends the real Redfern station point (the route's
  connector), and clears a building when any ring vertex is within 8 m of the
  reserve or a reserve point lies inside the ring.
- Building `ConcavePolygonShape3D` colliders now set
  `backface_collision = true`, so a body that ends up inside a wall cannot fall
  out through the single-sided hull.

## Verification

Automated, real bodies — `tests/rail_corridor_physics_test.gd`:
`RESULT: 2350 checks, 0 failures`. It builds the real `CbdWorld` and runs the
real `ArcadeCar` (Comet scene), the real on-foot `BoomPlayer` capsule and the
real `VehicleTrafficController` through the open cut, Town Hall bore and Central
ascent: 20 passes × 3 speeds (5 / 16 / 30 m/s) per location for each body type,
plus a 90-frame walk-through of every accessible station. Each pass asserts the
body reached the section, never dropped more than 1.5 m below the track bed,
never passed y = −20, and never exceeded 40 m/s downward.

Drop probe after the fix: every previously failing index now rests at the bed
(`386 → −9.45`, `364 → −9.45`, `378 → −9.45`, `485 → −9.00`, `499 → −8.31`),
and the Redfern downward ray hits the platform body instead of a building.

Affected suites re-run: parse 141/0, CBD expansion 54/0, living Sydney 51/0,
rail vertical 16/0, rail network 29/0, Sydney physics 32/0, gameplay overhaul
13/13.

Visual captures (windowed, inspected): `tests/captures/phase_a/` —
`descent_cut_rim.png`, `town_hall_bore.png`, `central_ascent.png`,
`redfern_approach.png`. The Redfern approach now shows continuous rails with no
building across the line. The bore capture is very dark; interior lighting is
part of Phase C and still needs an in-game look.

## Continuation — roads over the open cutting (2026-11-22)

The rail-bed fix stopped bodies falling through the *bore*, but a second path
remained: the open cutting removes the ground slab along the route, and road
ribbons simply span the gap. A downward ray at a road point inside the cutting
landed on `RailDescentCuttingCollision` at y ≈ −6, i.e. six metres below the
street, with no deck above it. A car following that road fell into the trench.

`CbdWorld._build_rail_cut_road_decks()` now finds every road centreline segment
that intersects the cut centreline and builds a bridge deck at street grade:

- one collision box per crossing, aligned to the road and lengthened for
  oblique crossings;
- a visual slab 1 cm below the road surface to avoid z-fighting;
- crossings within 2.5 m are deduplicated (dual carriageways / split OSM ways);
- roads that merely end at the rim do not cross the centreline and get no deck.

`tests/rail_cut_road_collision_test.gd` builds the real Stage B world, finds the
crossings and checks each one: 14 crossings, 14 decks, 14/14 rays hit at street
level, and three real `ArcadeCar` drops land on the decks. Result: 5 checks, 0
failures. The full rail suite still reports 2350 checks, 0 failures.

## Remaining / not fixed here

- The shallow Central ascent remains unroofed and under the ground slab. It now
  has a floor, so nothing falls into the void, but a train at that grade can
  still intersect the slab; solving it requires a terrain cut or a re-profiled
  approach in Phase B/F, not a collision-only edit.
- Performance is unchanged by Phase A and remains well above the documented
  128 ms / 54 ms targets (see `docs/OVERHAUL_BASELINE.md`).
- Manual in-game drive-through of the bore and the Redfern approach is still
  required; headless physics passing is not a visual sign-off.
