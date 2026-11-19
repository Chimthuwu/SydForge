# District Zero validation

Engine: bundled Godot 4.7.2, Compatibility renderer. Windows, AMD Radeon RX 6600.

> **Current-tree status (2026-11-19):** on commit `a8dc2a2` plus the uncommitted
> Sydney work, the exact command
> `APPDATA="$PWD/.runtime" ./Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/integration.gd`
> was run twice. Both runs exited 1 with **63 checks, 2 failures**:
> `melee damages nearby enemy` and `enemy defeat grants reputation`. The same
> two failures are recorded on the untouched tree in
> `docs/BASELINE_VERIFICATION.md`. The 63/0 result below is the earlier
> historical run and does not reproduce on this working tree. They were not
> introduced or fixed by the Sydney geometry pass.

Historical integration result: **63 checks, 0 failures**, process exit code 0.
Final rendered test: all four input/state observations true, process exit code 0.

All six production GDScript files passed Godot `--check-only`. The main scene
imported and ran headlessly without script errors. The integration suite loads
the production district and its player, enemy and four vehicle scenes; it tests:

- Walking, sprint speed, jump height and landing.
- Camera orbit calculation, pitch limits and actual obstruction retraction.
- All four vehicles: interaction entry, collision/visibility state, acceleration,
  steering, wheel-axis stability, braking, moving-exit refusal and safe exit.
- Blocked-exit rejection, reverse driving and physical crash damage.
- Pistol hit damage/ammunition, delayed reload, melee and enemy defeat.
- Enemy respawn, line-of-sight damage and obstruction by a wall.
- Player death/respawn; vehicle destruction with an occupant and timed recovery.
- Live health HUD updates.

Rendered testing uses actual viewport mouse/key events and polled input actions.
Mouse orbit, E entry, approximately 12 m/s driving, braking, E exit and firing damage were
observed. Screenshots were captured and inspected for street view, driving,
combat and district overview (`tests/*.png`). This is automated graphical testing,
not a substitute for a prolonged human feel/playability assessment.

The environment emits `Failed to read the root certificate store` at startup.
It does not prevent gameplay. Setting APPDATA to the local `.runtime` folder
for test processes avoids restricted user-data/shader-cache writes. Normal
launch uses the user's normal Godot data directory. gda could not run because
its installed uv trampoline is broken; no dependency was installed to replace it.

Known limitations:
- Enemy pursuit is direct line-of-sight steering, without navigation/pathfinding.
- Cars are grounded arcade bodies; no suspension, rollover or deformation.
- Raised curbs can stop cars; jump onto raised pavement on foot.
- Characters/buildings are primitive-based art, with basic walk motion; no
  skeletal aiming, entering/exiting animations or authored animation library.
- Synthesized combat sounds only; no engine loop, ambience or music.
- No missions, traffic, save system, menus, controller support or exported build.
- Camera has manual orbit while driving; no automatic recentering.

Next work: human controller/driving playtest, improved character/vehicle art and
feedback, then navigation-aware AI and one authored encounter. Keep city scale fixed.
