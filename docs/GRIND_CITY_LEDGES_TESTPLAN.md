# SydForge — Grind on Real City Ledges/Rails Test Plan (L52)

**Purpose:** Verify grind mechanics work on actual city geometry (ledges, rails, curbs) from multiple viewpoints.

**Context:** Grind state machine tested headless (`gameplay_overhaul_test`: mount, state_enter, sustain, exit). Raycast-based entry requires real geometry. Visual confirmation needed for rail alignment, spark particles, exit trajectory, and camera.

---

## Test Locations (Known Grindable Features)

| Location | Feature Type | Coordinates (approx) | Notes |
|----------|--------------|---------------------|-------|
| Circular Quay | Stone ledge / seawall | x≈200, z≈-1500 | Long straight ledge, water side |
| The Rocks | Sandstone coping | x≈100, z≈-1400 | Historic district, varied heights |
| Central Station | Platform edges | x≈-40, z≈-460 | Multiple platform copings |
| Darling Harbour | Modern railings | x≈-200, z≈-800 | Metal rails, good for speed |
| Barangaroo | Concrete benches/ledges | x≈-300, z≈-600 | New district, clean geometry |
| George St (CBD) | Kerb cuts / planter edges | x≈0, z≈-500 | Street furniture, varied |
| Parramatta Rd (West) | Median barriers / kerbs | x≈-3000 to -7000 | New extended area, test coverage |

---

## Test Matrix

| Test | Approach | Action | Expected |
|------|----------|--------|----------|
| 1. Straight grind | Parallel to ledge | Ollie (SPACE) onto ledge → Hold grind | Grind enters → sparks → rider locks to rail → sustain > 3s |
| 2. Angled approach | 30-45° to ledge | Ollie at angle → Land on rail | Grind catches → auto-aligns to rail direction |
| 3. Speed variation | Slow (8 km/h) to fast (25 km/h) | Vary approach speed | Min speed ~8 km/h → max sustainable ~25 km/h |
| 4. Turn during grind | Curved rail/ledge | Grind → Steer (A/D) | Rider leans → follows curve → exits clean at end |
| 5. Boost out of grind | Mid-grind | Press NOS/Boost (N) | Launch off rail → airborne → land smoothly |
| 6. Manual exit | Mid-grind | Press Jump (SPACE) | Clean ollie off → airborne → land |
| 7. Grind to vehicle | Near parked car | Grind → Approach car → Press E (enter) | Smooth transition → board despawns → vehicle entered |
| 8. Multi-ledge chain | Adjacent ledges | Grind ledge 1 → Ollie → Grind ledge 2 | Chain grinds → no speed loss → fluid |
| 9. Night grind | Any location at night | Same as above | Sparks visible → grind glow → particles lit |
| 10. Camera angles | All above | Toggle camera (C) / orbit | Camera follows grind → no clipping → smooth |

---

## Visual / Audio Checks

- [ ] Spark particles emit from board-truck contact point
- [ ] Grind sound (metal-on-stone/metal) plays and loops
- [ ] Rider pose: crouched, board perpendicular to rail
- [ ] Board visual rotates to match rail direction
- [ ] No clipping through rail/ledge geometry
- [ ] Exit trajectory predictable (forward + slight up)
- [ ] Camera doesn't jitter during grind entry/exit

---

## Headless Coverage

- `gameplay_overhaul_test`: grind_mount, grind_state_enter, grind_sustain (0.63), grind_exit
- `gameplay_regression`: grind_mount, grind_state_enter, grind_sustain (FAIL: 0.00), grind_exit
- Raycast entry NOT tested headless (requires world geometry)

---

## Known Issues

- `gameplay_regression` grind_sustain fails in headless (grind_stable=0.00) — investigate
- Inner West district not in menu (build time) — new Parramatta Rd area untested
- Some heritage ledges (The Rocks) may have collision mismatch

---

## Sign-Off

| Location | Straight | Angled | Speed Var | Turn | Boost Exit | Manual Exit | Chain | Night | Camera |
|----------|----------|--------|-----------|------|------------|-------------|-------|-------|--------|
| Circular Quay | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| The Rocks | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| Central | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| Darling Harbour | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| Barangaroo | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| George St | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| Parramatta Rd | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |

---

## Related Files

- `scripts/skateboard.gd` — `_check_grind_entry()`, `_grind()`, raycast logic
- `scripts/skateboard.gd` — `_grind_stable`, `_jump_buffer`, grind exit
- `tests/gameplay_overhaul_test.gd` — headless grind assertions
- `tests/gameplay_regression.gd` — headless grind assertions (sustain FAIL)