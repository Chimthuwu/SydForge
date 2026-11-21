# Cyberpunk Sydney — Shared Asset Library Gap Audit

Audited `Z:\GITHUB\_ASSETS\ASSETS` and `INDEX.md` against the neon-overhaul
asset requirements on 2026-11-21. Nothing in the shared library was modified.

## What was inspected
- `INDEX.md` in full.
- All 3D packs listed under `3D/Buildings-Shops`, `3D/Props-Furniture`,
  `3D/Roads-Infrastructure`, `3D/Vehicles`, `3D/Characters-Animations`.
- File-name and extension scans (`*.glb`, `*.gltf`, `*.fbx`, `*.obj`,
  `*.zip`, `*.rar`) for cyber/neon/holo/sci-fi/industrial/police signage.

## Gap findings
- **No cyberpunk / neon / holographic / digital-signage assets** exist in the
  library. No `neon`, `holo`, `cyber`, `sci-fi building`, `billboard` or
  `digital sign` pack was found.
- **No futuristic vehicle assets.** The vehicle packs are low-poly/PSX-style
  civilian cars (`Designersoup Low Poly Car Pack`, `Low_Poly_Cars_DevilsWorkShop_V03`,
  `PSX_Style_Cars`, `PSX_Vehicle_Pack`) — useful for generic traffic, not a
  futuristic fleet.
- **No rigged human characters.** `3D/Characters-Animations` contains no usable
  models; 2D character packs are sprites and unsuitable for 3D close-ups. The
  existing procedural humanoid population remains the correct base.
- **Generic assets that were already adopted by the project** (not touched here):
  `assets/imported/free_city_pack/*.glb` (bench, bin, tree, streetlight,
  traffic light, stop sign, hydrant, cones) from `free city pack.zip`.
- `Downtown City MegaKit[Standard].zip` (223 MB) is a generic low-poly city kit;
  not cyberpunk, and not imported wholesale to avoid asset bloat.
- `Shacks Shanties Sheds and Gantries 0001.zip` is a plausible industrial source
  for a later Inner West pass, outside this vertical slice.

## Decision for the vertical slice
Build the neon signage layer procedurally, using animated shader quads with a
restrained palette (cyan / magenta / violet / amber). This is cheap, scalable
and keeps the exported OSM geometry and collision untouched. It should be
replaced with authored signage/prop assets if a suitable licensed pack is
sourced later; the module boundaries (`sydney/cbd/cbd_neon_slice.gd` for the
hero locations, `sydney/cbd/cbd_neon_city.gd` for the city-wide system) make
that swap local.

## Status after the city-wide extension (2026-11-21)
- **Still no usable external assets** for neon signage, holograms, futuristic
  vehicles, or rigged humans. No new asset pack was imported.
- **Vehicles:** kept the existing procedural fleet; added restrained emissive
  LED accents (shared materials) to taxis, vans, police, sports cars and buses
  in `sydney/ecosystem/vehicle_visual_builder.gd`. This is a visual retrofit,
  not a replacement model set — true futuristic vehicle models remain missing.
- **Pedestrians:** kept the articulated procedural humanoids; added subtle
  headphones / lit-bag details. No rigged human model is available in the
  library, so the population is still not equivalent to authored characters.
- **Signage:** now data-driven in `cbd_neon_city.gd` (district palettes and
  densities) with cached materials and batched MultiMesh skyline dressing.
- **Skyline/districts:** `cbd_skyline_heroes.gd` adds a handful of authored
  retrofit tower silhouettes using a facade-integrated light-panel shader;
  `cbd_district_anchors.gd` gives underdressed districts one designed
  installation each (transport monument, heritage arch, corporate canopy,
  gateway) rather than more repeated signs. Still procedural — no authored
  futuristic architecture assets were available.
- **Architecture slice:** `cbd_arch_slice.gd` + `shaders/architecture.gdshader`
  add real facade geometry (mullions, spandrels, projecting fins, sills,
  podium bands, rooftop plant) to 80 buildings in one representative CBD block.
  Re-checked `3D/Buildings-Shops`: only generic low-poly kits (`Downtown City
  MegaKit` 224 MB, `Buildings.rar`, `6twelve.rar`) and small mixed packs.
  None are near-future Sydney architecture, none are licensed for a clean
  drop-in replacement, and importing a 224 MB kit wholesale would bloat the
  project. No architecture asset was imported. The procedural slice is a
  genuine geometric upgrade, not an authored-model equivalent.
