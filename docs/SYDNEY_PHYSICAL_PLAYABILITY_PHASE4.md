# Phase 4 — Sydney physical playability

Water collision, natural stair traversal on the Opera House podium, and a second
playtest entry point on the forecourt.

Starting point: `docs/SYDNEY_PLAYTEST.md` and the Phase 3 landmark
(`docs/SYDNEY_OPERA_HOUSE_PHASE3.md`). Nothing in this phase changed the
landmark geometry, the Stage A export, the water renderer, vehicles, combat,
enemies, traffic or the District Zero startup.

## 1. Harbour collision

**Problem.** Stage A renders water as a flat mesh and gives the whole slice one
ground collision box, so the harbour was walkable.

**Approach.** A single invisible barrier is generated from the same rings that
are drawn as water, so the barrier is exactly the visible coastline:

- every ring is closed and walked edge by edge;
- each edge becomes one vertical quad (two triangles) from `y = 0` to
  `y = 2.4 m`;
- all quads go into **one** `StaticBody3D` + one `ConcavePolygonShape3D`
  (`WaterCollision`), with `backface_collision = true` because rings are wound
  per source polygon;
- edges shorter than 0.05 m are dropped.

No rectangles, no raycasts, no per-frame work, no collision volume filling the
harbour. Land outside the water polygons is unaffected by construction, so the
Circular Quay promenade, the Opera House forecourt and any future wharf deck
remain walkable.

**Measured cost.** 16 rings, 170 edges, 340 triangles, 0.362 ms of build time,
one physics body.

**Why 2.4 m.** The player's jump apex is about 1.33 m, so the barrier cannot be
jumped over and the invisible wall is never reachable from above.

**Verification.** Walking at the cove for 3 s stops the player 1.42 m from the
nearest water edge and never inside a water polygon; jumping into it while
pressing forward also fails to cross.

**Limitation.** The barrier follows the export's water ring, which is a coarse
66-vertex polygon for the harbour, so the invisible wall is as simplified as the
rendered shore. There is no swimming or wading: water is simply impassable.

## 2. Step traversal

`scripts/player.gd` keeps its architecture (one `CharacterBody3D`,
`move_and_slide`, coyote time, jump buffer). Two additions:

- **Step assist.** After `move_and_slide`, if the player was grounded, is now
  against a wall and not rising, `_try_step_up()` lifts the body by
  `STEP_HEIGHT` (0.6 m), retries the frame's horizontal motion pushed a further
  capsule radius past the riser, then drops back. The attempt is reverted unless
  there is headroom, the horizontal move is clear, the landing is within 0.6 m
  above the start, and the landing surface is no steeper than 60°.
- **Downward snap.** `floor_snap_length` is 0.6 m while walking and 0.05 m while
  rising, so descending a 0.5 m riser is a snap instead of a free-fall, and a
  jump is never pulled back to the floor.

**Maximum step height: 0.6 m.** The Opera House risers are 0.5 m, so they clear
with margin, while a 1 m ledge or a building wall cannot be climbed.

Two details matter and cost one iteration each:

1. Lifting exactly the step height leaves the capsule's round bottom landing on
   the nose of the riser, producing a ~46° contact normal. The first version
   rejected that (it is outside `floor_max_angle`, 45°) and the player stopped
   dead at the first riser.
2. Landing on the nose also wedged the capsule, which then ratcheted upward when
   walking *down* the stairs. Pushing the retry move past the riser by the
   capsule radius makes the body settle on the tread instead.

**Verification.** From the forecourt the player walks 7 m of plaza and climbs all
24 risers of 0.5 m to the deck (y 0.00 → 12.02) without pressing jump, and walks
back down to the forecourt (y 0.00) without leaving the floor. Jump apex from
flat ground is +1.40 m, and a 31 m building wall stops the player after 2.5 m at
ground level.

## 3. Playtest entry points

| Scene | Root node | Start |
|---|---|---|
| `res://sydney/sydney_test.tscn` | `SydneyPlaytest` | Circular Quay promenade, facing the Opera House across the cove |
| `res://sydney/sydney_opera_test.tscn` | `SydneyOperaPlaytest` | Opera House forecourt, facing the steps |

