# SydForge — Police Death / Wanted Escalation Test Plan (L53)

**Purpose:** Verify the complete wanted escalation chain: officer_killed → wanted heat increase → nearby units react → escalation tiers.

**Context:** `scripts/wanted_system.gd` manages heat, tiers, police spawning. Headless tests cover basic wanted but not full escalation chain. Requires live session for AI behavior, spawning, and multi-unit coordination.

---

## Escalation Tiers (from wanted_system.gd)

| Tier | Heat Range | Police Response | Spawn Distance |
|------|------------|-----------------|----------------|
| 0 | 0 | None | — |
| 1 | 1-50 | 1-2 patrol cars | 80-120m |
| 2 | 51-150 | 3-4 cars, roadblocks | 60-100m |
| 3 | 151-300 | 5+ cars, helicopter | 40-80m |
| 4 | 301-500 | SWAT, heavy armor | 30-60m |
| 5 | 500+ | Maximum response | 20-40m |

---

## Test Scenarios

### Scenario 1: Single Officer Kill
1. Gain wanted level 1 (hit police car / shoot near police)
2. Locate single officer on foot
3. Kill officer (shoot/melee)
4. **Expected:** Heat jumps +50 → Tier 2 → 2-3 additional units spawn within 30s

### Scenario 2: Multiple Officer Kill
1. Gain wanted level 2
2. Engage 2+ officers simultaneously
3. Kill both within 10s
4. **Expected:** Heat jumps +100 → Tier 3 → Helicopter spawns + roadblocks

### Scenario 3: Vehicle Officer Kill
1. Gain wanted level 2
2. Ram/destroy police car with officer inside
3. **Expected:** Heat +75 → Tier escalation → Immediate backup call

### Scenario 4: Escalation Decay
1. Reach Tier 3
2. Evade police (hide in alley/parking garage) for 60s
3. **Expected:** Heat decays → Tier drops → Police despawn/search mode

### Scenario 5: Civilian Collateral
1. High wanted (Tier 3+)
2. Explosion kills civilians near police
3. **Expected:** Extra heat per civilian → Faster escalation

### Scenario 6: Police Vehicle Theft
1. Steal police car (E while driver dead)
2. Drive in stolen police car
3. **Expected:** Instant Tier 3+ → All units hostile → Helicopter tracks

---

## AI Behavior Checks

| Behavior | Verification |
|----------|--------------|
| Officer seeks cover | ☐ Officers move behind vehicles/walls |
| Flanking | ☐ Units approach from multiple angles |
| Pursuit persistence | ☐ Units follow into alleys, buildings |
| Roadblock placement | ☐ Cars block intersections at Tier 2+ |
| Helicopter spotlight | ☐ Light tracks player at night Tier 3+ |
| SWAT tactics | ☐ Coordinated entry, flashbangs (Tier 4+) |

---

## Visual / Audio Checks

- [ ] Wanted stars UI updates correctly (top-right HUD)
- [ ] Police sirens audible, directional
- [ ] Helicopter rotor sound at Tier 3+
- [ ] Radio chatter / voice lines
- [ ] Police light bars flash (red/blue)
- [ ] Roadblock vehicles positioned correctly
- [ ] Dead officer bodies remain (ragdoll)
- [ ] Heat meter decays visibly when evading

---

## Headless Coverage

- `gameplay_regression`: Basic vehicle enter/exit, damage
- `gameplay_overhaul_test`: Explosion chain, NOS
- `wanted_system_test.gd`: 6/3 FAIL (stale baseline) — needs update
- No full escalation chain test in headless

---

## Sign-Off

| Scenario | Tester | Date | Build | Heat Delta | Tier Reached | Notes |
|----------|--------|------|-------|------------|--------------|-------|
| Single officer kill | | | | | | |
| Multi officer kill | | | | | | |
| Vehicle officer kill | | | | | | |
| Escalation decay | | | | | | |
| Civilian collateral | | | | | | |
| Police vehicle theft | | | | | | |

---

## Related Files

- `scripts/wanted_system.gd` — heat, tiers, spawning, decay
- `scripts/police_car.gd` — police AI, pursuit, roadblocks
- `scripts/vehicle_combat.gd` — vehicle damage, explosion
- `tests/wanted_system_test.gd` — stale baseline (6/3 FAIL)