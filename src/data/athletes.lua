-- Player levels: 6 all-rounders, from backyard to elite. Used for you and for the opponent.
--
-- stats (levels 1-10; curves in src/data/stats.lua and src/data/shots.lua `technique`):
--   Technique: clear, lift, drop, net, drive, smash -> accuracy, coping when late / cross-court,
--              how tight net shots are, and (clear/drop/smash) how high you can make contact
--   Physical:  power -> max launch speed;  speed -> top speed and split-step push-off;
--              stamina -> heart rate: rises slower when moving, drops faster when resting;
--              legs  -> momentum kept from a run and how fast it fades
--   Movement:  reach -> lunge;  reaction -> delay before moving;  recovery -> pause after hitting
--
-- brain (opponent AI only, src/core/ai.lua; never shown, not trainable):
--   aimMargin m inside the standard targets (toward the middle), noise (sloppy choices),
--   riskAversion, recovery "none" | "center", anticipation 0-3 (0 = recovery as above;
--   1 = base depends on the shot just played; 2 = also knows what the opponent can't play
--   from where they'll hit; 3 = also weighs the opponent's habits this match)
local A = {}

local function stats(t, p)
  return { clear = t, lift = t, drop = t, net = t, drive = t, smash = t,
           power = p.power, speed = p.speed, legs = p.legs, reach = p.reach,
           reaction = p.reaction, recovery = p.recovery, stamina = p.stamina or p.legs }
end

A.levels = {
  { key = "backyard", title = "Backyard", tag = "No overhead, no lunge, stays put",
    stats = stats(1, { power = 1, speed = 1, legs = 1, reach = 1, reaction = 1, recovery = 1 }),
    brain = { aimMargin = 1.0, noise = 0.6, riskAversion = 0.3, recovery = "none", anticipation = 0 } },
  { key = "beginner", title = "Beginner", tag = "Learning the overhead, slow back to centre",
    stats = stats(2, { power = 2, speed = 2, legs = 2, reach = 2, reaction = 2, recovery = 2 }),
    brain = { aimMargin = 0.7, noise = 0.45, riskAversion = 0.5, recovery = "center", anticipation = 0 } },
  { key = "intermediate", title = "Intermediate", tag = "All the shots, half of them miss",
    stats = stats(3, { power = 4, speed = 4, legs = 3, reach = 3, reaction = 3, recovery = 3 }),
    brain = { aimMargin = 0.5, noise = 0.35, riskAversion = 0.7, recovery = "center", anticipation = 0 } },
  { key = "advanced", title = "Advanced", tag = "Strong club player, real smash",
    stats = stats(6, { power = 6, speed = 6, legs = 6, reach = 5, reaction = 6, recovery = 6 }),
    brain = { aimMargin = 0.3, noise = 0.2, riskAversion = 0.9, recovery = "center", anticipation = 1 } },
  { key = "national", title = "National", tag = "Fast, accurate, reads your options",
    stats = stats(8, { power = 8, speed = 8, legs = 8, reach = 5, reaction = 8, recovery = 8 }),
    brain = { aimMargin = 0.15, noise = 0.1, riskAversion = 1.0, recovery = "center", anticipation = 2 } },
  { key = "elite", title = "Elite", tag = "International / world class",
    stats = stats(10, { power = 10, speed = 10, legs = 10, reach = 5, reaction = 10, recovery = 10 }),
    brain = { aimMargin = 0.05, noise = 0.03, riskAversion = 1.1, recovery = "center", anticipation = 3 } },
}

-- Match-ready athlete definition for level i (1-6). name: shown in the HUD.
function A.level(i, name)
  local L = A.levels[i]
  return { name = name or L.title, title = L.title, tag = L.tag, stats = L.stats, brain = L.brain, level = i }
end

return A
