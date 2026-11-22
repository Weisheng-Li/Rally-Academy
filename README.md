# Rally Academy

Badminton strategy + idle training game. Pixel-art, 2.5D court, built with [LÖVE](https://love2d.org) 11.5.

Design doc: https://claude.ai/artifact/EqpHxhQEHdQG2t7RYCGmgh

## Run

```powershell
& "C:\Program Files\LOVE\love.exe" .
```

Use `lovec.exe` instead to see console output / errors.

## Controls (match demo)

| Input | Action |
| --- | --- |
| Hover a % bubble | Show how the success chance is calculated |
| Left-click a target | Choose where to hit |
| Left-click on your half | Choose recovery spot (clamped to the blue circle) |
| Space | Recover to center |
| Right-click / Esc | Back to target choice |
| `[` / `]` | Slow down / speed up the game |
| F11 | Fullscreen |

## Project layout

```
main.lua, conf.lua      LÖVE entry points (thin)
src/core/               Pure game rules: court, shots, athlete, rally, match, ai. NO love.* calls.
src/data/               Balance numbers as plain Lua tables (shots, athletes).
src/config/layout.lua   Screen layout, camera, colors - nudge UI positions here.
src/view/               Drawing + UI (only layer that uses love.graphics).
src/scenes/             Title and match scenes: glue between core and view.
src/app.lua             Canvas scaling, scene switching, dev flags.
tools/sim/              Headless AI-vs-AI balance simulation.
assets/                 Fonts and sprites (placeholders for now).
```

The core/view split is deliberate: rules and data can be ported to another engine
without touching drawing code, and the simulation runs without rendering.

## Dev tools

Balance simulation (runs core only, prints win rates):

```powershell
& "C:\Program Files\LOVE\lovec.exe" tools/sim 300
```

Automated screenshots (saved to `%APPDATA%\LOVE\rally_academy\screenshots\shot.png`):

```powershell
& "C:\Program Files\LOVE\lovec.exe" . --profile trained --seed 3 --auto 3 --hover 3 --shot 1
```

See `src/dev.lua` for all flags.
