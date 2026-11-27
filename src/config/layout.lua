-- Everything visual you may want to nudge by hand lives here.
-- All positions are in virtual pixels (the game renders at width x height and scales up).
return {
  width = 640,
  height = 360,

  -- 2.5D court camera, described by where the court ends up on screen.
  camera = {
    centerX = 320,       -- screen x of the court's center line
    nearY = 335,         -- screen y of the near baseline
    farY = 110,          -- screen y of the far baseline
    nearWidth = 420,     -- on-screen width of the near baseline (doubles width)
    farWidth = 230,      -- on-screen width of the far baseline
    heightScale = 0.45,  -- squash vertical heights (shuttle arcs, players) to fit the screen
  },

  fonts = { small = 8, normal = 10, big = 20, title = 32 },

  hud = {
    scoreX = 8, scoreY = 8,
    promptY = 344,
    hintX = 8, hintY = 346,
    -- your heart rate (only yours: the opponent's is for you to read from how they move)
    hr = { x = 8, y = 58, textY = 11,     -- bpm with a pulsing dot, what it does to you below
           showOpponent = true, oppY = 86 },  -- TEMPORARY debug: the opponent's too (normally hidden)
  },

  targets = {
    ringRadius = 0.45,    -- meters, ground ring around each target zone
    bubbleHeight = 2.4,   -- meters above the ground (before heightScale)
    bubbleW = 30, bubbleH = 13,
    bubbleOffsetX = 14,   -- push bubbles outward so the pins look like the sketch
  },

  -- Title / level picker: your level on the left, the opponent's on the right, stats between.
  menu = {
    titleY = 14, subtitleY = 50,
    youX = 16, oppX = 444, listY = 84, rowW = 180, rowH = 32, rowGap = 4,
    statsX = 206, statsY = 84, statsW = 228, statsH = 212,
    hintY = 340,
  },

  -- Shot breakdown panel. Shown at leftX when hovering a right-side target, rightX for left-side.
  tooltip = { width = 200, leftX = 4, rightX = 436, y = 84, padding = 5, lineH = 11 },

  -- Player / racket / shuttle sizes live in src/core/body.lua (shared with the rules and
  -- checked by tests/), not here.

  -- Streak behind a skidding shuttle: shows only its last `skidTrail` seconds, fading out.
  skidTrail = 0.25,

  -- "WINNER!" / "OUT!" popup: bottom edge starts this high (m) above the landing spot and rises.
  popup = { startHeight = 1.0, rise = 1.5 },

  -- Trajectory preview color by flight time: fastTime or quicker = fast color,
  -- slowTime or longer = slow color, passing through mid halfway (red -> white -> blue).
  flightColors = {
    fast = { 1.00, 0.30, 0.25 }, fastTime = 0.6,   -- red: hard, quick shots (smash, drive)
    mid  = { 0.92, 0.92, 0.92 },                    -- white: medium-paced shots (drops)
    slow = { 0.40, 0.65, 1.00 }, slowTime = 2.0,   -- blue: floaty shots (clear, lift)
  },

  colors = {
    bg         = { 0.10, 0.12, 0.16 },
    floor      = { 0.20, 0.24, 0.30 },
    court      = { 0.16, 0.42, 0.34 },
    lines      = { 0.93, 0.93, 0.88 },
    net        = { 0.05, 0.05, 0.07, 0.55 },
    netTape    = { 0.95, 0.95, 0.95 },
    post       = { 0.80, 0.80, 0.85 },
    near       = { 0.30, 0.65, 1.00 },
    far        = { 1.00, 0.45, 0.35 },
    shadow     = { 0, 0, 0, 0.35 },
    shuttle    = { 1, 1, 1 },
    skidMark   = { 1, 1, 1, 0.4 },    -- streak behind a skidding shuttle (fades out)
    good       = { 0.45, 0.90, 0.45 },
    ok         = { 1.00, 0.85, 0.35 },
    bad        = { 1.00, 0.40, 0.35 },
    disabled   = { 0.55, 0.55, 0.60 },
    recovery   = { 0.55, 0.85, 1.00 },
    panel      = { 0.06, 0.07, 0.10, 0.92 },
    panelEdge  = { 0.85, 0.85, 0.90 },
    text       = { 0.95, 0.95, 0.95 },
    textDim    = { 0.65, 0.68, 0.75 },
  },

  timeScale = 1.0,   -- 1.0 = real time; [ and ] change it in game
}
