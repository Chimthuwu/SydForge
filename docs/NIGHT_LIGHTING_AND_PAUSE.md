# Phase C/D — night lighting budget and pause menu

## Why

The night view had two unbounded light sources: every AI traffic car within
110 m of the player kept both headlight spots and rear lamps live, and 18
street lamp spots were active. The scene therefore paid for a variable number
of real lights that grew with nearby traffic. Separately, there was no way to
pause or adjust volume/fullscreen without leaving the game.

## Night lighting

`city_lights_manager.gd` is the single owner of the vehicle light budget.

- Active street lamps: 18 → 14 (`ACTIVE_STREETLIGHTS`), still nearest-first and
  still culled beyond `LIGHT_RANGE`.
- AI traffic: the four-times-a-second tick ranks every traffic car within
  70 m (`AI_HEADLIGHT_RADIUS`) by squared distance and lights at most six
  (`AI_HEADLIGHT_MAX`). Cars outside the radius are explicitly switched off.
- A car the player is driving is excluded from the budget
  (`set_light_budget_managed(false)`) so its own headlight logic keeps working
  when hijacked at night.
- The candidate list is rebuilt on the existing 0.25 s tick, not per frame, and
  only holds cars already inside the radius. No new per-frame allocation was
  added to the hot path.
- All street lamp and traffic spots remain `shadow_enabled = false`, and the
  sun's shadow pass is already skipped at night, so the scene remains at one
  shadow-casting directional light by day and zero at night (limit: four).

`vehicle_traffic_controller.gd` exposes `set_light_budget_managed()` and
`apply_light_budget()`, and its own `_update_light_visibility()` returns early
while the manager owns the car.

## Pause menu

`scripts/pause_menu.gd` is an on-demand `CanvasLayer` (layer 90) built after
play starts. It dims the frame and offers:

- Resume.
- Settings: master volume slider (−40…6 dB), AI headlight density
  (Off / Nearest 3 / Nearest 6), fullscreen toggle.
- Esc closes it. Every node in the overlay runs with `PROCESS_MODE_ALWAYS`, so
  it stays responsive while the scene tree is paused.

`scripts/sydney_cbd_district.gd` opens it on `ui_cancel` only when the real
game entry point is active (`_menu_allowed()`), no opening menu is present and
no pause overlay already exists. Opening pauses the tree and releases the
mouse; closing unpauses and recaptures the mouse. Headless suites and capture
tools keep the pre-existing mouse-toggle behaviour.

`scripts/game_settings.gd` holds the three values as static state, applies
volume through the Master bus and window mode through `DisplayServer`, and
persists them to `user://settings.cfg`. Settings load once, so the lighting
manager reads the current budget on its next tick without extra signals.

## Verification

- `tests/lighting_pause_test.gd`: 14 checks, 0 failures. Ten fake cars exercise
  distance ranking, the six-light cap, the off switch, manager ownership of far
  cars and exemption of the driven car. It also checks the overlay structure
  and that a simulated Esc press closes and frees it.
- `tests/parse_check.gd`: 142 scripts checked, 0 failed.
- Real-scene headless probe on `main.tscn` at 22:00: 6 traffic cars, all six
  manager-owned, 0 lit while all were ~107 m from the spawn; after moving the
  player within 25 m, 2 lit (only 2 were within the radius). Shadow-casting
  lights at night: 0. Pause opened (`paused=true`) and closed
  (`paused=false`, menu freed).
- `tests/perf_compare.gd` at 22:00, fixed camera:
  205.13 ms (first, transient), then 156.68 ms, draw 3200, primitives 6.73 M,
  lights 127, mesh nodes 8145. The clean-HEAD baseline was 155.35–174.60 ms
  with 129–135 lights, so this change is performance-neutral within run-to-run
  variance. No speedup is claimed; the benefit is a bounded number of live
  traffic lights.
- Captures: `tests/captures/phase_cd/night_headlights.png` and
  `pause_menu.png` (windowed, real `main.tscn`). These are visual captures, not
  automated checks. A human should still drive the repaired route at night and
  confirm the lighting reads correctly on their display.

## Player vehicle headlights (2026-11-22 continuation)

`ArcadeCar` now builds real dynamic beams, not just emissive lamp boxes. Every
enterable car gets two front `SpotLight3D`s (one central beam on the motorbike):
38 m range, 31° cone, no shadows. They are off until the driver toggles them
with **F**; entering at night switches them on automatically from the district's
`WorldTimeManager`. Leaving the vehicle switches them off, and entering also
switches off the on-foot torch so it cannot shine through the windscreen.

`district.gd` routes F by context: `player.vehicle != null` toggles headlights,
otherwise the first-person flashlight. This works for every `ArcadeCar` scene
(comet/viper/hauler/taxi/motorbike), not one showcase car.

AI traffic keeps its separate budgeted lights in `city_lights_manager.gd`.

## Expanded pause menu

`pause_menu.gd` now offers Resume, Respawn, Settings, Controls and Return to
Menu (reloads the canonical scene, which presents the opening time/spawn menu).
Return-to-menu is deferred until the overlay closes so the pause state is
unwound first.

Settings:

- master, music and SFX volume (music and SFX are offsets over the authored bus
  trims; all non-music categories share the SFX control);
- mouse sensitivity 0.2–3.0× and invert-Y, read live by `camera_rig.apply_look`;
- AI headlight density and fullscreen, as before.

Controls shows the current binding for movement, jump/handbrake, sprint/NOS,
interact, fire, aim, weapons 1–3, next weapon, reload, torch/headlights,
skateboard, horn, wheelie and skate trick. Clicking a binding listens for the
next key or mouse button; Esc cancels. Remaps are written to InputMap and
persisted. All pause UI remains on `PROCESS_MODE_ALWAYS`, and rebind input is
consumed so it cannot fire a gameplay action.

## Settings file

`user://settings.cfg` stores `audio/master_db`, `audio/music_db`,
`audio/sfx_db`, `input/mouse_sensitivity`, `input/invert_y`,
`input/bindings`, `video/headlight_budget` and `video/fullscreen`. Delete it to
return to defaults (0 dB offsets, 1.0 sensitivity, no inversion, six AI
headlights, windowed).

## Tests added

- `tests/vehicle_headlights_test.gd` — 32 checks, 0 failures: two beams on each
  car, one on the bike, front position, no shadow pass, on/off visibility and
  illumination.
- `tests/settings_input_test.gd` — 12 checks, 0 failures: sensitivity scales
  look, invert-Y flips pitch, a remap reaches InputMap and is displayed, all
  audio/input values persist.
- `tests/lighting_pause_test.gd` — now 17 checks, 0 failures, covering the
  expanded settings, controls, respawn and return-to-menu entries.

## Known limits

- The six-headlight cap is global around the player, not per street; a very
  dense traffic cluster could still show six simultaneous spots.
- Traffic density in the default spawn area is sparse (six cars), so most
  nearby cars are dark simply because they are beyond 70 m.
- The pause overlay uses the default Godot control theme, matching the
  existing opening menu's unstyled controls.
