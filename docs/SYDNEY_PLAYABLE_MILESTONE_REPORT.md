# Splooge — Unified Sydney Playable Milestone

**Engine:** Godot 4.7.2  
**Status:** uncommitted; no push

## Canonical launch

- `project.godot` names the game **Splooge** and runs `res://scenes/main.tscn`.
- `scenes/main.tscn` is the canonical main game scene. It loads the existing
  gameplay through `scripts/sydney_cbd_district.gd`.
- The desktop `Sydney CBD (Stage B).cmd` was renamed in place to
  `C:\Users\Serge\Desktop\Splooge.cmd`. It runs Godot with the live project path;
  the project main-scene setting selects the canonical scene.
- The original desktop item launched
  `res://sydney/sydney_cbd_test.tscn` directly, which is why it was labelled
  **Sydney CBD (Stage B)**. The Stage B export is now world data used by the
  canonical game, not a separate export.

## Unified world and landmarks

The canonical world uses the Stage B Sydney export in the existing metre-based
projection. Its `CbdWorld` inherits the Stage A importer and loads the existing
Harbour Bridge, Opera House, and Phase 6A harbour water. Stage A and Stage B are
not layered together, avoiding duplicate roads/buildings. Existing development
and test scenes remain in place.

The Inner West files remain in the repository, but are not added to this world:
the Inner West export overlaps much of Stage B and would duplicate its urban
mesh/collision if loaded as a sibling without clipping. It also currently has
headless parse/runtime errors (see verification below); it was not used as a
reason to block this milestone.

New `sydney/cbd/cbd_landmarks.gd` content uses the Stage B OSM footprints and
coordinates, while preserving the surrounding city:

- **Queen Victoria Building:** retained OSM-footprint mass with a prominent
  green dome/cupola, clock lantern, arcaded façade rhythm, and roof turrets.
- **Sydney Town Hall:** retained OSM footprint with a taller clocktower, visible
  clock faces, sandstone colonnade, and roof cupolas.
- **St Mary’s Cathedral:** retained footprint with nave roof, twin towers,
  spires, buttresses, and a rose-window treatment.
- **Hyde Park:** retained park polygons and vegetation, with a cleared axial
  promenade, Archibald Fountain, Hyde Park Obelisk, and an Anzac Memorial/pool
  focal area.
- **Central Station:** authored grand-concourse/clocktower silhouette and
  repeated platform canopies anchored to the exported Central transit location.
- **Circular Quay:** wharf/terminal structures and static ferry silhouettes
  anchored to exported ferry stops.
- **Darling Harbour:** wharf structures and a steel truss treatment along the
  existing exported Pyrmont Bridge path.

Three authored building treatments replace the generic CBD shell for the same
named OSM footprints; their OSM-derived collision masses are retained.
Generated parcel fills that overlapped the Opera House podium were removed.
Landmark decoration is batched by material, keeping the added presentation mesh
count bounded. New wharf/ferry props are static visual dressing; they do not yet
have independent walkable collision or boat gameplay.

The asset-library index (`Z:\GITHUB\_ASSETS\ASSETS\INDEX.md`) contains general
building kits but no dedicated Sydney landmark models. These additions use
procedural geometry rather than importing unrelated or unverified models.
They are stylized recognizable silhouettes, not surveyed reconstructions.

## Player, weapon, and vehicle

- The single existing `BoomPlayer` now uses a first-person on-foot camera,
  mouse-look, WASD movement, sprint, jump, gravity, collision, and the existing
  step assist. The procedural pistol is camera-mounted; hitscan uses the camera
  aim ray and retains enemy damage/impact feedback.
- The single camera rig switches from first-person to a SpringArm third-person
  chase view while possessing a vehicle, then returns to first-person on exit.
  The existing player/vehicle possession state remains the control gate; there
  are no competing on-foot and vehicle controllers.
- The Viper sports car is at the Harbour Bridge overlook; the Comet remains at
  the southern bridge roadway entrance. The other cars retain their CBD export
  spawns. `E` enters/exits; safe-exit and speed checks remain active.
- Vehicle body pitch no longer lifts the wheel visuals: running gear stays
  attached to the chassis with bounded body pitch.
- Gun audio was not retuned; the user identified it as low priority. No traffic
  behaviors were added by this pass; the separate traffic-agent changes were
  preserved and not edited.

## Verification

### Automated

| Check | Result |
|---|---|
| `tests/main_game_test.gd` | **39 checks, 0 failures** — canonical Stage B world, Bridge/Opera/water, landmark modules, first-person weapon hit, Viper possession, third-person camera, drive/exit, and wheel ride-height |
| `tests/opera_house_test.gd` | **57 checks, 0 failures** |
| `tests/harbour_water_test.gd` | **82 checks, 0 failures** |
| `tests/vehicle_handling_test.gd` | **28 checks, 0 failures** |
| `tests/integration.gd` | **63 checks, 2 failures** — the pre-existing melee-damage and enemy-defeat/reputation assertions; the first-person pistol ray now passes |
| `tests/cbd_expansion_test.gd` | **54 checks, 7 failures** — existing export/test discrepancies: OSM count threshold, two untriangulable footprints, generated-road clearance, minimum kerb clearance, harbour building-centroid check, old shoreline-collision node expectation, and viewpoint-to-footpath distances |
| `tests/inner_west_smoke.gd` | **Not passing** — unresolved type inference in `sydney/inner_west/buildings.gd` and a `float` constructor error in `sydney/inner_west/inner_west_mesh.gd`; untouched |
| `tests/harbour_bridge_test.gd` | Structural checks passed through the two grounded approach checks, then the full-route test exceeded the 180-second run limit; not reported as a pass |

### Windowed

Godot 4.7.2 Compatibility rendering ran on the AMD Radeon RX 6600. The
windowed visual scripts loaded the canonical main scene and captured rendered
landmark/gameplay views. These are scripted camera/state captures, not a claim
that a human keyboard/mouse playthrough was completed.

Gameplay captures:

- `tests/main_first_person.png`
- `tests/main_first_person_weapon.png`
- `tests/main_third_person_vehicle.png`
- `tests/main_exit_first_person.png`

Landmark captures:

- `tests/landmark_town_hall.png`
- `tests/landmark_queen_victoria_building.png`
- `tests/landmark_st_marys_cathedral.png`
- `tests/landmark_hyde_park.png`
- `tests/landmark_central_station.png`
- `tests/landmark_circular_quay.png`
- `tests/landmark_darling_harbour.png`
- `tests/landmark_pyrmont_bridge.png`

## Remaining limitations

- Landmark geometry is intentionally low-poly and approximate; QVB, Town Hall,
  St Mary’s, and Central need further silhouette/facade refinement against
  in-game reference views.
- The Bridge-start Opera House view is improved but its lower silhouette can
  still be intersected by nearby Bridge rails; a later camera-framing pass can
  move the opening view or favor the nearby quay.
- The CBD expansion test still reports the export/test issues listed above.
- Inner West remains a preserved, separate development scene until its overlap
  and current parse/runtime issues are resolved.
- `README.md`, `AGENTS.md`, and `STATE.md` still contain District Zero / Stage A
  default-launch guidance from earlier work and should be reconciled with this
  canonical-main-scene change.
