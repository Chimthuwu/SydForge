# SydForge — 13 Integration Scenarios Manual Test Plan

**Purpose:** Verify the 13 shared integration scenarios from the vehicle/combat/skateboard brief work correctly in a live game session.

**Context:** Headless tests cover grind state machine, explosion chain damage, and vehicle physics. These 13 scenarios require visual/human confirmation of gameplay feel, camera, audio, and cross-system interactions.

---

## Test Environment
- Build: `main` branch, latest commit
- Mode: Windowed (`SPLOOGE_SYDNEY=1 ./Godot_v4.7.2-stable_win64_console.exe --path .`)
- Spawn: Any menu spawn (Central, Circular Quay, etc.)
- Time of day: Test both day and night for lighting/headlight scenarios

---

## Scenario Checklist

### Vehicle / Combat Scenarios

| # | Scenario | Steps | Expected | Headless Coverage | Status |
|---|----------|-------|----------|-------------------|--------|
| 1 | **Shoot car until explosion** | Enter any traffic car → Drive → Exit → Shoot car with pistol/rifle until it explodes | Car catches fire → explodes → wreck remains → debris/smoke particles | `gameplay_overhaul_test`: explosion_damage | ☐ |
| 2 | **Kill police** | Gain wanted level → Wait for police spawn → Shoot/kill officer | Officer dies → ragdoll → wanted heat increases → nearby units react | `gameplay_regression`: (partial) | ☐ |
| 3 | **Explosion near police/peds** | Detonate car (shoot or NOS) near police or pedestrians | Nearby units take chain damage → panic/flee → wanted escalates if police hit | `gameplay_overhaul_test`: explosion_chain_vehicle | ☐ |
| 4 | **High-speed bike** | Spawn motorbike (or steal) → Accelerate to max speed on arterial (Parramatta Rd, George St) | Stable handling → no wobble → NOS works → lean animation correct | `gameplay_overhaul_test`: bike_wheelie | ☐ |
| 5 | **B wheelie** | On motorbike → Hold B (wheelie) → Release | Front wheel lifts → rider leans back → smooth return on release | `gameplay_overhaul_test`: bike_wheelie, bike_wheelie_release | ☐ |
| 6 | **Sports cars in traffic** | Observe traffic on arterial roads → Identify STING/PHANTOM/APEX exotics | Exotics spawn in traffic (37% perf share) → vivid colours → enterable/stealable | `gameplay_overhaul_test`: traffic_variety | ☐ |
| 7 | **NOS in sports car** | Enter exotic sports car → Activate NOS (Shift) → Accelerate | NOS overlay appears → speed boost → intensity ramps/decays → audio cue | `gameplay_overhaul_test`: nos_activation, nos_cleanup | ☐ |

### Skateboard Scenarios

| # | Scenario | Steps | Expected | Headless Coverage | Status |
|---|----------|-------|----------|-------------------|--------|
| 8 | **RIGHT ALT skateboard** | On foot → Hold RIGHT ALT → Mount board → Release to dismount | Smooth mount/dismount → board follows player → no stuck state | `gameplay_overhaul_test`: skate_mount, skate_dismount | ☐ |
| 9 | **Ollie + tricks** | On skateboard → SPACE (ollie) → Arrow combos (tricks) | Ollie height correct → trick animations play → land smoothly | `gameplay_overhaul_test`: (partial) | ☐ |
| 10 | **Grind rail/ledge** | Approach ledge/rail at speed → Ollie onto it → Grind | Grind state enters → sparks/sound → rider pose locked to rail | `gameplay_overhaul_test`: grind_mount, grind_state_enter, grind_sustain, grind_exit | ☐ |
| 11 | **Boost out of grind** | While grinding → Press boost key (Shift) → Exit grind | Boost launches player off rail → clean exit → no physics glitch | `gameplay_overhaul_test`: grind_exit | ☐ |

### Cross-Mode Scenarios

| # | Scenario | Steps | Expected | Headless Coverage | Status |
|---|----------|-------|----------|-------------------|--------|
| 12 | **Enter vehicle while skateboarding** | On skateboard → Approach car → Press E to enter | Clean transition → board despawns → vehicle entered → camera switches | `gameplay_overhaul_test`: (not covered) | ☐ |
| 13 | **Exit back to walking** | In vehicle → Press E to exit → Walk around | Clean exit → player spawns on foot → camera third-person → no stuck | `gameplay_regression`: vehicle_exit | ☐ |

---

## Visual / Audio Checks (Per Scenario)

- [ ] No clipping/z-fighting at transitions
- [ ] Particle effects visible (sparks, smoke, debris)
- [ ] Audio cues play (engine, NOS, grind, explosion, weapon)
- [ ] Camera transitions smooth (third-person ↔ vehicle ↔ skateboard)
- [ ] HUD updates correctly (health, speed, wanted, weapon)
- [ ] No script errors in output log

---

## Regression Guard

After any future change, re-run this checklist. Headless suites that guard these scenarios:
- `tests/gameplay_overhaul_test.gd` — 18/18 (grind, explosion chain, NOS, bike, skate mount)
- `tests/gameplay_regression.gd` — 23/23 (vehicle enter/exit, pedestrian move, node stability)
- `tests/vehicle_headlights_test.gd` — 32/0 (headlight beams, toggle)
- `tests/lighting_pause_test.gd` — 17/0 (AI headlight budget, pause overlay)
- `tests/settings_input_test.gd` — 12/0 (input remap, sensitivity, invert-Y)

---

## Sign-Off

| Scenario | Tester | Date | Build Commit | Notes |
|----------|--------|------|--------------|-------|
| 1-7 (Vehicle/Combat) | | | | |
| 8-11 (Skateboard) | | | | |
| 12-13 (Cross-Mode) | | | | |

---

## Related Files

- `tests/gameplay_overhaul_test.gd` — headless grind/explosion/NOS/bike/skate assertions
- `tests/gameplay_regression.gd` — vehicle enter/exit, pedestrian, node stability
- `scripts/skateboard.gd` — ollie, grind, boost, mount/dismount logic
- `scripts/vehicle.gd` / `vehicle_combat.gd` — NOS, damage, explosion, enter/exit
- `scripts/player.gd` — on-foot locomotion, weapon, wanted
- `scripts/wanted_system.gd` — police spawn, escalation, officer_killed handling