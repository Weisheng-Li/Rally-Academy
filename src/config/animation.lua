-- Footwork / lunge animation numbers (sprite metres, seconds). Shared by the match
-- (src/view/animator.lua) and the tuning demo (lovec . --demo balance), so tuning one
-- tunes both.
return {
  -- side shuffle (chasse): short sideways / diagonal moves. Feet never cross.
  shuffle = {
    step = 0.45,     -- m covered per close-and-step
    wide = 0.55,     -- m between the feet when stepped out
    narrow = 0.2,    -- m when the trailing foot has closed in
    hip = 0.66,      -- m, slightly crouched
    hop = 0.05,      -- m, small hop on the close
  },

  -- running: long moves, and forward/back moves (where a real player would turn side-on)
  run = {
    from = 2.0,      -- m; moves longer than this are run
    inOut = 0.5,     -- moves whose sideways screen share is below this are run too
    stride = 1.0,    -- m covered per full cycle (two quick 0.5 m steps)
    amp = 0.35,      -- m, how far each foot swings ahead of / behind the hips
    lift = 0.18,     -- m, swing foot height
    hip = 0.725,     -- m, support leg nearly straight (leg = 0.735 m)
  },

  -- lunge at contact
  lunge = {
    start = 0.6,     -- m before arriving the lunge step begins
    minMove = 0.5,   -- moves shorter than this just step in (no lunge) unless overreaching
    controlled = { hip = 0.5, front = 0.35, back = -0.52, lean = 0.08, straight = 1 },
    -- overreach lean = Body.leanFor(base + perStretch * stretch): tilt covers the extra reach
    overreach = { hip = 0.42, front = 0.45, back = -1.0, straight = 0, base = 0.15, perStretch = 0.2 },
  },

  -- low serve (toss timing and contact point: serveToss in src/data/shots.lua)
  serve = {
    holdAngle = -100,  -- deg above horizontal: racket hanging back and down before the toss
    swing = 0.15,      -- s before contact the underarm swing starts (accelerates into it)
    follow = 0.15,     -- s of follow-through after contact, up to followAngle
    followAngle = -5,
    settle = 0.3,      -- s to bring the racket back to the ready angle
  },

  splitHop = { time = 0.12, height = 0.12 },   -- hop when a new move starts
  stand = { front = 0.12, back = -0.12 },      -- feet when standing
}
