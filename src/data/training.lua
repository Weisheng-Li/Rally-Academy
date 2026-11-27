-- Training demo numbers: the coach's schedule, how levels grow with reps, and the athlete's
-- habits (what he does instead of following the plan). Pure data (no love.*).
--
-- Time: the demo clock runs `minutesPerSecond` schedule minutes per simulated second, while
-- the reps themselves play at real speed (a rep every couple of seconds), so a 90 minute drill
-- block is ~3 min on screen and holds a few dozen reps plus breaks.
local T = {}

T.minutesPerSecond = 0.5

-- The schedule we set for him. kind: warmup | drill | gym | free | cooldown.
-- focus: which shots (drill) or exercises (gym) the block is for.
T.schedule = {
  { start = "08:00", stop = "08:20", kind = "warmup",   loc = "court", label = "Warm-up" },
  { start = "08:20", stop = "09:50", kind = "drill",    loc = "court", label = "Drill: net & lift", focus = { "net", "lift" } },
  { start = "09:50", stop = "11:10", kind = "gym",      loc = "gym",   label = "Gym: legs", focus = { "squat", "skip" } },
  { start = "11:10", stop = "12:30", kind = "drill",    loc = "court", label = "Drill: clear & smash", focus = { "clear", "smash", "drop" } },
  { start = "12:30", stop = "13:30", kind = "free",     loc = "gym",   label = "Lunch break" },
  { start = "13:30", stop = "14:50", kind = "gym",      loc = "gym",   label = "Gym: cardio & arms", focus = { "treadmill", "press" } },
  { start = "14:50", stop = "16:20", kind = "drill",    loc = "court", label = "Drill: drives", focus = { "drive", "net" } },
  { start = "16:20", stop = "16:40", kind = "cooldown", loc = "court", label = "Cool down" },
}

-- Reps needed for the next level: base * growth^(level - 1), rounded.
T.levels = { base = 14, growth = 1.25 }

-- Trainable stats and where he starts (levels as in src/data/athletes.lua).
T.skills = {
  technique = { "clear", "lift", "drop", "net", "drive", "smash" },
  physical  = { "power", "speed", "legs", "stamina" },
}
T.start = { clear = 3, lift = 3, drop = 3, net = 3, drive = 3, smash = 3,
            power = 4, speed = 4, legs = 3, stamina = 3 }

-- Drill reps are real shots from the match's shot model (src/core/shots.lua): his technique
-- level decides how often they land in. A rep that lands within perfectRadius (m) of the aim
-- is perfect and counts double; one that misses (net / long / wide) still counts once.
-- tired: low energy makes his hands shakier (wobble x up to 1 + tired).
T.quality = { perfectRadius = 0.6, tired = 0.35, perfectGain = 2, missGain = 1 }

-- Energy 0..1 (hidden): drains while working, refills while resting (per simulated second).
-- Only steers how often he takes breaks and how shaky he gets.
T.energy = { drill = 0.0022, gym = 0.0032, warmup = 0.001, rest = 0.006, nap = 0.012 }

-- Drill sets: one shot type per set, `reps` reps (min, max). Each rep lasts the feed flight,
-- then the return flight + `after` s (at least `recover` s to get back to base).
-- Each rep also trains the legs a little.
T.drill = {
  reps = { 6, 10 }, lead = 2.5, after = 0.5, recover = 1.3,
  physical = { legs = 0.15, stamina = 0.1, speed = 0.05 },
}

-- The feeder: stands here on the far half and hits feeds from height h (m).
T.feeder = { x = 0.3, y = -2.3, h = 1.0 }