Both are the same world, player, camera, HUD, vehicles, enemy and landmark; only
`_playtest_spawn()`, `_playtest_look_target()` and `_playtest_message()` differ.
`scripts/sydney_district.gd` holds the shared entry point and
`scripts/sydney_opera_district.gd` overrides those three functions.

Forecourt spawn: **(632.1, 0.3, −1650.9)**. Derived from the landmark: the
podium ring spans u = −85…+85 along its long axis, the 24 steps occupy
u = −86…−109, so this point is on the paved plaza about 7 m in front of the
lowest riser. It is 67 m from water, 850 m from the nearest building, and the
line to the podium crosses no water and no building.

## 4. Tests

`tests/sydney_physics_test.gd` — **31 checks, 0 failures**, against the real
scenes:

- water: barrier exists, covers all 16 rings in one light mesh, the player cannot
  walk or jump into the cove, stops at the rendered shoreline, stays on the quay;
- land movement still works;
- forecourt: spawn on land, at ground level, on the floor, at Bennelong Point;
  Opera House visible and collidable;
- stairs: climbs all 24 risers without jumping, stands on the deck, walks back
  down and is grounded;
- jump still works and returns to the ground;
- a 31 m wall is impassable and is not passed through.

Regression results:

| Suite | Result |
|---|---|
| `sydney_physics_test.gd` | 31 / 0 |
| `sydney_playtest_test.gd` | 22 / 0 |
| `sydney_scene_test.gd` (`SPLOOGE_SYDNEY=1`) | 23 / 0 |
| `sydney_geometry_test.gd` | 107 / 0 |
| `opera_house_test.gd` | 57 / 0 |
| `architecture_test.gd` | 80 / 0 |
| `architecture_clearance.py` | 29 / 0 |
| District Zero `integration.gd` | 63 / 2 (pre-existing `melee damages nearby enemy`, `enemy defeat grants reputation`) |

The two District Zero failures are the same baseline failures documented in
earlier phases; nothing was changed to make them pass.

## 5. Launches

Both scenes were launched in Godot 4.7.2 (windowed, not headless) with
`--quit-after 320` and with the capture script, exit code 0 and no errors or
warnings in the log.

## 6. Captures

| File | What it shows |
|---|---|
| `tests/phase4_quay.png` | Circular Quay spawn, Opera House across the cove |
| `tests/phase4_harbour.png` | Player stopped at the harbour boundary |
| `tests/phase4_forecourt.png` | Forecourt spawn, stepped podium and shells ahead |
| `tests/phase4_steps.png` | Player partway up the steps, camera pitched down |
| `tests/phase4_podium.png` | Player on the podium deck between the shells |

## 7. Performance

World build, one run before and after this phase (milliseconds):

| Step | Before | After |
|---|---|---|
| Ground | 0.94 | 0.95 |
| Water | 3.24 | 3.03 |
| WaterCollision | — | 0.36 |
| Parks | 6.80 | 6.22 |
| Roads | 87.83 | 90.43 |
| Footpaths | 113.80 | 113.85 |
| Crossings | 79.93 | 85.93 |
| Buildings | 1526.88 | 1578.60 |
| Landmarks | 102.01 | 101.59 |
| Total | 1921.42 | 1980.96 |

The barrier itself is 0.36 ms and 340 triangles. The total moved by +60 ms, all
of it in the buildings step, which varies run to run on this machine (the
landmark and water steps did not grow); this is not a measured cost of the
barrier. No FPS claim is made.

## 8. Known limitations

- Water is impassable, not swimmable; there is no wading, drowning or boat
  interaction.
- The barrier is invisible and sits exactly on the rendered water edge, so it is
  coarse wherever the source water polygon is coarse.
- Stage A contains no wharf or pontoon geometry, so "wharves remain usable" was
  verified structurally (the barrier only follows water rings) rather than on an
  actual wharf deck.
- The step assist climbs up to 0.6 m; taller ledges still need a jump or a
  route. The Opera House steps are 0.5 m, so they are climbable everywhere.
- The stepped apron still reads as a broad pale surface from the plaza, because
  the landmark uses one flat stone material; that is a Phase 3 visual matter,
  unchanged here.
- The 2 s opening-heading hold from Phase 3 is still in the playtest entry
  point, because `district.gd` captures the mouse in `_ready` and the cursor
  jump would otherwise spin the camera.
