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

  -- Training demo (lovec . --demo training, or T on the title screen).
  training = {
    -- closer camera than the match: the near half fills the screen
    camera = { centerX = 320, nearY = 352, farY = 128, nearWidth = 520, farWidth = 268, heightScale = 0.5 },
    schedule = { x = 4, y = 4, w = 132, rowH = 12 },         -- coach's plan, top left
    stats = { x = 504, y = 4, w = 132, rowH = 11 },          -- stat levels + rep bars, top right
    now = { y = 4, w = 220 },                                -- clock + what he is doing, top centre
    hintY = 350,
    walkSpeed = 1.4,                                         -- m/s between spots
    -- world spots (court metres; the gym uses the same floor coordinates)
    court = {
      base = { x = 0, y = 3.3 }, basket = { x = 1.4, y = -2.6 },   -- feeder: src/data/training.lua
      bench = { x = 3.6, y = 4.4 }, water = { x = 2.85, y = 4.4 },
      chat = { x = 0.7, y = 0.6 }, chatFeeder = { x = -0.1, y = -0.6 }, juggle = { x = 0.8, y = 3.6 },
      jog = { x1 = -2.2, x2 = 2.2, y1 = 1.2, y2 = 5.9 },
      entry = { x = 5.8, y = 4.2 },
    },
    gym = {
      wallY = -1.8,
      treadmill = { x = -2.3, y = -0.5 }, rack = { x = 0.2, y = -0.7 }, skip = { x = 0.3, y = 2.4 },
      press = { x = 2.5, y = 0.9 }, dumbbells = { x = 3.3, y = -0.9 }, bench = { x = 2.4, y = 3.8 },
      mat = { x = -1.7, y = 4.3 }, cooler = { x = -3.6, y = -1.2 }, water = { x = -3.0, y = -0.9 },
      mirror = { x1 = 1.0, x2 = 3.6 }, selfie = { x = 2.3, y = -0.9 }, speaker = { x = -3.2 },
      idle = { x = 0.3, y = 2.4 }, entry = { x = -5.6, y = 3.2 }, coach = { x = -1.3, y = 1.5 },
    },
    -- the lobby (between the court and the gym): front desk, pro shop, WC, the plan whiteboard.
    -- entry = the street door (he walks in from below the screen).
    lobby = {
      wallY = -1.8, idle = { x = 0.6, y = 2.6 }, entry = { x = 0.6, y = 8.4 },
      desk = { x = 1.95, y = -0.3, hx = 1.0, hy = 0.35, h = 1.05 }, receptionist = { x = 1.95, y = -1.05 },
      deskFront = { x = 1.7, y = 0.6 }, deskSign = { x1 = 0.9, x2 = 3.0 },
      board = { x1 = -1.7, x2 = 0.3, z1 = 1.0, z2 = 2.1 },              -- whiteboard on the back wall
      wcDoor = { x1 = -2.95, x2 = -2.35, h = 2.4 }, wc = { x = -2.65, y = -1.25 },   -- tall and narrow: heights are squashed on screen
      shopWall = { x1 = -9, x2 = -3.3 },                                -- slatwall with rackets + shoes
      cabinet = { x = -5.2, y = -1.3, hx = 1.2, hy = 0.32, h = 0.85 }, browse = { x = -4.8, y = -0.45 },
      stringer = { x = -2.4, y = 1.3 }, stringerWatch = { x = -1.7, y = 1.7 },
      sofa = { x = -3.2, y = 3.6 }, sofaSit = { x = -3.24, y = 3.6 }, water = { x = 4.7, y = -1.1 }, fountain = { x = 5.3, y = -1.45 },
      plant = { x = 3.4, y = -1.35 }, mat = { x = 0.6, y = 6.3 },
    },
    -- doors between rooms: doors[room][neighbour] = where that door is in `room` (m, off-screen
    -- at the side, so he walks out of the picture toward the next room)
    doors = {
      court = { lobby = { x = 5.8, y = 4.2 } },
      lobby = { court = { x = -6.6, y = 3.0 }, gym = { x = 6.6, y = 3.0 } },
      gym = { lobby = { x = -5.6, y = 3.2 } },
    },
    roomNames = { court = "Court", lobby = "Lobby", gym = "Gym" },
    lobbyLook = {
      plank = 0.4, plankLen = 2.0, wallTop = 2.9,
      rackets = { -8.2, -7.6, -7.0, -6.4, -5.8, -5.2, -4.6, -4.0 },     -- x of the rackets on the slatwall
      shopSign = { x1 = -7.2, x2 = -4.6 }, shoes = { -8.8, -8.25, -7.7 },
      sofa = { hx = 0.28, hy = 0.75, seat = 0.42, back = 0.85, backT = 0.14, arm = 0.6, armT = 0.14 },   -- half sizes (long along y), heights, thicknesses
    },
    -- gym decoration (metres): plank width/length, wall panel width, trim height, windows,
    -- poster, red rug, chequered tiles (skipping spot), plant, gym ball, loose weights
    -- courtside bench (m): seat half sizes (long along y), seat height + thickness, legs at
    -- +-legY; racket bag (centre y offset, half sizes, height) and the bottle's y offset
    courtBench = { hx = 0.22, hy = 0.85, seat = 0.42, thick = 0.07, legY = 0.65, clear = 0.35,   -- clear: he walks round it this far off
                   bag = { y = -0.1, len = 0.8, width = 0.24, hHead = 0.42, hHandle = 0.27, round = 0.18,
                           roundBottom = 0.03, dir = { x = 0.8, y = 0.6 } },   -- dir: its length, on the ground
                   bottleY = 0.6 },
    gymLook = {
      plank = 0.45, plankLen = 2.4, panel = 0.35, wallTop = 2.9,
      windows = { { x1 = -4.9, x2 = -3.4 }, { x1 = -3.0, x2 = -1.6 } },
      poster = { x = -1.05 },
      rug = { x = 2.5, y = 0.9, hx = 1.0, hy = 0.7 },
      tiles = { x = 0.3, y = 2.4, n = 4, size = 0.5 },
      plant = { x = -4.4, y = 0.6 }, ball = { x = 3.9, y = 2.4, r = 0.33 },
      bench = { hx = 0.7, hy = 0.18, legX = 0.5, padZ = 0.36, top = 0.45 },   -- pad from padZ up to top (m)
      floorWeights = { { x = -0.4, y = 4.7, color = "dbRed" }, { x = -0.2, y = 5.0, color = "dbBlue" },
                       { x = 3.7, y = 0.1, color = "dark", kettle = true } },
    },
    colors = {
      -- gym: warm wood + beige, coloured mats (equipment stays charcoal metal)
      gymFloor = { 0.80, 0.58, 0.36 }, gymFloorLight = { 0.85, 0.64, 0.42 }, gymFloorLine = { 0.62, 0.42, 0.25 },
      wall = { 0.93, 0.84, 0.68 }, wallStripe = { 0.88, 0.77, 0.60 }, wallTrim = { 0.97, 0.97, 0.95 },
      baseboard = { 0.55, 0.38, 0.24 }, glass = { 0.70, 0.84, 0.96 },
      gymMat = { 0.30, 0.74, 0.62 }, gymMatEdge = { 0.20, 0.58, 0.48 },
      rug = { 0.78, 0.22, 0.28 }, rugEdge = { 0.62, 0.14, 0.20 }, rubber = { 0.40, 0.40, 0.46 },
      tileA = { 0.50, 0.50, 0.56 }, tileB = { 0.40, 0.40, 0.46 },
      poster = { 0.35, 0.60, 0.90 }, trophy = { 1.0, 0.80, 0.20 },
      dbRed = { 0.88, 0.25, 0.25 }, dbBlue = { 0.25, 0.50, 0.90 },
      pot = { 0.62, 0.38, 0.22 }, potTop = { 0.50, 0.30, 0.18 }, leaf = { 0.35, 0.70, 0.30 },
      leafDark = { 0.22, 0.52, 0.22 }, ball = { 0.25, 0.55, 0.95 },
      pad = { 0.78, 0.24, 0.28 }, padSide = { 0.55, 0.14, 0.18 },
      benchTop = { 0.25, 0.45, 0.85 }, benchSide = { 0.16, 0.30, 0.62 }, benchLeg = { 0.18, 0.32, 0.66 },
      bag = { 0.42, 0.26, 0.19 }, bagTop = { 0.30, 0.18, 0.13 }, bagPanel = { 0.58, 0.38, 0.25 },
      bagTrim = { 0.95, 0.55, 0.15 },
      metal = { 0.62, 0.64, 0.70 }, dark = { 0.22, 0.22, 0.26 },
      wood = { 0.55, 0.38, 0.22 }, mirror = { 0.80, 0.90, 0.97 }, water = { 0.45, 0.75, 1.0 },
      banana = { 1.0, 0.88, 0.25 }, phone = { 0.65, 0.90, 1.0 },
      perfect = { 1.0, 0.85, 0.30 }, levelup = { 1.0, 0.80, 0.20 },
      coach = { 1.0, 0.72, 0.30 }, sweat = { 0.70, 0.88, 1.0 },
      coachShirt = { 0.85, 0.28, 0.25 }, coachCap = { 0.15, 0.18, 0.30 },   -- coach (= the feeder on court)
      -- lobby: light wood floor, white walls, warm wood furniture, green shop sign
      lobbyFloor = { 0.84, 0.72, 0.55 }, lobbyFloorLight = { 0.88, 0.77, 0.60 }, lobbyFloorLine = { 0.72, 0.60, 0.44 },
      lobbyWall = { 0.93, 0.92, 0.89 }, slat = { 0.86, 0.86, 0.84 }, slatLine = { 0.74, 0.74, 0.72 },
      cabinet = { 0.82, 0.52, 0.24 }, cabinetTop = { 0.90, 0.62, 0.32 }, cabinetLine = { 0.62, 0.36, 0.14 },
      desk = { 0.32, 0.34, 0.40 }, deskTop = { 0.86, 0.80, 0.70 }, deskPanel = { 0.20, 0.55, 0.45 },
      shopSign = { 0.16, 0.55, 0.43 }, door = { 0.97, 0.97, 0.96 }, doorFrame = { 0.80, 0.80, 0.78 },
      board = { 0.98, 0.98, 0.98 }, boardFrame = { 0.62, 0.64, 0.70 },
      stringer = { 0.62, 0.10, 0.12 }, sofa = { 0.25, 0.30, 0.42 }, sofaTop = { 0.32, 0.38, 0.52 }, sofaSeat = { 0.38, 0.45, 0.60 },
      entryMat = { 0.30, 0.30, 0.33 }, receptionShirt = { 0.20, 0.55, 0.45 },
      racketFrames = { { 0.90, 0.20, 0.25 }, { 0.20, 0.45, 0.90 }, { 0.15, 0.15, 0.18 }, { 0.95, 0.75, 0.15 },
                       { 0.30, 0.70, 0.40 }, { 0.85, 0.85, 0.88 }, { 0.60, 0.30, 0.80 }, { 0.95, 0.45, 0.15 } },
      shoes = { { 0.90, 0.25, 0.25 }, { 0.25, 0.55, 0.90 }, { 0.95, 0.95, 0.95 }, { 0.30, 0.75, 0.45 } },
      bags = { { 0.85, 0.15, 0.20 }, { 0.15, 0.20, 0.35 }, { 0.20, 0.45, 0.85 } },
    },
  },

  -- League emblems (src/view/emblem.lua): frame / gem colour per tier (1-6 leagues, 7 = World Champion).
  emblems = {
    hole = { 0.08, 0.10, 0.16 },
    tiers = {
      { name = "Bronze",   frame = { 0.73, 0.49, 0.27 } },
      { name = "Silver",   frame = { 0.73, 0.75, 0.79 } },
      { name = "Gold",     frame = { 0.96, 0.71, 0.20 } },
      { name = "Platinum", frame = { 0.80, 0.85, 0.92 } },
      { name = "Emerald",  frame = { 0.37, 0.79, 0.56 } },
      { name = "Diamond",  frame = { 0.50, 0.70, 0.95 } },
      { name = "World Champion", frame = { 0.96, 0.71, 0.20 }, gem = { 0.61, 0.78, 1.00 } },
    },
  },

  -- Title screen hall (src/view/hall_view.lua): the match camera on an empty centre court,
  -- busy courts around it. Courts are offset in metres from the centre court.
  hall = {
    -- like the match camera, tilted up a little so the back row, wall and lights show
    camera = { centerX = 320, nearY = 330, farY = 146, nearWidth = 420, farWidth = 206, heightScale = 0.45 },
    gap = 2.0,                 -- m between neighbouring courts (side by side)
    backGap = 3.0,             -- m between the front row and the back row
    sideCourts = { -1, 1 },    -- front row neighbours (in court widths + gaps)
    backCourts = { -2, -1, 0, 1, 2 },
    wallBehind = 2.5,          -- m behind the back row's far baseline
    ceilingY = 26,             -- screen y where the back wall meets the ceiling
    lights = { rows = 4, perRow = 7 },
    woodStrip = 0.9,           -- m of wood floor in front of the near baseline
    walkers = 6, walkSpeed = { 0.9, 1.3 },
    titleY = 30, buttonW = 120, buttonH = 22, buttonDepth = 3.8,   -- New career sits this far (m) into the near half
    -- name dialog (New career): box, input field, Start / Cancel buttons
    naming = { w = 240, h = 104, y = 128, fieldW = 180, fieldH = 18, fieldY = 34, buttonW = 70, buttonH = 18,
               buttonY = 70, buttonGap = 16, maxLen = 12 },
    colors = {
      floor = { 0.12, 0.52, 0.42 }, court = { 0.10, 0.58, 0.47 }, lines = { 0.92, 0.95, 0.92 },
      wall = { 0.09, 0.10, 0.12 }, wallTrim = { 0.13, 0.14, 0.17 }, ceiling = { 0.06, 0.07, 0.09 },
      light = { 0.95, 0.97, 1.00 }, glow = { 0.85, 0.92, 1.00 },
      post = { 0.95, 0.78, 0.15 }, wood = { 0.78, 0.64, 0.46 }, woodLine = { 0.70, 0.56, 0.39 },
      spot = { 1.00, 0.95, 0.80 },
      shirts = { { 0.30, 0.65, 1.00 }, { 1.00, 0.45, 0.35 }, { 0.36, 0.73, 0.54 }, { 0.61, 0.42, 0.84 },
                 { 0.88, 0.64, 0.23 }, { 0.91, 0.44, 0.56 }, { 0.82, 0.84, 0.88 }, { 0.20, 0.22, 0.28 } },
    },
  },

  -- Career hub (src/scenes/hub.lua): the training view plus the career panels.
  hub = {
    accent = { 0.95, 0.78, 0.15 },                               -- drag targets, Enter, hover
    plan = { x = 4, y = 4, w = 140, rowH = 13, slotH = 16, snap = 0.5 },   -- today's plan, top left; snap: share of the dragged chip that must cover a slot
    stats = { x = 504, y = 4, w = 132, rowH = 11 },              -- stat levels + rep bars, top right
    top = { y = 4, w = 220 },                                    -- league, day, clock, activity
    deskCard = { w = 150, h = 46 },                              -- pops up over the lobby's front desk on hover
    doors = { y = 176, w = 18, h = 74 },                         -- door tabs at the screen edges (to the next room)
    fade = 0.25,                                                 -- s of black when the view changes room
    card = { x = 590, y = 330, w = 20, h = 20 },                 -- Athlete (your headshot icon)
    menu = { x = 614, y = 330, w = 20, h = 20 },                 -- back to the title (arrow icon)
    drawer = { x = 150, y = 60, w = 340, h = 122, tabH = 16, cardW = 104, cardH = 32, gap = 6 },
    -- athlete page (full screen, src/view/athlete_view.lua): stat rows on the left, the picked
    -- stat's detail on the right
    athlete = { back = { x = 6, y = 6, w = 18, h = 18 }, headX = 32, headY = 8,
                split = { x = 8, y = 36, w = 196, rowH = 22, rowGap = 2, paneX = 216 } },
    hintY = 350,
  },

  -- Tournament screens (src/scenes/tournament.lua, src/scenes/promotion.lua).
  tournament = {
    headerY = 10, bracketX = 16, bracketY = 64, bracketW = 380, bracketH = 260,
    centerW = 64, headColW = 24, minPillW = 70, maxPillW = 112, maxPillH = 24, maxRowH = 56,   -- bracket: final column, later-round columns, round-1 pills, row spacing cap
    previewX = 412, previewY = 64, previewW = 212, previewH = 200,
    buttonY = 300, buttonW = 120, buttonH = 22, withdrawW = 70, withdrawH = 14,   -- Withdraw: under Play, before the first match
  },
  promotion = { emblemY = 150, emblemR = 52, textY = 236 },

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
