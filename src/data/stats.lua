-- Body stats (levels 1-10) -> numbers. Curves: { [level] = value }, linear between the
-- listed levels (src/core/curve.lua). Technique curves live in src/data/shots.lua.
return {
  power = { [1] = 33, [3] = 40, [5] = 55, [7] = 72, [10] = 105 },        -- m/s max launch speed (smash)
  speed = { [1] = 2.0, [10] = 4.5 },                                      -- m/s top running speed
  -- split-step push-off: speed (m/s) you already have when a move starts. Beginners
  -- don't split-step, so they start every move from a standstill.
  firstStep = { [1] = 0, [10] = 1.5 },
  -- lunge: beginners don't lunge; from club level on everyone lunges about the same
  reach = { [1] = 0, [2] = 0.2, [3] = 0.4, [4] = 0.5 },                  -- m extra reach
  reaction = { [1] = 0.45, [3] = 0.35, [5] = 0.25, [7] = 0.17, [10] = 0.08 }, -- s before moving after the opponent hits
  -- recovery: pause after every hit, and the extra pause after a full lunge
  swingPause = { [1] = 0.45, [3] = 0.35, [5] = 0.25, [7] = 0.2, [10] = 0.12 },  -- s
  stretchPause = { [1] = 1.2, [3] = 0.9, [5] = 0.6, [7] = 0.4, [10] = 0.2 },    -- s
}
