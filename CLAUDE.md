# Rally Academy - notes for Claude

- Engine: LÖVE 11.5 (`C:\Program Files\LOVE\lovec.exe`). LÖVE is for the POC phase; keep the code easy to port.
- **`src/core/` and `src/data/` must never call `love.*`.** Randomness is injected (`rng` function). `tools/sim` loads core via plain `require` to prove this.
- Drawing/input lives only in `src/view/`, `src/scenes/`, `src/app.lua`.
- UI positions, camera and colors go in `src/config/layout.lua` (the user tweaks these by hand); do not hardcode screen positions elsewhere when avoidable.
- Balance numbers go in `src/data/`. After changing them, run `lovec tools/sim 300` and report the win rates.
- Any change to `trajectory.lua` / `shot_model.lua` algorithms: run `lovec tools/bench` (~15 s) and show the user the speed + accuracy tables from `tools/bench/results.md`, before vs after.
- Unit tests: `lovec tests` (all must pass). Body/racket sizes live only in `src/core/body.lua`; drawing goes through `src/view/figure.lua` so tests can check what is drawn matches the model. Add a test when adding drawn geometry.
- Verify visual changes with a dev screenshot (`--shot`, see `src/dev.lua`); output lands in `%APPDATA%\LOVE\rally_academy\screenshots\`.
- Design doc (rules source of truth): https://claude.ai/artifact/EqpHxhQEHdQG2t7RYCGmgh
