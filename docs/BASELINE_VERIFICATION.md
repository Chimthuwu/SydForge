# Baseline verification — Phase 0

Date: 19 November 2026
Godot: bundled `Godot_v4.7.2-stable_win64_console.exe`
Project: `Z:\GITHUB\_GAMES\New folder` (commit `a8dc2a2`, clean tree at baseline)
Command:

```
APPDATA=<project>/.runtime ./Godot_v4.7.2-stable_win64_console.exe \
  --headless --path . --script res://tests/integration.gd \
  --log-file <project>/tests/integration.log
```

## Result

**63 checks, 2 failures, process exit code 1.**

| Check | Result |
|---|---|
| `melee damages nearby enemy` | **FAIL** |
| `enemy defeat grants reputation` | **FAIL** |
| All other 61 checks | PASS |

The suite loads the production district, player, enemy and four vehicles and
exercises movement, sprint, jump, camera orbit/pitch/obstruction, all four cars,
entry/exit, blocked exits, reverse, crash damage, pistol, reload, damage,
respawn, vehicle destruction/recovery and HUD updates.

## Analysis

Both failures are in the same melee sequence:

```
foe.position = p.position+Vector3(0,0,-1.5)
p.melee()
check(foe.health == 35, "melee damages nearby enemy")   # FAIL
foe.take_damage(40)
check(not foe.visible and p.kills == 1, ...)            # FAIL (kills not 1)
```

`player.melee()` requires three conditions: distance < 2.8 m, the target inside
a 0.25 forward dot product, and a ray from the player's chest to the enemy's
chest that hits the enemy first. The test places the enemy at 1.5 m but does
not set the player model's facing, and the preceding pistol segment leaves the
camera/model orientation from earlier driving. A failed melee means `kills`
stays 0, so the follow-up reputation check fails by consequence. This is a
**pre-existing test-fixture sensitivity, not a regression from this work** —
the project was clean and untouched before the run.

No GDScript parse errors, missing scenes, or startup errors appeared. The
process exited 1 solely because `failures > 0`.

## Existing issues observed

1. Melee test depends on actor facing that the fixture does not establish.
2. `README.md` contains NUL bytes after the visible text (file ends with
   `#\0 \0s\0p\0l\0o\0o\0g\0e\0`). It does not affect the game but is malformed.
3. `runtime.log`, `validation.log`, `tests/*.log` are tracked/generated logs in
   the project root and test folder.
4. No navigation, traffic, save system, missions, or imported art, as documented.

## Limitations

- Headless only. A GUI launch was not performed during baseline; rendered
  validation is addressed separately after the Sydney integration.
- `gda 0.25.0` is present but was not used for the baseline because the bundled
  console executable is the documented runner.
