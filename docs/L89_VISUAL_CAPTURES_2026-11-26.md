# L89 visual captures — 2026-11-26

Bounded step for todo L89 ("Visual capture and human check of the 131 new
storefronts, night headlights and the expanded pause/controls screens"):
the capture material now exists; the human sign-off remains.

## Produced

`tests/capture_l89_visuals.gd` (windowed run) writes 27 PNGs (1920x1080) to
`tests/captures/l89/`:

- Storefront street views for McDonald's, KFC, 7-Eleven (both facings, day +
  night) — the business_poi layer.
- Woolworths and Coles via the supermarket system (both facings, day + night).
- Night headlights: front view + rear beam view for three cars and the
  motorbike (set_headlights called via its real toggle path).
- Pause menu overlay.

Harness gotchas recorded in the script: Woolworths/Coles are NOT in the
business_poi group (supermarket system, `Store_<short>` names); the 7-Eleven
node name keeps its hyphen; `set_headlights()` must be called — setting the
`headlights_on` property directly skips `_apply_headlights()` and the spots
stay invisible.

## Machine-checked (vision pass, 2026-11-26)

- McDonald's day sign: readable, correctly seated, no z-fighting or floating
  geometry. Storefront reads small against the tower behind it (cosmetic).
- Night sign: legible; reads as lit via high-contrast albedo but has no glow
  or light spill (no bloom halo, no light on the pavement).
- Pause menu: clean layout, all five buttons present and legible, focus
  highlight visible, footer hints readable; no overlaps.

## Found: headlight beams do not light the road (needs a fix pass)

With `set_headlights(true)` on a parked car at 22:00, the lens quads glow and
the taillights light up, but the asphalt ahead shows no light pool from any
angle (`headlights_*_beam.png`). The SpotLight3Ds exist and toggle visible
(`tests/vehicle_headlights_test.gd` 32/0), so the logic is correct — the light
does not reach the pixels.

Working hypothesis: the road/footpath meshes are single whole-city merged
meshes whose AABB covers every light, so in the Compatibility renderer they
hit the max-lights-per-object limit and the headlight spots lose the budget
to streetlamps (the perf audit counted 126 night lights). The fix direction
is the same as the perf audit's P2: tile the merged static meshes so nearby
lights cull per tile. Documented in the todo Inbox; not fixed in this pass.

## Still needing human eyes

- Framing/feel of the storefronts in motion (dashboard view, occlusion by
  trees/furniture at speed).
- Night headlight look once the road-lighting bug above is fixed.
- Settings sub-menus (video/audio/input sliders), remapping flow, and
  persistence across sessions — the captures cover the landing pause screen.
