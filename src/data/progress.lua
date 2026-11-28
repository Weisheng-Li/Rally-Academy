-- What the athlete page says about each stat: the unlocks along its level track, and the
-- numbers that don't come from a game curve yet. Pure data (no love.*).
-- The concrete readings (smash km/h, top speed, lunge, shots landing in) come from the real
-- curves (src/data/stats.lua) and the shot model; only stamina is a placeholder here.
local P = {}

-- On-screen names where the stat key reads wrong to a player (the key stays the same in code).
P.names = { speed = "footwork" }
function P.name(k) return P.names[k] or k end

-- Level -> what you can newly do (shown on the stat's track). Design placeholders.
P.unlocks = {
  power   = { [3] = "smash gets past a Backyard player", [5] = "smash beats a club player's reactions",
              [7] = "clears reach the back line from anywhere", [9] = "smash wins rallies outright" },
  speed   = { [2] = "first split-step", [4] = "reaches a drop from the back", [6] = "covers the court in a second",
              [9] = "never caught out of position" },
  legs    = { [2] = "first lunge", [4] = "full lunge reach", [6] = "back up before a fast reply",
              [8] = "lunges and counter-attacks" },
  stamina = { [3] = "lasts a long rally", [5] = "a full game without fading", [8] = "fresh in the final" },
  clear   = { [3] = "overhead clears", [5] = "reliable cross-court", [7] = "holds up when you're late" },
  lift    = { [3] = "lifts to both back corners", [5] = "lifts from a full lunge", [8] = "deceptive lifts" },
  drop    = { [3] = "overhead drops", [5] = "drops land just past the net", [7] = "cross-court drops" },
  net     = { [4] = "tight to the tape", [6] = "spinning net shots", [8] = "net kills" },
  drive   = { [3] = "flat over the net", [5] = "drives from both sides", [7] = "fast exchanges" },
  smash   = { [3] = "smash in matches (contact above 1.9 m)", [5] = "smash from the back", [7] = "jump smash" },
}

-- What each stat means, one line (the track's subtitle).
P.about = {
  power   = "How hard you hit: your top smash speed, and how deep clears and lifts go.",
  speed   = "How fast you cover the court, and the push-off from a split-step.",
  legs    = "Lunge reach, and how quickly you're back up after one.",
  stamina = "How long you can keep it up before your heart rate makes your hands shaky.",
  shot    = "How many of your practice shots land in, from the drill's hitting spot to its target.",
}

-- Placeholder until stamina gets a real reading: hard shots before you tire (level -> shots).
P.staminaShots = { [1] = 5, [3] = 8, [5] = 12, [7] = 18, [10] = 30 }

-- Reps-per-day estimate from the plan (src/core/career.lua Career.dailyReps): share of a
-- block spent working (the rest is breaks and walking), seconds per drill rep.
P.estimate = { work = 0.55, drillRep = 2.4 }   -- checked against a simulated day: within ~25% (net runs higher: perfect reps count double)

-- Practice shots drawn on a shot card / per level on the track.
P.practice = { card = 20, track = 120 }

return P
