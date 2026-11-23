-- Off-balance system (placeholder numbers). Each player has an off-balance meter 0..1.
-- Setup shots push it up; time (and the Balance stat) brings it back down.
return {
  -- what pushes it up (added when the shot is played / hit at you)
  stretchGain = 0.6,        -- x stretch (0..1) when you had to lunge for it
  wrongFootGain = 0.35,     -- the ball goes away from where you were moving
  smashGain = 0.2,          -- returning a smash
  -- recovery per second: base + perLevel * Balance stat
  recoverBase = 0.35,
  recoverPerLevel = 0.06,
  -- effects at full off-balance (scaled by the meter)
  reactionAdd = 0.25,       -- s extra before the first step
  speedLoss = 0.30,         -- fraction of running speed lost
  wobbleAdd = 0.80,         -- wobble x(1 + wobbleAdd * meter)
  -- limited shots: when stretched or off balance >= restrictAt
  restrictAt = 0.6,
  crossMinTechnique = 7,    -- cross-court shots need this technique level when late
  lateCrossWobble = 1.5,    -- and even then they shake more
}
