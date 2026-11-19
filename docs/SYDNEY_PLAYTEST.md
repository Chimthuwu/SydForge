# Sydney playtest guide

How to open the Sydney Stage A world in the Godot editor and play it yourself,
without touching District Zero or the normal startup.

## 1. Project

Open **`Z:/GITHUB/_GAMES/New folder/project.godot`** with Godot 4.7.2.

The project's main scene is still `res://scenes/district.tscn` (District Zero).
Pressing **F5** therefore still starts the original game; nothing about the
normal startup changed.

## 2. Scenes

Three Sydney entry points exist; pick whichever you want to test.

| Scene | Root node | Starts at |
|---|---|---|
| `res://sydney/sydney_test.tscn` | `SydneyPlaytest` | Circular Quay promenade, looking across the cove at the Opera House |
| `res://sydney/sydney_opera_test.tscn` | `SydneyOperaPlaytest` | Opera House forecourt, facing the steps |
| `res://sydney/sydney_bridge_test.tscn` | `SydneyBridgePlaytest` | Southern bridge approach, facing north along the eastern walkway |

## 3. Launch

Open one of them and press **F6** (Run Current Scene).

That is all. There is no flag, no environment variable and no command line. The
scenes force the same Sydney branch that `PLAY_SYDNEY.cmd` selects with
`-- --sydney`.

From a terminal:

```bash
Godot_v4.7.2-stable_win64.exe --path "Z:/GITHUB/_GAMES/New folder" res://sydney/sydney_test.tscn
Godot_v4.7.2-stable_win64.exe --path "Z:/GITHUB/_GAMES/New folder" res://sydney/sydney_opera_test.tscn
```

## 4. What is running

All three scenes are **the real game**:

- root scripts `scripts/sydney_district.gd` and `scripts/sydney_opera_district.gd`,
  which extend `scripts/district.gd` and only override the Sydney switch, the
  spawn, the opening heading and the HUD line;
- the actual `SydneyWorld` importer and Stage A export, including the shoreline
  collision;
- the existing `BoomPlayer` character controller (capsule, sprint, jump, step
  assist, shoot, melee, reload, vehicle entry);
- the existing `BoomCamera` spring-arm rig;
- the existing HUD, messages, tracer/impact effects and four `ArcadeCar`s;
- the authored Opera House landmark added by `SydneyWorld`.
- the Harbour Bridge, with road, eastern walkway, railway, pylons and bounded shore connections.

The bridge scene adds `scripts/sydney_bridge_district.gd`, relocates the four
existing cars to the approaches, and provides **N** to switch shore while on foot.
It does not change the player, vehicle, camera or HUD implementations.

District Zero, the main scene, gameplay scripts and the Stage A export are
unchanged.

## 5. Controls

| Input | Action |
|---|---|
| `W A S D` | Move |
| Mouse | Look |
| `SHIFT` | Sprint |
| `SPACE` | Jump |
| Left mouse | Fire pistol |
| Right mouse | Aim (tighter camera) |
| `R` | Reload |
| `F` | Melee |
| `E` | Enter / exit the nearest vehicle |
| `F5` | Respawn at the scene's spawn point |
| `ESC` | Release / capture the mouse |
| `N` (bridge scene only) | Switch between southern and northern approach spawns while on foot |

Stairs up to 0.6 m are climbed automatically by walking into them, so the Opera
House steps need no jump.

## 6. Spawns

- **Circular Quay:** **(219.9, 0.3, −1755.7)**, facing east across Sydney Cove
  toward the Opera House about 440 m away. A derived footpath vertex on land,
  outside every water ring and clear of every building.
- **Opera House forecourt:** **(632.1, 0.3, −1650.9)**, standing on the plaza
  about 7 m in front of the lowest of the 24 podium risers, facing the shells.

The export's normal spawn (George Street / Town Hall, `-42.8, −466.5`) is still
used by `PLAY_SYDNEY.cmd`; only these scenes override it.

**Bridge:** spawn is derived from the fourth resampled southern approach section,
21 m east of its centreline, on the pedestrian surface. The optional northern
spawn is four sections before the Lavender Street exit. Both face the bridge.
Select `north_start` on the scene root before F6, or press N during play.

## 7. Getting around

**From the quay:** the Opera House is straight ahead across the cove. Walk east
along the water's edge toward Bennelong Point.

**From the forecourt:** walk straight forward. The 24 risers climb 12 m to the
podium deck; walk back down the same way. The shells, foyer glazing and deck are
all walkable.

**Water:** the harbour is bounded. You cannot walk or jump into Sydney Cove; the
barrier sits exactly on the rendered shoreline, so you can follow the coast
right up to the water.

**Vehicles** spawn at the export's Town Hall area, not at the quay or the Opera
House, so expect to walk to them.

**Bridge scene:** follow the separated eastern walkway north through the pylon
portals and across the harbour. The graded northern approach reaches the Lavender
Street exit and the small Alfred Street/Fitzroy Street road area. Turn and return
along the same walkway. For a car, walk back to the ground-level opening at the
start of the approach and cross to the road; two cars wait in separate northbound
lanes. Two more are at the northern approach. Use E near a car, then W to drive.
The bridge uses a fixed four-lanes-each-way, keep-left layout. Follow the arrows.

## 8. Known limitations

- **Water is impassable, not swimmable.** There is no swimming, wading or boat
  interaction. The invisible barrier follows the source water polygon, which is
  coarse for the harbour.
- **Step assist is limited to 0.6 m.** Taller ledges still need a jump.
- **Stage A has no wharf geometry**, so there is no pier deck to walk out onto.
- **The environment is Stage A plus the bounded bridge extension**: 930 buildings
  (7 with authored facades), flat terrain, no traffic, pedestrians or interiors.
- **Bridge approach elevations and lane allocation are simplified.** They are
  graded to the existing flat world, not a surveyed interchange. Railway tracks
  are decorative. No North Shore city was generated. See
  [the Phase 5 report](SYDNEY_HARBOUR_BRIDGE_PHASE5.md) for dimensions and limits.
- **The Opera House roof is an approximation** — a parametric sail surface over
  the real OSM podium, not surveyed sphere-section geometry. See
  `docs/SYDNEY_OPERA_HOUSE_PHASE3.md`.
- **The stepped apron looks flat from the plaza** because the landmark uses one
  stone material; the steps are real collision, they just read as a pale surface
  from below.
- The first two seconds hold the opening heading, because `district.gd` captures
  the mouse in `_ready` and the cursor jump would otherwise spin the camera away
  from the landmark.
- If the Sydney world ever fails to load, the scenes fall back to District Zero
  and log the reason to the console; they will not show an empty scene.

## 9. Checking the scenes still work

```bash
APPDATA=./.runtime ./Godot_v4.7.2-stable_win64_console.exe --path . \
  --script res://tests/sydney_playtest_test.gd --log-file tests/sydney_playtest.log

APPDATA=./.runtime ./Godot_v4.7.2-stable_win64_console.exe --path . \
  --script res://tests/sydney_physics_test.gd --log-file tests/sydney_physics.log
```

The first launches the Circular Quay scene, checks the player, camera, HUD,
vehicles, Opera House and podium deck, and writes
`tests/sydney_playtest_spawn.png` and `tests/sydney_playtest_opera.png`.
The second drives both scenes for the water barrier, the stairs up and down, the
jump, the building wall and the forecourt spawn, and writes the five
`tests/phase4_*.png` captures via `tests/sydney_phase4_visual.gd`.

Both must be run windowed (without `--headless`) when they save images.
