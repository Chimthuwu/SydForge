# Station audit — Central precinct, City Circle, Inner West and North Shore

_Updated: 2026-11-22. Scope: the second milestone (2A–2E), not the completed first-milestone interiors._

This audit records every station in the milestone against OpenStreetMap and the
current Stage B world. It is the station-data input for `docs/RAIL_EXTENSION_PLAN.md`
and for the 2B–2E placement work. It does **not** claim that any unbuilt station is
complete.

## Sources and coordinate system

- Station elements, platform tags and railway geometry: OpenStreetMap, fetched
  2026-11-22 from the public Overpass API. Raw responses are in the gitignored
  `data_raw/` (`osm_stations.json`, `osm_rail_geom.json`) and are not committed.
- OSM data © OpenStreetMap contributors, ODbL 1.0.
- Projection: the project's installed Sydney metre projection (WGS84 local
  equirectangular tangent plane): origin `-33.873, 151.208`,
  `x = (lon - 151.208) * 92459.893`, `z = (-33.873 - lat) * 111019.656`.
  X is east, Z is south, 1 unit = 1 m, Y is up.
- Stage B bounds (`sydney/world/stage_b/world.json`):
  `x -2700.0 … 2265.3`, `z -2497.9 … 2609.0`.
- Existing authored interiors: `sydney/railway/station_interiors.gd`.

## Station inventory

“Mapped mainline tracks” is a count of distinct OSM `railway=rail` centerlines
within **55 m** of the station element, excluding `service=yard`, `siding` and
`crossover`. It is a mapped-geometry count, not an operational track diagram or a
promise that every counted road serves a platform. See the limitations below.

| Station | Line | OSM element | WGS84 | Local X, Z (m) | Platforms | Mapped mainline tracks (55 m) | Type | In Stage B | Authored | Code X, Z |
|---|---|---|---|---:|---:|---:|---|---|---|---|
| Central | City Circle / Inner West | `way/679354513` | -33.883419, 151.206111 | -174.7, 1156.8 | 28 | 11 | surface | yes | yes | -174.7, 1156.8 |
| Town Hall | City Circle | `way/740048665` / `node/1763901273` | -33.873792, 151.206886 | -103.0, 87.9 | 6 | 6 | underground | yes | yes | -106.3, 62.9 |
| Wynyard | City Circle / North Shore | `way/740048667` / `node/1886265379` | -33.866730, 151.207152 | -78.4, -696.1 | 6 | 4 | underground | yes | yes | -202.5, -778.2 |
| Circular Quay | City Circle | `way/740048069` / `node/1692720118` | -33.861526, 151.210063 | 190.7, -1273.8 | 2 | 2 | surface | yes | yes | 221.0, -1283.0 |
| St James | City Circle | `way/1115995149` | -33.870623, 151.211773 | 348.8, -263.9 | 2 | 2 | underground | yes | yes | 348.8, -263.9 |
| Museum | City Circle | `way/50940824` | -33.876000, 151.209928 | 178.3, 333.0 | 2 | 4 | underground | yes | yes | 178.3, 333.0 |
| Redfern | Inner West | `way/585998416` | -33.892186, 151.198719 | -858.1, 2130.0 | 12 | 16 | surface | yes | yes | -858.1, 2130.0 |
| Macdonaldtown | Inner West | `node/4735626773` | -33.896905, 151.185892 | -2044.1, 2654.0 | 2 | 14 | surface | no | no | — |
| Newtown | Inner West | `node/4735625743` | -33.897918, 151.179613 | -2624.6, 2766.3 | 2 | 7 | surface | no | no | — |
| Stanmore | Inner West | `node/6618892735` | -33.894513, 151.163907 | -4076.8, 2388.4 | 3 | 6 | surface | no | no | — |
| Petersham | Inner West | `node/1886240877` | -33.893911, 151.155373 | -4865.8, 2321.6 | 2 | 6 | surface | no | no | — |
| Lewisham | Inner West | `node/6618892736` | -33.893369, 151.147627 | -5582.0, 2261.3 | 2 | 9 | surface | no | no | — |
| Summer Hill | Inner West | `node/1886240903` | -33.890459, 151.138723 | -6405.3, 1938.3 | 3 | 9 | surface | no | no | — |
| Ashfield | Inner West | `node/1886240860` | -33.887658, 151.125818 | -7598.6, 1627.3 | 5 | 6 | surface | no | no | — |
| North Sydney | North Shore | `node/4887412745` | -33.841215, 151.207464 | -49.6, -3528.8 | 4 | 2 | underground | no | no | — |
| Milsons Point | North Shore | `node/1829323375` | -33.845863, 151.211791 | 350.5, -3012.8 | 2 | 2 | elevated | no | yes | 350.4, -3014.8 |

Platform counts are the OSM `platforms` tag on the station element. Where a
station has both a station way and a station node, the way is the primary
geometry and the node is the transit/entrance reference; both IDs are listed.

## Bounds result

Inside current Stage B bounds:

- Central, Town Hall, Wynyard, Circular Quay, St James, Museum, Redfern.
- Surry Hills, Railway Square and the Devonshire Street Tunnel corridor are also
  inside the bounds; they are precinct work, not new station records.

Outside current Stage B bounds:

