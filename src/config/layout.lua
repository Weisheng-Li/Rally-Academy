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
    logX = 486, logY = 8, logWidth = 148, logLines = 6,
    promptY = 344,
    hintX = 8, hintY = 346,
  },

  targets = {
    ringRadius = 0.45,    -- meters, ground ring around each target zone
    bubbleHeight = 2.4,   -- meters above the ground (before heightScale)
    bubbleW = 30, bubbleH = 13,
    bubbleOffsetX = 14,   -- push bubbles outward so the pins look like the sketch
  },

  -- Shot breakdown panel. Shown at leftX when hovering a right-side target, rightX for left-side.
  tooltip = { width = 200, leftX = 4, rightX = 436, y = 84, padding = 5, lineH = 11 },

  actor = { bodyHeight = 1.75, width = 0.42 },

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
