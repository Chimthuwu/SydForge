# SydForge — Wheelie Rider Pose Test Plan (L51)

**Purpose:** Verify the motorbike wheelie rider pose stays correct while turning, accelerating, and braking.

**Context:** Wheelie logic implemented in `scripts/vehicle.gd` (bike class). Headless test `gameplay_overhaul_test` covers `bike_wheelie` (wheelie=0.41) and `bike_wheelie_release` (returned=0.00). Visual confirmation needed for rider lean, camera, and animation blending.

---

## Test Steps

| Phase | Action | Expected Visual |
|-------|--------|-----------------|
| 1. Mount | Spawn/steal motorbike → Enter (E) | Rider sits naturally, hands on bars |
| 2. Accelerate | Hold forward (W) → Build speed | Rider leans forward slightly |
| 3. Wheelie | Hold B (wheelie) at speed > 15 km/h | Front wheel lifts → rider leans back smoothly → `_wheelie_factor` > 0 |
| 4. Turn in wheelie | While wheelie held → Steer left/right (A/D) | Rider leans into turn → bike leans → front wheel tracks turn |
| 5. Brake in wheelie | While wheelie held → Tap brake (S) | Wheelie factor decreases → front wheel lowers gradually |
| 6. Release wheelie | Release B | Smooth transition back to two wheels → rider returns to neutral |
| 7. Wheelie + NOS | Wheelie + Hold NOS (Shift) | Combined effect → higher wheelie → boost particles |
| 8. Crash during wheelie | Hit obstacle while wheelie | Rider ragdolls correctly → bike tumbles |

---

## Key Variables to Monitor (Debug Overlay)

- `vehicle._wheelie_factor` (0.0 to 1.0)
- `vehicle.speed` (km/h)
- `vehicle.lean` (radians)
- Rider visual `rotation.x` (should lerp to ~0.12 when wheelie)

---

## Headless Coverage

- `gameplay_overhaul_test`: `bike_wheelie` (factor=0.41), `bike_wheelie_release` (returned=0.00)
- `gameplay_regression`: Not covered

---

## Sign-Off

| Test | Tester | Date | Build | Notes |
|------|--------|------|-------|-------|
| Straight wheelie | | | | |
| Wheelie + turn | | | | |
| Wheelie + brake | | | | |
| Wheelie + NOS | | | | |
| Crash recovery | | | | |

---

## Related Files

- `scripts/vehicle.gd` — `_do_wheelie()`, `_update_wheelie()`, bike class specs
- `scripts/vehicle_visual.gd` — rider pose lerp, lean application
- `tests/gameplay_overhaul_test.gd` — headless wheelie assertions