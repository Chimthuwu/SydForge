# Sydney asset compatibility

**Phase 2 update:** eight MegaKit modules and only their dependencies are now
imported and verified in Godot 4.7.2. The archive licence/provenance was checked
again. See [the asset inventory and results](SYDNEY_ARCHITECTURE_PHASE2.md).
The original read-only audit below records the state before that implementation.

This phase did not import or extract any asset. The original library at
`Z:\GITHUB\_ASSETS\ASSETS` was inspected read-only; archives were listed, never
extracted, and nothing was reorganised.

## Recommended families

| Asset | Path | Format | Licence | Godot fit | Intended use |
|---|---|---|---|---|---|
| **Downtown City MegaKit [Standard]** | `3D/Buildings-Shops/Downtown City MegaKit[Standard].zip` | 153 unique modular pieces; FBX, **glTF + .bin**, 75 textures | **CC0 1.0** (verified `License_Standard.txt`) | **Best.** Ships `Exports/glTF (Godot)` | Primary CBD facades, cornices, roofs, sidewalks, street decals |
| **Urban Modular Demo** | `3D/Roads-Infrastructure/Urban_Modular_Demo.zip` | 163 glTF + 163 bin + 5 PNG | 046GAMES / Freddy Dohmen: commercial use allowed, **no resale/redistribution of raw or edited assets** (verified) | Very good (native glTF) | Secondary modern walls, pillars, roofs, pavement |
| **Low Poly Cars — Devil’s Work.shop V03** | `3D/Vehicles/Low_Poly_Cars_DevilsWorkShop_V03.zip` | DAE/FBX/OBJ + 11 textures | Commercial use allowed, no attribution required (verified `License.txt`) | Good | Traffic: bus, cars, police (reskin to NSW) |
| **[FREE] Modular Roads — Base** | `3D/Roads-Infrastructure/[FREE] Modular Roads - Base.zip` | 27 unique modules; FBX/OBJ/GLB/DAE/Blend | **No licence file found — not cleared** | Good (GLB) | Junction props, barriers, cones, lamps, trees — not whole streets |
| **free city pack** | `3D/Buildings-Shops/free city pack.zip` | 18 props; FBX/OBJ/GLB | **No licence file found — not cleared** | Good (GLB) | Benches, bins, hydrants, signals, placeholder props |

## Do not use yet

| Asset | Reason |
|---|---|
| PSX vehicle packs, PSX Style Cars | No licence file found; very low detail, clashes with MegaKit |
| `Buildings.rar` and all `.rar` packs | Contents unverifiable (no `unrar`/`7z`/`bsdtar`); licences unknown |
| Voxel building packs | All nine index entries are absent from the library; models survive only in the Sydney repo at `38932cc:assets/models/voxel_buildings/`. Style clashes with MegaKit. |
| TownTileSet | PSX RPG tile, one tile only; credit “Red” required; not CBD scale |

The library index is stale: **25 of 84 entries are missing**, including all ten
voxel packs, zombies, weapons, animations and PSX dungeon/mansion. Treat
`INDEX.md` as a wish list, not inventory.

## Missing for Sydney

No asset exists for:

- Sydney Harbour Bridge;
- Sydney Opera House;
- Australian/NSW road signs (the free pack’s stop sign is US-style);
- ferries, wharves, ferry terminals;
- eucalypts/Port Jackson figs/palms (only generic trees);
- NSW police livery, ticketing machines, bus shelters.

These must be authored or sourced separately. Bridge and Opera House are already
listed in the export as `authoredLandmarksRequired`.

## Format guidance

- Use **glTF/GLB** in Godot; avoid runtime OBJ/DAE.
- MegaKit’s FBX/Unity/Unreal duplicates are unnecessary — use the glTF export.
- Urban Modular needs no conversion.
- Low Poly Cars may need a Blender/glTF conversion pass; test one vehicle first.
- Any asset conversion must happen **outside** the shared library. Copy the
  archive to a temporary working folder, extract and convert there.

## Licence gate

Only CC0, explicitly commercial-friendly, or verified-permission packs may ship.
“No licence file found” means **not cleared**, regardless of where it was
downloaded from. Keep the asset pack’s readme with any converted output and
record the conversion in the project credits.
