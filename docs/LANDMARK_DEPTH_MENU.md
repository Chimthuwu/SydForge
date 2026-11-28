# Landmark depth menu — pick the next silhouettes

_Generated 2026-11-29 from `sydney/world/stage_b/world.json` (OSM © OpenStreetMap
contributors, ODbL) after the St Andrew's + GPO step (DECISION 9459065)._
_Purpose: the owner asked for "landmarks properly implemented"; this is the
pick-list of named CBD buildings that still render as the generic striped
shell, ranked by how close they stand to a menu spawn. Pick any and a worker
can author it the same way as QVB / Town Hall / St Mary's / Sydney Tower /
St Andrew's / the GPO (bespoke OSM-footprint mass + signature silhouette +
regression test + windowed capture)._

## Already authored (do not re-pick)

| Landmark | OSM id | Signature |
|---|---|---|
| Sydney Town Hall | `way/104948253` | colonnade + clock tower + corner domes |
| Queen Victoria Building | `way/40717424` | green copper dome + arcades |
| St Mary's Cathedral | `way/16749128` | twin west spires + gabled nave |
| St Andrew's Cathedral | `way/104948254` | twin pinnacled spires + rose window (2026-11-29) |
| Sydney GPO | `way/282238525` | Martin Place colonnade + campanile (2026-11-29) |
| Sydney Tower Eye | `way/389002928` | 283 m pod + golden turret + mast (2026-11-29) |
| Anzac Memorial + Pool of Reflection | civic group | art deco tower + reflecting pool |
| Circular Quay / Darling Harbour wharves, Pyrmont Bridge truss | civic group | wharf pavilions + static ferries |

## Candidates still on the generic shell (ranked by spawn proximity)

| Landmark | OSM id | h (m) | Position (x, z) | Nearest spawn | Suggested signature |
|---|---|---|---|---|---|
| Dymocks Building | `way/544415835` | 38 | (-58, -339) | george_street 19 m | heritage sandstone base + cream 1929 tower; George St corner read |
| Westfield Sydney (Central Plaza) | `way/214485734` | 26 | (-37, -296) | george_street 29 m | glass retail podium; sits opposite the GPO axis |
| Overseas Union Bank | `way/317347811` | 45 | (276, -557) | martin_place 25 m | 1980s granite slab closing Martin Place's east vista |
| Mid City Centre | `way/270319610` | 16 | (-33, -358) | george_street 37 m | 1970s arcade block between Dymocks and the GPO |
| Registrar General's Building | `way/16750415` | 13 | (489, -333) | hyde_park 41 m | sandstone classical pavilion on Hyde Park's east side |
| Hong Kong House | `way/409035171` | 16 | (-164, -45) | town_hall 42 m | mid-block Druitt St infill (low value) |
| **Hyde Park Barracks** | `way/16749595` | 10 | (444, -378) | hyde_park 46 m | World Heritage 1819 dormer cube: hipped roof, clock, front portico |
| Sun Building | `way/387746751` | 38 | (266, -528) | martin_place 48 m | interwar commerical tower on Martin Place's north side |
| Customs House | transit node `Customs House Library` | ~20 | Quay block, ~215, -1440 | circular_quay ~80 m | classical portico + flat iron-lace roof at the Quay spawn |

## Notes for the picker

- Every candidate anchors to its real OSM footprint the same way the six
  authored landmarks do; no coordinates are guessed.
- Best depth-per-effort next: **Hyde Park Barracks** (world-heritage identity
  right at the Hyde Park spawn, currently a 10 m box) and **Customs House**
  (completes the Circular Quay spawn view opposite the wharves).
- Larger gates that stay owner-owned: the futuristic skyline density
  (`docs/CYBERPUNK_ASSET_GAP.md`), the DEM terrain pass, and the Central live
  train route (Inbox) all need either owner taste calls or data work outside
  the repo.