-- Drill shots. The feeder's feed (trajectory spec) lands somewhere in x (|x|, side random) /
-- y (m); he meets it at contact height h on the way down and plays `shot` (src/data/shots.lua
-- types) straight at `aim` (x mirrored to his side).
T.shots = {
  net   = { shot = "net",   feed = { kind = "net", clearance = 0.35 }, x = { 0.6, 1.8 }, y = { 1.5, 2.0 }, h = 1.1,
            aim = { x = 0.9, y = -1.2 }, label = "net shots" },
  lift  = { shot = "lift",  feed = { kind = "net", clearance = 0.3 }, x = { 0.6, 1.8 }, y = { 1.4, 1.9 }, h = 0.6,
            aim = { x = 1.8, y = -5.6 }, label = "lifts" },
  drive = { shot = "drive", feed = { kind = "net", clearance = 0.3 }, x = { 1.8, 2.5 }, y = { 3.6, 4.4 }, h = 1.2,
            aim = { x = 2.0, y = -4.0 }, label = "drives" },
  clear = { shot = "clear", feed = { kind = "apex", apex = 5.5 }, x = { 0.3, 2.0 }, y = { 5.2, 6.0 }, h = 2.0,
            aim = { x = 1.8, y = -5.7 }, label = "clears" },
  drop  = { shot = "drop",  feed = { kind = "apex", apex = 5.5 }, x = { 0.3, 2.0 }, y = { 5.2, 6.0 }, h = 2.0,
            aim = { x = 1.4, y = -1.4 }, label = "drops" },
  smash = { shot = "smash", feed = { kind = "apex", apex = 4.5 }, x = { 0.3, 1.8 }, y = { 4.8, 5.6 }, h = 2.0,
            aim = { x = 1.6, y = -3.6 }, label = "smashes" },
}

-- Gym exercises: repTime s per rep, reps per set (min, max), stat gains per rep.
T.exercises = {
  squat     = { label = "Barbell squats", repTime = 2.6, reps = { 6, 10 }, gains = { legs = 1, power = 0.4 } },
  skip      = { label = "Skipping rope",  repTime = 3.0, reps = { 6, 10 }, gains = { speed = 0.8, stamina = 0.5 }, unit = "x10 skips" },
  treadmill = { label = "Treadmill run",  repTime = 4.0, reps = { 8, 12 }, gains = { stamina = 1, speed = 0.3 }, unit = "x100 m" },
  press     = { label = "Shoulder press", repTime = 2.4, reps = { 6, 10 }, gains = { power = 1 } },
  jog       = { label = "Jogging laps",   repTime = 5.0, reps = { 4, 6 },  gains = { stamina = 0.4, speed = 0.1 }, unit = "laps" },
}

-- Breaks and other things he does on his own. dur: seconds (min, max). loc: where it can
-- happen (nil = anywhere). w: base weight when picking what to do after a set.
-- rest = true: energy refills. work weight in a block is T.workWeight.
T.workWeight = 3.5
T.habits = {
  water    = { label = "Water break",          dur = { 6, 10 },  w = 1.2, rest = true },
  shoelace = { label = "Tying his shoelace",   dur = { 4, 6 },   w = 0.3, rest = true },
  chat     = { label = "Chatting with the feeder", dur = { 8, 14 }, w = 0.7, loc = "court", rest = true },
  juggle   = { label = "Juggling the shuttle", dur = { 6, 10 },  w = 0.6, loc = "court", rest = true },
  stretch  = { label = "Stretching",           dur = { 6, 10 },  w = 0.7, rest = true },
  phone    = { label = "Checking his phone",   dur = { 6, 12 },  w = 0.6, rest = true },
  yawn     = { label = "Looking around",       dur = { 3, 5 },   w = 0.4, rest = true },
  music    = { label = "Picking a playlist",   dur = { 4, 6 },   w = 0.5, loc = "gym", rest = true },
  selfie   = { label = "Mirror selfie",        dur = { 4, 6 },   w = 0.3, loc = "gym", rest = true },
  bench    = { label = "Resting on the bench", dur = { 6, 12 },  w = 1.0, loc = "gym", rest = true },
  sulk     = { label = "Annoyed with himself", dur = { 4, 6 },   w = 0, rest = true },   -- after misses
  celebrate = { label = "Fist pump!",          dur = { 2, 3 },   w = 0, rest = true },   -- after a perfect streak
}
-- Lunch break choices (free block) and the cool down.
T.free = {
  nap   = { label = "Napping on the mat", dur = { 25, 40 }, w = 1.0, rest = true, nap = true },
  snack = { label = "Eating a banana",    dur = { 10, 15 }, w = 1.0, rest = true },
  music = { label = "Listening to music", dur = { 15, 25 }, w = 0.8, rest = true },
  phone = { label = "Scrolling his phone", dur = { 10, 20 }, w = 0.7, rest = true },
}
-- Warm-up: jogging laps (T.exercises.jog) and these.
T.warmup = {
  stretch = { label = "Stretching",    dur = { 8, 12 },  w = 0.6, rest = true },
  juggle  = { label = "Juggling the shuttle", dur = { 6, 10 }, w = 0.3, rest = true },
}

