-- Heart rate (fatigue). Placeholder numbers, calibrated against elite singles:
-- ~10 shots per rally (Olympic finals 5.5 -> 10.2), rallies ~6 s with ~12 s rest, match heart
-- rate ~87-90% of max on average, peaks 95-100%. Target here (Elite vs Elite): rallies of
-- 6-15 shots peak near 88% of max, 16-30 near 94%, longer ones pin the player at max.
--
-- Moving raises it (sprints much more than jogging, plus each lunge); standing or walking
-- brings it back down, but never below your floor.
-- The floor is your own exertion: every second you spend above your rally's starting heart
-- rate adds load (bpm x s), and the floor rises with it. The player being run around builds
-- it fast; the one dictating from the centre builds it slowly.
-- Between rallies you only partly recover: the next rally starts higher after a hard one
-- (carry), and that extra fades over a few quieter points.
-- Above `onset` it starts to hurt: slower legs (top speed and split-step push-off), so you
-- arrive later and are forced into longer lunges, and a shakier racket.
return {
  max = 190,           -- bpm
  start = 150,         -- bpm at the start of a rally after full recovery

  -- dHR/dt = gain x intensity^2 - recover x (1 - intensity)   (intensity = speed / top speed)
  gain = 30,           -- bpm/s at a full sprint
  recover = 12,        -- bpm/s standing still (walking recovers less)
  lunge = 4,           -- bpm added by a full-stretch lunge (x stretch)

  -- floor within the rally = rally start + loadFloor x load (load = bpm above start x s)
  loadFloor = 0.04,
  -- next rally starts at start + carry; carry = carry x carryDecay + carryPerLoad x last load
  carryPerLoad = 0.012,
  carryDecay = 0.5,
  carryMax = 25,       -- bpm

  -- Stamina stat (1-10): x gain and lunge cost, x recover
  staminaCost = { [1] = 1.4, [5] = 1.0, [10] = 0.7 },
  staminaRecover = { [1] = 0.7, [5] = 1.0, [10] = 1.3 },

  -- effects: f = (hr - onset) / (max - onset), 0..1
  onset = 165,         -- bpm (~87% of max): below this, no effect
  slowAtMax = 0.35,    -- top speed and push-off x (1 - slowAtMax x f)
  wobbleAtMax = 3.0,   -- shot wobble x (1 + wobbleAtMax x f^1.5)
}
