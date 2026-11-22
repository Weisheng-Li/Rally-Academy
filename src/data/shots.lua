-- Shot balance data. All numbers are placeholders for the interaction demo.
-- base = success chance before modifiers; flight = seconds in the air; apex = extra arc height (m).
return {
  types = {
    clear       = { name = "Clear",       skill = "clear", flight = 1.70, base = 0.92, apex = 6.5, powerFlight = 0.02 },
    smash       = { name = "Smash",       skill = "smash", flight = 0.70, base = 0.82, apex = 0.0, powerFlight = 0.03, attacking = true },
    drop        = { name = "Drop",        skill = "drop",  flight = 1.30, base = 0.86, apex = 1.6 },
    push_clear  = { name = "Push clear",  skill = "drive", flight = 1.20, base = 0.88, apex = 3.0 },
    drive       = { name = "Drive",       skill = "drive", flight = 0.80, base = 0.87, apex = 0.5 },
    block       = { name = "Block",       skill = "drop",  flight = 1.00, base = 0.88, apex = 1.0 },
    lift        = { name = "Lift",        skill = "lift",  flight = 1.60, base = 0.93, apex = 5.5 },
    push        = { name = "Push",        skill = "drive", flight = 0.90, base = 0.88, apex = 1.0 },
    net         = { name = "Net shot",    skill = "net",   flight = 0.90, base = 0.82, apex = 1.2, attacking = true },
    short_serve = { name = "Short serve", skill = "net",   flight = 1.00, base = 0.95, apex = 1.0 },
    long_serve  = { name = "High serve",  skill = "lift",  flight = 1.80, base = 0.96, apex = 7.0 },
  },

  -- [hitting from depth][target depth] -> shot type
  matrix = {
    back  = { back = "clear",      mid = "smash", front = "drop" },
    mid   = { back = "push_clear", mid = "drive", front = "block" },
    front = { back = "lift",       mid = "push",  front = "net" },
  },

  -- Height of the shuttle at contact (m), by depth and timing.
  contactHeight = {
    back  = { early = 2.8, ontime = 2.6, late = 1.6 },
    mid   = { early = 1.6, ontime = 1.3, late = 0.9 },
    front = { early = 0.9, ontime = 0.6, late = 0.3 },
  },

  timing = {
    early  = { label = "Early",   success = 0.05,  flightMul = 0.9, flightAdd = 0 },
    ontime = { label = "On time", success = 0.0,   flightMul = 1.0, flightAdd = 0 },
    late   = { label = "Late",    success = -0.12, flightMul = 1.0, flightAdd = 0.15 },
  },

  cross = { success = -0.04, flight = 0.10 },
  skillPerLevel = 0.025,   -- success per skill level above/below 5
  slackEarly = 0.30,       -- arrive this much before the shuttle = early
  slackReach = -0.15,      -- later than this = can't reach (winner)
  latePause = 0.20,        -- extra recovery pause after a late contact

  skillNames = {
    clear = "Clear", smash = "Smash", drop = "Drop", net = "Net", drive = "Drive", lift = "Lift",
  },
}
