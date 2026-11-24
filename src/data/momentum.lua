-- Movement + momentum (placeholder numbers).
-- Movement = run + reach. Every move starts with the player's current momentum projected
-- onto the move direction (negative = carried the other way, so you decelerate first),
-- then accelerates at `accel` up to top speed (Speed stat).
-- Momentum comes from the run into each shot; Legs decide how much you keep and how fast
-- it fades while you regain balance.
return {
  accel = 5.0,              -- m/s^2, same for everyone for now
  swingPause = 0.25,        -- s after every hit before you can move
  stretchPause = 0.6,       -- extra s at a full stretch (scaled by how far you lunged)

  -- momentum at contact = run speed x retain x (1 + lungeBoost x stretch),
  -- minus what fades while waiting if you arrived early
  retainBase = 0.65,        -- Legs Lv1: 0.60, Lv5: 0.40, Lv9: 0.20
  retainPerLegs = 0.05,
  lungeBoost = 1.0,         -- a full lunge doubles it
  fullRunDistance = 1.0,    -- m; shorter shuffles build proportionally less

  -- regaining balance: momentum fades by this many m/s per second
  fadeBase = 0.67,          -- Legs Lv2: 1.0, Lv5: 1.5, Lv8: 2.0
  fadePerLegs = 0.167,

  -- display / rule thresholds (m/s)
  yellow = 0.6,             -- below: no arrow
  red = 1.2,                -- at or above: red arrow, limited shots

  -- shot effects
  wobblePerMS = 0.35,       -- wobble x(1 + wobblePerMS x momentum)
  crossMinTechnique = 7,    -- late/red momentum cross shots need this technique level
  lateCrossWobble = 1.5,    -- and even then they shake more
}
