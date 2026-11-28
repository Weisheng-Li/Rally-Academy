-- Career mode numbers: the day frame, the training programs you can put in it, the
-- tournament for each league, and where a new athlete starts. Pure data (no love.*).
-- Levels / leagues are the 6 in src/data/athletes.lua.
local C = {}

-- The day: fixed blocks and 4 open slots you fill with programs (slot = 1..4).
-- An empty slot is free time (he does his own thing, wandering between rooms). With nothing
-- planned at all, warm-up and cool-down are free time too (src/core/career.lua).
C.day = {
  { start = "08:00", stop = "08:20", kind = "warmup",   loc = "court", label = "Warm-up" },
  { start = "08:20", stop = "10:00", slot = 1 },
  { start = "10:00", stop = "11:40", slot = 2 },
  { start = "11:40", stop = "12:40", kind = "free",     loc = "gym",   label = "Lunch break" },
  { start = "12:40", stop = "14:20", slot = 3 },
  { start = "14:20", stop = "16:00", slot = 4 },
  { start = "16:00", stop = "16:20", kind = "cooldown", loc = "court", label = "Cool down" },
}

-- Program categories, in the order the drawer shows them as tabs.
C.categories = {
  { id = "court",    label = "Court drills" },
  { id = "gym",      label = "Gym" },
}

-- Programs. kind/loc/focus as in src/data/training.lua schedule blocks (drill focus: shots in
-- T.shots; gym focus: exercises in T.exercises; free: he picks lunch-style habits).
-- trains: what the drawer card lists (stats). short: the card's name where the drawer tab already
-- says it (label is what the plan shows).
C.programs = {
  { id = "net_lift",    cat = "court", kind = "drill", loc = "court", label = "Net & lift",
    focus = { "net", "lift" }, trains = "net, lift" },
  { id = "clear_smash", cat = "court", kind = "drill", loc = "court", label = "Clear & smash",
    focus = { "clear", "smash", "drop" }, trains = "clear, smash, drop" },
  { id = "drives",      cat = "court", kind = "drill", loc = "court", label = "Drives",
    focus = { "drive", "net" }, trains = "drive, net" },
  { id = "rear_court",  cat = "court", kind = "drill", loc = "court", label = "Rear court",
    focus = { "clear", "drop" }, trains = "clear, drop" },
  { id = "gym_legs",    cat = "gym", kind = "gym", loc = "gym", label = "Gym: legs", short = "Legs",
    focus = { "squat", "skip" }, trains = "legs, power, speed" },
  { id = "gym_cardio",  cat = "gym", kind = "gym", loc = "gym", label = "Gym: cardio", short = "Cardio",
    focus = { "treadmill", "skip" }, trains = "stamina, speed" },
  { id = "gym_arms",    cat = "gym", kind = "gym", loc = "gym", label = "Gym: arms", short = "Arms",
    focus = { "press" }, trains = "power" },
}

-- A new career's plan (program ids per slot; false = empty): nothing planned, he spends the
-- day on his own until you fill the plan at the lobby whiteboard.
C.defaultPlan = { false, false, false, false }

-- He comes in through the lobby every morning (and leaves through it).
C.arriveAt = "lobby"

-- New athletes start at the Backyard level in everything trainable.
C.startLevel = 1

-- Placeholders until the training stats get their own pass: reach and recovery follow legs,
-- reaction is the league's (src/data/athletes.lua level stats).
C.movement = { fromLegs = { "reach", "recovery" }, fromLeague = { "reaction" } }

-- Tournaments by league: draw size, and the opponent ramp. Your round r opponent (of R) has
-- stats blended from this league's level toward the next by r / R (the final is a preview of
-- the next league), +- spread levels of noise per stat.
C.events = {
  { name = "Neighbourhood Cup",     size = 4 },
  { name = "Rec League Cup",        size = 4 },
  { name = "Club Open",             size = 8 },
  { name = "Regional Championship", size = 8 },
  { name = "National Championship", size = 16 },
  { name = "World Championship",    size = 32 },
}
C.spread = 0.6
C.beyondTop = 1.5      -- the World Championship final: up to this many levels above Lv6 stats (capped at 10)

-- Matches you are not in: the stronger rating wins with this chance at a 1-level gap
-- (closer gaps are closer to a coin flip).
C.upsetEdge = 0.75

-- Score for tournament matches (first to `points`, win by 2, capped).
C.match = { points = 5, cap = 7 }

-- Opponent names (picked without repeats in a draw).
C.names = {
  "Okafor", "Lindqvist", "Tanaka", "Moreau", "Haddad", "Kowalski", "Silva", "Nguyen", "Brennan", "Ivanova",
  "Mendez", "Osei", "Larsen", "Park", "Rossi", "Abebe", "Fischer", "Kaur", "Dubois", "Sato",
  "Novak", "Quinn", "Herrera", "Yilmaz", "Petrov", "Achebe", "Lund", "Chen", "Marsh", "Varga",
  "Costa", "Ito", "Byrne", "Wolff", "Reyes", "Hale", "Mori", "Jansen", "Adeyemi", "Kim",
}

return C
