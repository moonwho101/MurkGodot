# Murk (Godot 4.7)

A Godot 4.7.2 port of the Three.js isometric dungeon crawler in `MurkThreejs`. Pick a hero, descend through
procedurally carved floors, steal the blue treasure and carry it back to your home pad.

## Run

Open this folder in Godot 4.7.2 and press F5, or from a shell:

```
Godot_v4.7.2-stable_win64.exe --path c:\godot\Murk
```

The first launch imports the assets (images and WAV sound effects) into `.godot/`.

## Layout

| Path | Purpose |
| --- | --- |
| `scripts/defs.gd` | Class, monster and talent tables, direction helpers |
| `scripts/dungeon_system.gd` | Episode parsing, level generation, pathfinding, fog reveal |
| `scripts/entity.gd`, `scripts/projectile.gd` | Heroes, allies, rivals, monsters and missiles |
| `scripts/game.gd` | Rules, AI, input (keyboard, mouse, gamepad), game flow, save/continue |
| `scripts/renderer.gd` | Painter-sorted isometric sprite renderer, torch lighting, particles, floating text |
| `scripts/ui.gd`, `scripts/map_view.gd` | HUD, menus, modals, talents, minimap and full map (all built in code) |
| `scripts/audio_manager.gd` | Sound effects and ambience |
| `shaders/` | Flickering torch light (`lit.gdshader`) and screen vignette / hit flash |
| `assets/` | Sprite sheets, sounds and `levels.json` copied from the web version |
| `tests/` | Headless/visual smoke, soak and input tests |

## Controls

WASD / arrows move, click walks or attacks, Space / J fires (auto-aim), right-click fires toward the cursor,
E / Enter uses ladders, R ring of protection, Q drops the relic, M / Tab map, Esc pause, F fullscreen,
N mute, H help, wheel or +/- zoom. Gamepads are supported (left stick move, RT / right stick fire, A ladder,
X ring, Y relic, Back map, Start pause).

## Saves

Settings, best run and episode progress are stored as JSON in Godot's user directory
(`%APPDATA%\Godot\app_userdata\Murk\`): `murk_settings.json`, `murk_save.json`, `murk_best.json`.

## Tests

```
Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/logic_test.gd   # plays every episode
Godot_v4.7.2-stable_win64_console.exe --path . -s res://tests/input_test.gd              # synthetic input checks
Godot_v4.7.2-stable_win64_console.exe --path . -s res://tests/smoke_test.gd -- <dir>     # screenshots of each screen
```

## Differences from the web version

- Sound effects are not stereo-panned by screen position (volume still falls off with distance).
- Glows, target rings and cursor overlays are drawn on top of the sprite layer instead of being sorted per tile.
- The hit-flash tint on sprites is applied through the sprite colour rather than an additive shader pass.
