# SydForge — Rail Crossing Drive Test Plan (L86)

**Purpose:** Manual in-game drive test over the 14 repaired rail cutting crossings and the Central/Redfern approach.

**Context:** `rail_cut_road_collision_test.gd` verifies 14/14 deck colliders and 3/3 car drops land (headless). Visual confirmation needed for deck alignment, road surface continuity, collision feel, and approach geometry.

---

## 14 Rail Cutting Crossings (from `cbd_rail_network.gd`)

| # | Road | Approx Location | Deck Type | Notes |
|---|------|----------------|-----------|-------|
| 1 | George St (North) | x≈150, z≈-1200 | 4-lane arterial | Heavy traffic |
| 2 | Pitt St | x≈200, z≈-1100 | 2-lane one-way | Tram corridor adjacent |
| 3 | Castlereagh St | x≈250, z≈-1000 | 2-lane one-way | Narrow |
| 4 | Elizabeth St | x≈300, z≈-900 | 4-lane | Busy intersection |
| 5 | College St | x≈350, z≈-800 | 2-lane | Near Hyde Park |
| 6 | Liverpool St | x≈100, z≈-600 | 4-lane | East-west arterial |
| 7 | Goulburn St | x≈80, z≈-500 | 2-lane | Quiet |
| 8 | Park St | x≈60, z≈-400 | 2-lane | Near Town Hall |
| 9 | Bathurst St | x≈40, z≈-300 | 4-lane | Major east-west |
| 10 | Kent St | x≈-50, z≈-200 | 2-lane one-way | Northbound |
| 11 | Sussex St | x≈-100, z≈-100 | 2-lane one-way | Southbound |
| 12 | Day St | x≈-200, z≈0 | 2-lane | Darling Harbour access |
| 13 | Murray St | x≈-250, z≈100 | 2-lane | Pyrmont bridge approach |
| 14 | Parramatta Rd (West) | x≈-3000 to -5000 | 4-lane | New extended area |

---

## Central/Redfern Approach

| Segment | Description | Key Checks |
|---------|-------------|------------|
| Central Forecourt | Eddy Ave → Platform level | Smooth ramp, no step |
| Platform 1-4 | Under canopies | Clearance > 4.5m |
| Suburban Platforms | Platforms 16-23 | Stair/bridge access |
| Redfern Cutting | Cleveland St bridge | Deck continuity |
| Redfern Platforms | Local/regional | Pedestrian bridges |

---

## Drive Test Matrix

### Per Crossing (1-14)

| Check | Method | Pass Criteria |
|-------|--------|---------------|
| Visual continuity | Drive at 40 km/h | No visible gap/seam at deck joint |
| Collision feel | Drive at 60 km/h | No "clunk" or airborne moment |
| Deck width | Measure visually | Matches road lanes + 0.55m kerb each side |
| Parapet height | Visual + camera | 1.2m above deck, blocks fall |
| Night lighting | Drive at night | Deck lit, parapets visible |
| Rain/wet | Drive in rain | No hydroplaning on deck surface |
| Heavy vehicle | Hauler/truck | No bottom-out, suspension ok |
| Motorbike | Bike at speed | Stable, no wobble on expansion joints |

### Central/Redfern Approach

| Check | Method | Pass Criteria |
|-------|--------|---------------|
| Forecourt entry | From George St | Smooth transition, no curb strike |
| Platform canopy clearance | Drive under | >4.5m vertical clearance |
| Redfern bridge | Cleveland St | Deck continuous, no gap |
| Pedestrian bridge clearance | Drive under | >5m clearance |
| Station interior | Walk (not drive) | NavMesh connects, no stuck |

---

## Vehicle Classes to Test

- [ ] Commuter sedan (Comet)
- [ ] Sports car (Viper)
- [ ] Supercar (Phantom, Apex, Sting)
- [ ] Hauler (van)
- [ ] Motorbike
- [ ] Police car (pursuit mode)

---

## Visual / Audio Checks

- [ ] Asphalt texture continuous across deck
- [ ] Lane markings continue across deck (dashed/solid)
- [ ] Kerb strips (0.55m) visible on both sides
- [ ] Parapet collision: car hits parapet, not fall through
- [ ] Expansion joint sound: subtle "thump" not harsh
- [ ] Shadow continuity: deck casts/receives shadows correctly
- [ ] Reflection probes: wet deck reflects correctly

---

## Headless Coverage

- `tests/rail_cut_road_collision_test.gd`: 5/0 PASS
  - 14 crossings detected
  - 14/14 deck colliders exist
  - 14/14 rays solid at street level
  - 3/3 car drops land on decks
- `tests/cbd_rail_vertical_test.gd`: 16/16 PASS (corridor cut, no square holes)

---

## Sign-Off

| Crossing | 40 km/h | 60 km/h | Night | Rain | Heavy | Bike | Parapet | Notes |
|----------|---------|---------|-------|------|-------|------|---------|-------|
| 1. George St N | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | |
| 2. Pitt St | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | |
| 3. Castlereagh | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | |
| 4. Elizabeth | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | |
| 5. College | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | |
| 6. Liverpool | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | |
| 7. Goulburn | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | |
| 8. Park | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | |
| 9. Bathurst | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | |
| 10. Kent | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | |
| 11. Sussex | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | |
| 12. Day | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | |
| 13. Murray | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | |
| 14. Parramatta Rd | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | |
| Central Forecourt | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | |
| Redfern Bridge | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | |

---

## Related Files

- `sydney/cbd/cbd_rail_network.gd` — `_build_descent_cutting()`, crossing decks
- `sydney/cbd/cbd_world.gd` — `_build_descent_cut_ground()`, corridor cut
- `tests/rail_cut_road_collision_test.gd` — headless deck verification
- `tests/cbd_rail_vertical_test.gd` — corridor cut verification
- `shaders/asphalt.gdshader` — road surface rendering (cull_disabled)