- Macdonaldtown is only ~45 m beyond the southern bound (`z 2654.0` vs
  `maxZ 2609.0`), so a small south-west extension reaches it.
- Newtown, Stanmore, Petersham, Lewisham, Summer Hill and Ashfield require the
  Inner West corridor extension (to about `x -7600` for Ashfield).
- North Sydney and Milsons Point require a north-shore extension past
  `minZ -2497.9`; Milsons Point is at `z -3012.8` and North Sydney at
  `z -3528.8`.

These extensions are the reason Phase 2E must extend terrain and the world
bounds; placing stations without that terrain would violate the brief.

## Discrepancies against the current authored layout

The audit found real position differences between OSM and the current
`station_interiors.gd` data. OSM is the source of truth for the milestone, so
these must be resolved rather than preserved silently:

| Station | OSM local X, Z | Authored X, Z | Difference / note |
|---|---:|---:|---|
| Town Hall | -103.0, 87.9 | -106.3, 62.9 | ~25 m south in the authored layout; the station way runs north–south, so this is a platform-centre offset. |
| Wynyard | -78.4, -696.1 | -202.5, -778.2 | ~150 m west/south. The authored position is at the OSM station **node** (`node/1886265379`, -202.5, -778.2), while the station way centroid is east of it. The rail route uses the node vicinity, so the interior and platform shell are not at the same anchor. |
| Circular Quay | 190.7, -1273.8 | 221.0, -1283.0 | ~32 m east. The authored point sits between the OSM station way centroid and station node (251.4, -1292.3). |
| Redfern | -858.1, 2130.0 | -858.1, 2130.0 | Match. The 12-platform station way spans ~235 m east–west; the authored interior is a single platform dressing, not the full station. |
| Central | -174.7, 1156.8 | -174.7, 1156.8 | Match at the centroid, but the station way spans ~400 m and 28 platform faces. The authored interior builds one 110 m platform. |

The Central and Redfern interiors are therefore representative single-platform
dressing, not complete reconstructions of their real platform groups. The 2B/2D
work must replace that assumption with the mapped platform and track layout.

## Track-count limitations

- The 55 m count is deliberately local. Central's 28 platform faces span about
  400 m; the count of 11 describes the roads immediately around the station
  element, not all 28 platform roads. The full throat must be derived from the
  mapped railway ways when the station is rebuilt.
- Large yards and junctions (Macdonaldtown/Eveleigh, Redfern, Lewisham) have many
  parallel mapped roads. Counts there include running lines and non-platform
  roads within the radius; they are not a platform-road count.
- OSM ways can be split into multiple way IDs for the same physical track. The
  count treats each distinct mapped centerline as one; it does not merge
  fragments across the whole corridor.
- Where OSM has no `platforms` tag the count is marked by the station element's
  own mapping; all 16 stations in this milestone do carry a platform count.

These limitations are acceptable for planning, but they are not a substitute for
a surveyed track diagram. Any later claim about platform roads must cite the
mapped geometry used, not this summary count.

## Reusable station component library

The monolithic interiors builder has been split into:

- `sydney/railway/station_components.gd` — reusable presentation components:
  `room`, `ticket_hall`, `platform_dressing`, `canopy`, `signage`, `lights`,
  `stairs`, and `make_palette`.
- `sydney/railway/station_interiors.gd` — the existing authored station
  definitions and placement. It now delegates all repeated dressing to the
  component library and owns only station specs, openings and the descent cut.

The library keeps the previous geometry and collision behaviour:

- `room()` creates the solid floor, walls, ceiling and tiled bands.
- `ticket_hall()` creates Opal gates, ticket machines, benches, bins and the
  departure board.
- `platform_dressing()` creates platform edge strips, tactile bands, seating,
  help points, overhead signs and lighting.
- `stairs()` creates solid steps and slim inclined handrails.
- `canopy()` is a new reusable surface-platform canopy (posts, roof and fascia)
  for the Inner West stations; it is not applied to the existing interiors yet.
- `make_palette()` applies per-station colour overrides without mutating the
  shared defaults.

Usage from a station builder:

```gdscript
const StationComponents := preload("res://sydney/railway/station_components.gd")

var palette := StationComponents.make_palette({
    "tile_floor": Color("8b857a"),
    "canopy": Color("4f5b60"),
})
var hall := StationComponents.room(root, Vector3(0, y, 0), Vector3(30, 4.5, 16), palette)
StationComponents.ticket_hall(hall, Vector2(30, 16), palette)
StationComponents.platform_dressing(platform, 96.0, 14.0, "Newtown", false, palette)
```

The existing `cbd_rail_vertical_test.gd` still resolves the `StationInteriors`
node and its openings; no node names or public static helpers were removed.

## Remaining work

- Rebuild Central's and Redfern's platform groups from the mapped track and
  platform geometry before claiming those stations complete.
- Resolve the Town Hall, Wynyard and Circular Quay anchor discrepancies above
  when the City Circle is rebuilt.
- Extend Stage B bounds and terrain for Macdonaldtown through Ashfield and for
  the North Shore before placing those stations.
- Add station-specific identity data (palette, canopy, entrance layout) to the
  component library as each station is built; the library is deliberately
  presentation-only and does not define track alignment.

Manual in-game verification is still required for all existing interiors; the
headless parse and existing rail tests do not verify visual appearance.
