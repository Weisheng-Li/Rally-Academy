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
  serveHeight = 1.0,         -- contact height of the low serve (rules: below 1.15 m)
  -- Low serve: the shuttle is held at the chest (startH high, startFront m in front of the
  -- body, so the near player's body hides it and the far player's doesn't), tossed in a
  -- small arc to the contact point (contactRight m of court to the player's right,
  -- serveHeight high) and hit on the way down, `time` s later (the arc bulges g*time^2/8
  -- above the straight line: 0.5 s -> 0.31 m). Nobody moves until contact.
  -- Court metres: sprites are squashed by the camera's heightScale (0.45), so contactRight
  -- 0.29 is where the drawn racket head reaches (tests/test_figure.lua checks).
  serveToss = { time = 0.5, contactRight = 0.29, startH = 1.2, startFront = 0.15 },

  -- Hand shake (1 sigma) for a Lv5 technique, on-time contact.
  baseWobble = { angle = math.rad(1.6), dir = math.rad(2.2), speed = 0.06 },
  -- However shaky the hand, a shot leaves the racket at this share of its intended speed at
  -- most / least (a wild mishit is slow or a bit hot, never 20x faster). Without it a
  -- very shaky shot could launch at hundreds of m/s and break the flight integrator.
  speedRange = { 0.5, 1.6 },
  -- Technique level of the shot's family (1-10) -> curves (linear between listed levels).
  technique = {
    -- hand shake x baseWobble; set so a typical on-time rally shot (aimed at the standard
    -- targets) lands in about 25% at Lv1, 50% Lv3, 70% Lv5, 85% Lv7, 95% Lv10
    wobble = { [1] = 11.0, [3] = 4.0, [5] = 2.0, [7] = 1.1, [10] = 0.5 },
    -- wobble x at a full stretch (late): a good technique copes with being late
    late = { [1] = 2.4, [5] = 1.6, [10] = 1.15 },
    -- cross-court shots are harder with a weak technique
    cross = { [1] = 1.5, [5] = 1.15, [10] = 1.03 },
    -- late (or red momentum) AND cross: extra x on top; near-impossible without a good technique
    lateCross = { [1] = 4.0, [5] = 2.5, [7] = 1.7, [10] = 1.2 },
    -- net-clearance shots (drop, net, block, drive, push, short serve): clearance x
    -- (beginners float them high over the tape)
    tightness = { [1] = 2.5, [3] = 1.8, [5] = 1.0, [10] = 0.85 },
    -- highest contact (m) from the overhead technique (mean of clear, drop, smash): beginners
    -- have no overhead, so they let it drop and hit flat or upward (and can't smash, minContact)
    contactCeiling = { [1] = 1.5, [2] = 1.7, [3] = 1.9, [4] = 2.0, [5] = 2.15 },
  },
  timingMul = { early = 0.85, ontime = 1.0 },   -- stretched: technique.late
  -- serves: your own toss, no movement, no incoming shot -> much steadier than a rally shot
  -- (x technique wobble: Lv1 lands ~54% of short serves, Lv2 ~70%, Lv3 ~90%)
  serveEase = 0.35,
  incomingMul = { smash = 1.25, drive = 1.10 },     -- returning fast shots is harder

  earlySlack = 0.30,         -- arrive this many seconds before the shuttle = early
  smashSpeedStep = 2.0,      -- m/s steps when slowing a smash down to clear the net

  skillNames = { clear = "Clear", smash = "Smash", drop = "Drop", net = "Net", drive = "Drive", lift = "Lift" },
}
