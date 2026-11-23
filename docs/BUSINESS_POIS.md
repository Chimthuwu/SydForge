# Real Sydney businesses — OSM POI layer

## Result

Real businesses now come from OpenStreetMap rather than an authored brand list.
`sydney/world/businesses.json` is an offline extract inside the Stage B geo
bounds:

- south `-33.8965`, west `151.178798`, north `-33.8505`, east `151.2325`
- local plane matches `stage_b/world.json` (origin `-33.873, 151.208`,
  `x = Δlon × 92459.893`, `z = Δlat × 111019.656`)
- **189 mapped POIs**, each retaining its OSM type/id, WGS84 coordinates, brand,
  `shop`/`amenity`, opening hours and `brand:wikidata` where supplied.

No position is invented. Same-brand rows within 22 m are treated as one store
(node + building way duplicates). Fuel stations are omitted because
`sydney/world/fuel_stations.json` already owns them.

## Requested brands

| Brand | Mapped POIs in bounds |
|---|---|
| McDonald's | 11 |
| KFC | 7 |
| 7-Eleven | 10 |
| Woolworths (incl. Metro) | 16 |
| Coles | 7 |

Every requested brand has real mapped locations; none had to be omitted.

## Other chains found

| Brand | POIs | Brand | POIs |
|---|---|---|---|
| EzyMart | 22 | City Convenience | 11 |
| IGA | 14 | Subway | 12 |
| Chemist Warehouse | 9 | Fishbowl | 9 |
| BWS | 6 | Domino's | 6 |
| Guzman y Gomez | 6 | Hungry Jack's | 6 |
| Oporto | 6 | Officeworks | 4 |
| Quikstop | 4 | Daiso Japan | 3 |
| Friendly Grocer | 3 | Grill'd | 3 |
| Liquorland | 3 | ALDI | 2 |
| Harris Farm | 2 | Zambrero | 2 |
| Big W | 1 | David Jones | 1 |
| Kmart | 1 | Myer | 1 |
| Target | 1 | | |

## How placement works

`CbdBusinesses` (`sydney/cbd/cbd_businesses.gd`) loads the JSON during the world
build, never from the network.

1. Builds a 48 m spatial edge index of the buildings that actually exist in the
   scene (not footprints the sanitizer removed).
2. For each POI, prefers the footprint that **contains** the OSM point (a store
   inside a shopping centre), otherwise the nearest facade within 45 m.
3. Rejects authored heritage landmarks (Town Hall, QVB, St Mary's) and
   landmark-named buildings.
4. Snaps a storefront to the selected edge, oriented to the street normal, with
   a size and dressing appropriate to the kind (supermarket/trolley bay,
   fast-food menu board/awning, convenience, pharmacy green cross, liquor,
   general retail).
5. Avoids reusing a frontage or placing two signs within 5 m.

Real placements are exposed through `placed_points()`; the older parody retail
layer now skips any site within 18 m of one, so it dresses blocks without mapped
chains instead of covering them.

Woolworths and Coles remain owned by `cbd_supermarkets.gd` to avoid duplicate
enterable stores. That system now selects the nearest mapped branch of each
brand (OSM `way/387741340` and `node/20827870`) instead of a hand-placed anchor.

## Current real-world build

- 189 mapped POIs loaded.
- **131 storefronts placed**.
- 35 skipped with a recorded reason (no suitable facade / frontage already used
  / too close). Skips are listed in `stats["notPlaced"]` and are not moved to a
  convenient but wrong address.
- Business layer build cost: ~0.3–0.5 s (17 s before the spatial index).

Most skips are tenancies deep inside shopping centres where the containing
building's own OSM ring has no usable exterior edge, or a second brand on a
frontage already taken. `stats` reports the exact OSM id for each.

## Attribution

- Source: OpenStreetMap contributors.
- Licence: ODbL 1.0 — https://www.openstreetmap.org/copyright
- The committed JSON keeps the source, licence and method fields. Development
  fetch/processing scripts and the raw Overpass response live in gitignored
  `data_raw/`, so the game performs no network access.

## Tests

`tests/business_poi_test.gd` (20 checks, 0 failures):

- all five requested brands exist in the dataset;
- every POI is inside the Stage B bounds and projects back from its WGS84
  coordinates within 1 m;
- OSM ids are unique;
- a synthetic POI inside a building places one correctly oriented storefront
  with its source id and brand sign;
- authored landmarks are never used;
- Woolworths/Coles are not duplicated.

`tests/cbd_expansion_test.gd` still passes 54/0 with the layer in the real world.

## Limits

- Placement is facade-level, not unit-level: a chain inside a large centre may
  be signed on the centre's exterior rather than the exact internal tenancy.
- OSM coverage is uneven; the layer reports skips instead of filling gaps.
- No visual capture of individual storefronts was taken in this pass, so brand
  legibility at driving distance still needs a human look.