-- After a set: how strongly low energy pushes him toward a break, and how much less likely
-- the same habit is twice in a row.
T.tiredBreak = 3.0
T.repeatHabit = 0.25
-- Mid-set surprises: chance per rep his shoelace comes undone; misses in a row before he
-- gets annoyed; perfect reps in a row before he celebrates.
T.shoelaceChance = 0.006
T.sulkAfter = 4
T.celebrateAfter = 4
-- Napping through the end of the lunch break: chance, and how long he oversleeps (s).
T.oversleep = { chance = 0.5, extra = { 4, 10 } }
-- Walking between the court and the gym (s); arriving late in the morning (schedule minutes).
T.walk = 6
T.lateMorning = { -2, 8 }

-- Coach clicks: every click the coach shouts a line and adds 1 hype; hype halves every
-- halfLife s. Speed = 1 + (max - 1) * (1 - exp(-hype / ramp)): about 1.9x after 10 quick
-- clicks, close to max with many more. reply: chance he answers a shout.
T.coach = {
  max = 2.2, ramp = 6, halfLife = 4, reply = 0.08,
  lines = {
    drill = { "Faster feet!", "Come on, lunge!", "Get low!", "Attack it!", "Again, quicker!", "Split step!",
              "Watch the shuttle!", "Good, again!", "Move, move!" },
    gym   = { "Push!", "Two more!", "Don't stop!", "Feel the burn!", "Breathe, push!", "Drive it up!",
              "Keep going!", "Yes!" },
    rest  = { "Quick break!", "Hydrate fast!", "Clock's ticking!", "Shake it out!", "Up you get soon!" },
    lunch = { "Eat up, champ.", "Rest well, big afternoon!", "Chew faster!", "Lunch is lunch." },
    other = { "Hustle!", "Pick it up!", "Come on!", "Let's go!" },
  },
}

-- Things he says. Picked at random from the list for the occasion.
T.lines = {
  perfect   = { "Yes!", "Clean!", "Nice one", "That's it" },
  miss      = { "Oops", "Ugh", "Hmm", "Again" },
  sulk      = { "Come on!", "Focus...", "Argh!" },
  celebrate = { "YES!", "Let's go!", "Too good" },
  levelup   = { "Feels smoother", "Getting it!", "Clicked!" },
  tired     = { "My legs...", "So tired", "Phew", "One more set..." },
  start     = { "Okay, let's go", "Again!", "Ready", "Come on" },
  chat      = { "...", "Haha", "No way", "Did you see the final?", "Yeah yeah" },
  feeder    = { "Haha", "...", "Back to work!", "Right?" },
  phone     = { "lol", "...", "Hm" },
  yawn      = { "*yawn*", "..." },
  late      = { "Sorry, I'm late!", "Traffic..." },
  overslept = { "Five more minutes...", "zzz" },
  selfie    = { "Gains", "*click*" },
  snack     = { "Mmm", "Banana time" },
  yesCoach  = { "Yes coach!", "On it!", "Okay!" },
}

return T
