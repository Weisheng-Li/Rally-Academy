-- Shot data for the physics shot model. Placeholder balance numbers.
-- spec kinds (see src/core/trajectory.lua):
--   apex  = peak height (m)     net = height over the tape (m)     speed = launch speed (m/s)
-- smash uses the player's Power speed, reduced only as far as needed to clear the net.
return {
  types = {
    clear       = { name = "Clear",       skill = "clear", spec = { kind = "apex", apex = 5.5 } },
    smash       = { name = "Smash",       skill = "smash", spec = { kind = "speed" }, usesPower = true, minContact = 1.9 },
    drop        = { name = "Drop",        skill = "drop",  spec = { kind = "net", clearance = 0.25 } },
    push_clear  = { name = "Push clear",  skill = "drive", spec = { kind = "apex", apex = 3.5 } },
    drive       = { name = "Drive",       skill = "drive", spec = { kind = "net", clearance = 0.25 } },
    block       = { name = "Block",       skill = "drop",  spec = { kind = "net", clearance = 0.20 } },
    lift        = { name = "Lift",        skill = "lift",  spec = { kind = "apex", apex = 4.5 } },
    push        = { name = "Push",        skill = "drive", spec = { kind = "net", clearance = 0.35 } },
    net         = { name = "Net shot",    skill = "net",   spec = { kind = "net", clearance = 0.12 } },
    short_serve = { name = "Short serve", skill = "net",   spec = { kind = "net", clearance = 0.15 }, serve = true },
    long_serve  = { name = "High serve",  skill = "lift",  spec = { kind = "apex", apex = 6.0 }, serve = true },
  },

  -- [hitting from depth][target depth] -> shot type
  matrix = {
    back  = { back = "clear",      mid = "smash", front = "drop" },
    mid   = { back = "push_clear", mid = "drive", front = "block" },
    front = { back = "lift",       mid = "push",  front = "net" },
  },

  -- Contact height (m) by depth: early / on time / fully stretched (interpolated by stretch).
  contactHeight = {
    back  = { early = 2.15, ontime = 2.0, stretched = 1.6 },  -- must stay <= Body.MAX_REACH (2.19 m), see tests
    mid   = { early = 1.6, ontime = 1.3, stretched = 0.8 },
    front = { early = 1.0, ontime = 0.6, stretched = 0.3 },
  },
  serveHeight = 1.0,

  -- Hand shake (1 sigma) for a Lv5 technique, on-time contact.
  baseWobble = { angle = math.rad(1.6), dir = math.rad(2.2), speed = 0.06 },
  -- x step^(pivot - level): Lv1 x2.44, Lv3 x1.56, Lv5 x1.0, Lv7 x0.64, Lv10 x0.33
  techniqueMul = { step = 1.25, pivot = 5 },
  timingMul = { early = 0.85, ontime = 1.0, stretchedMax = 1.6 },  -- stretched: 1.0 -> 1.6 by stretch
  incomingMul = { smash = 1.25, drive = 1.10 },     -- returning fast shots is harder

  earlySlack = 0.30,         -- arrive this many seconds before the shuttle = early
  smashSpeedStep = 2.0,      -- m/s steps when slowing a smash down to clear the net

  skillNames = { clear = "Clear", smash = "Smash", drop = "Drop", net = "Net", drive = "Drive", lift = "Lift" },
}
