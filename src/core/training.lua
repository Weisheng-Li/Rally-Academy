-- Training simulation (idle mode): the athlete follows the coach's schedule (data/training.lua)
-- in his own way - sets of drill reps with a feeder, gym sets, and in between whatever he
-- feels like (water, phone, chatting, a nap that runs long...). Every rep adds progress to a
-- stat; enough reps level it up, each level needing more.
-- Pure Lua (no love.*): randomness comes in through opts.rng (returns [0, 1)).
--
-- State the view reads:
--   s.clock (schedule minutes since midnight), s.day, s.location ("court" | "lobby" | "gym")
--   s.activity  current activity: kind ("drill" | "exercise" | "habit" | "walk" | "arrive" |
--               "home"), name, label, t / dur (s), and for rep activities lead, reps / repsTarget,
--               cur (this rep: i, t0 / contactT / endT (activity seconds), and for drills the
--               feed + ret flight paths, contact, outcome, quality)
--   s.skills[name] = { level, progress }, s.energy (0..1), s.music (headphones on),
--   s.bubble / s.feederBubble / s.coachLine ({ text, t }), s.hype (coach clicks, fading),
--   s.pace (his speed this update, Training.speed), s.log, s.events (drained by the view)
local T = require("src.data.training")
local Traj = require("src.core.trajectory")
local Shots = require("src.core.shots")
local Curve = require("src.core.curve")
local Stats = require("src.data.stats")

local Training = {}
Training.data = T

local function pick(rng, list) return list[math.floor(rng() * #list) + 1] end
local function range(rng, r) return r[1] + (r[2] - r[1]) * rng() end
local function irange(rng, r) return math.floor(r[1] + (r[2] - r[1] + 1) * rng()) end

function Training.minutes(hhmm)
  local h, m = hhmm:match("(%d+):(%d+)")
  return tonumber(h) * 60 + tonumber(m)
end

function Training.clockText(minutes)
  local m = math.floor(minutes) % (24 * 60)
  return string.format("%02d:%02d", math.floor(m / 60), m % 60)
end

-- Reps needed to go from `level` to the next.
function Training.repsFor(level)
  return math.floor(T.levels.base * T.levels.growth ^ (level - 1) + 0.5)
end

local SCHEDULE = {}
for i, b in ipairs(T.schedule) do
  SCHEDULE[i] = { i = i, start = Training.minutes(b.start), stop = Training.minutes(b.stop), kind = b.kind,
                  loc = b.loc, label = b.label, focus = b.focus }
end
Training.schedule = SCHEDULE

-- Schedule blocks from { start = "HH:MM", stop = "HH:MM", kind, loc, label, focus } defs.
function Training.buildSchedule(defs)
  local out = {}
  for i, b in ipairs(defs) do
    out[i] = { i = i, start = Training.minutes(b.start), stop = Training.minutes(b.stop), kind = b.kind,
               loc = b.loc, label = b.label, focus = b.focus }
  end
  return out
end

-- Rooms (T.rooms, left to right; neighbours share a door). Next room on the way from a to b.
local ROOM_I = {}
for i, r in ipairs(T.rooms) do ROOM_I[r] = i end
function Training.nextRoom(a, b)
  local i, j = ROOM_I[a], ROOM_I[b]
  if not i or not j or i == j then return b end
  return T.rooms[i + (j > i and 1 or -1)]
end

function Training.neighbours(room)
  local i, out = ROOM_I[room], {}
  if T.rooms[i - 1] then out[#out + 1] = T.rooms[i - 1] end
  if T.rooms[i + 1] then out[#out + 1] = T.rooms[i + 1] end
  return out
end

function Training.block(s)
  for _, b in ipairs(s.schedule or SCHEDULE) do
    if s.clock >= b.start and s.clock < b.stop then return b end
  end
  return nil
end

---------------------------------------------------------------------------- talking + log
function Training.say(s, key, who)
  local text = pick(s.rng, T.lines[key])
  if who == "feeder" then s.feederBubble = { text = text, t = 2.2 }
  else s.bubble = { text = text, t = 2.0 } end
end

local function log(s, text)
  s.log[#s.log + 1] = { clock = s.clock, text = text }
  if #s.log > 60 then table.remove(s.log, 1) end
end

local function event(s, e) s.events[#s.events + 1] = e end

---------------------------------------------------------------------------- progress
local function addProgress(s, name, amount)
  local sk = s.skills[name]
  sk.progress = sk.progress + amount
  while sk.progress >= Training.repsFor(sk.level) do
    sk.progress = sk.progress - Training.repsFor(sk.level)
    sk.level = sk.level + 1
    event(s, { type = "levelup", skill = name, level = sk.level })
    log(s, string.format("%s up to level %d!", name, sk.level))
    Training.say(s, "levelup")
  end
end

---------------------------------------------------------------------------- coach clicks
-- Clicking cheers him on: the coach shouts something every click and each click adds 1 hype.
-- Hype fades over time (halves every T.coach.halfLife s). His speed is
--   1 + (max - 1) * (1 - exp(-hype / ramp))
-- so spamming works but with diminishing returns: ~10 quick clicks get him close to 2x,
-- more clicks add little. At speed x his activity runs x times faster (reps, breaks, walking,
-- the feeder) while the schedule clock keeps its pace, so he packs more reps into each block
-- (and tires sooner: energy changes with his own time).
function Training.speed(s)
  local C = T.coach
  return 1 + (C.max - 1) * (1 - math.exp(-s.hype / C.ramp))
end

-- One click. The coach's line depends on what he is doing.
function Training.coach(s)
  s.hype = s.hype + 1
  local a = s.activity
  local b = Training.block(s)
  local key = (b and b.kind == "free" and "lunch") or (b and b.kind == "idle" and "other") or (a.kind == "drill" and "drill") or
              (a.kind == "exercise" and "gym") or (a.kind == "habit" and "rest") or "other"
  local line = pick(s.rng, T.coach.lines[key])
  if s.coachLine and s.coachLine.text == line then line = pick(s.rng, T.coach.lines[key]) end
  s.coachLine = { text = line, t = 1.6, life = 1.6, shout = true }
  if s.rng() < T.coach.reply then Training.say(s, "yesCoach") end
  event(s, { type = "coach" })
end

-- His stats as the match's shot model reads them (levels; see src/data/athletes.lua).
-- Untrained stats (reach, reaction, recovery) are 3 unless the owner (the career) sets
-- s.statsHook(st) to fill them in.
function Training.stats(s)
  local st = { reach = 3, reaction = 3, recovery = 3 }
  for name, sk in pairs(s.skills) do st[name] = sk.level end
  if s.statsHook then s.statsHook(st) end
  return st
end

-- One drill rep, flown with the match's physics (src/core/trajectory.lua) and shot model
-- (src/core/shots.lua):
--   feed    the feeder sends the shuttle to land at a random spot of the drill's area; he
--           meets it on the way down at the shot's contact height (Shots.contactOnPath)
--   return  his shot from there to the drill's aim point: Shots.evaluate with his technique,
--           then Shots.execute with a real random hand shake -> in / net / long / wide
-- Returns the rep: feed + ret paths (world {x,y,h} every dt s), contact point/height/time,
-- outcome, quality ("perfect" = in and within perfectRadius of the aim, "good", "miss").
function Training.drillRep(s, shotName, rng)
  local S = T.shots[shotName]
  local F = T.feeder
  local side = rng() < 0.5 and -1 or 1
  local land = { x = side * range(rng, S.x), y = range(rng, S.y) }
  local fdx, fdy = land.x - F.x, land.y - F.y
  local fdist = math.sqrt(fdx * fdx + fdy * fdy)
  local netS = -F.y / (fdy / fdist)
  local sol = Traj.solve(F.h, fdist, netS, S.feed)
  local rec = Traj.fly(F.h, sol.speed * math.cos(sol.angle), sol.speed * math.sin(sol.angle), netS, { record = true })
  local feed = Shots.worldPath(F, fdx / fdist, fdy / fdist, rec.points)
  local dt = Traj.config.dt
  local cpos, ctime, ch = Shots.contactOnPath(feed, dt, S.h)
  -- cut the feed at the contact
  local nFeed = math.min(#feed, math.floor(ctime / dt) + 2)
  for i = #feed, nFeed + 1, -1 do feed[i] = nil end
  feed[#feed] = { x = cpos.x, y = cpos.y, h = ch }

  local aim = { x = S.aim.x * (cpos.x >= 0 and 1 or -1), y = S.aim.y }
  local stats = Training.stats(s)
  local ctx = { stats = stats, from = cpos, h0 = ch, contact = { state = "ontime" },
                maxSpeed = Curve.at(Stats.power, stats.power),
                -- tired: shakier hands
                hrMul = 1 + T.quality.tired * (1 - s.energy) }
  local ev = Shots.evaluate(ctx, aim, S.shot)
  local rep = { feed = feed, dt = dt, contact = cpos, h = ch, feedTime = ctime, aim = aim, success = ev.success }
  if not ev.available then              -- can't play it from there: straight into the net
    rep.outcome, rep.ret, rep.retTime = "net", { { x = cpos.x, y = cpos.y, h = ch }, { x = cpos.x, y = 0.02, h = 0.8 } }, 0.3
  else
    local res = Shots.execute(ctx, ev, rng)
    rep.outcome, rep.ret, rep.retTime, rep.landing = res.outcome, res.path, res.time, res.landing
  end
  if rep.outcome ~= "in" then rep.quality = "miss"
  elseif math.sqrt((rep.landing.x - aim.x) ^ 2 + (rep.landing.y - aim.y) ^ 2) <= T.quality.perfectRadius then
    rep.quality = "perfect"
  else rep.quality = "good" end
  return rep
end

-- n practice shots of a drill (T.shots[shotName]) for someone with these stats, from the
-- middle of the drill's hitting area to its aim: real shot model + real hand shake, no
-- feeder, no tiredness. For the athlete page's landing clouds.
-- Returns { from, aim, points = { {x, y, outcome} }, inCount, available }.
function Training.practice(stats, shotName, n, rng)
  local S = T.shots[shotName]
  local from = { x = (S.x[1] + S.x[2]) / 2, y = (S.y[1] + S.y[2]) / 2 }
  local aim = { x = S.aim.x, y = S.aim.y }
  local ctx = { stats = stats, from = from, h0 = S.h, contact = { state = "ontime" },
                maxSpeed = Curve.at(Stats.power, stats.power or 5) }
  local ev = Shots.evaluate(ctx, aim, S.shot)
  local out = { from = from, aim = aim, points = {}, inCount = 0, available = ev.available, n = n }
  if not ev.available then return out end
  for i = 1, n do
    local res = Shots.execute(ctx, ev, rng)
    out.points[i] = { x = res.landing.x, y = res.landing.y, outcome = res.outcome }
    if res.outcome == "in" then out.inCount = out.inCount + 1 end
  end
  return out
end

-- Next rep of the set, starting at a.t0: drills fly a real feed and return; gym reps take repTime.
local function startRep(s, a, t0)
  a.started = a.started + 1
  local cur
  if a.kind == "drill" then
    cur = Training.drillRep(s, a.name, s.rng)
    cur.contactT = t0 + cur.feedTime
    cur.endT = cur.contactT + math.max(cur.retTime + T.drill.after, T.drill.recover)
  else
    local len = a.repTime
    cur = { quality = "good", contactT = t0 + a.contact * len, endT = t0 + len }
  end
  cur.i, cur.t0 = a.started, t0
  a.cur = cur
  a.nextStart = cur.endT
  if a.started >= a.repsTarget then a.dur = cur.endT end
end

local function finishRep(s, a)
  a.reps = a.reps + 1
  local q = a.cur.quality
  s.totalReps = s.totalReps + 1
  if a.kind == "drill" then
    local Q = T.quality
    local gain = q == "perfect" and Q.perfectGain or (q == "miss" and Q.missGain or 1)
    addProgress(s, a.name, gain)
    for stat, g in pairs(T.drill.physical) do addProgress(s, stat, g) end
    event(s, { type = "rep", skill = a.name, quality = q, gain = gain, outcome = a.cur.outcome })
    if q == "miss" then
      s.missStreak, s.perfectStreak = s.missStreak + 1, 0
      if s.missStreak >= T.sulkAfter then
        Training.say(s, "sulk"); s.wantSulk = true; s.missStreak = 0
      elseif s.rng() < 0.35 then Training.say(s, "miss") end
    else
      s.missStreak = 0
      s.perfectStreak = q == "perfect" and s.perfectStreak + 1 or 0
      if s.perfectStreak >= T.celebrateAfter then
        Training.say(s, "celebrate"); s.wantCelebrate = true; s.perfectStreak = 0
      elseif q == "perfect" and s.rng() < 0.25 then Training.say(s, "perfect") end
    end
    -- shoelace came undone: the set stops here
    if a.reps < a.repsTarget and s.rng() < T.shoelaceChance then
      a.repsTarget, a.dur, s.forced = a.reps, a.cur.endT, "shoelace"
      log(s, "Shoelace came undone")
    end
  else
    for stat, g in pairs(a.gains) do addProgress(s, stat, g) end
    event(s, { type = "rep", skill = a.main, quality = q, gain = a.gains[a.main] })
  end
  if s.energy < 0.3 and s.rng() < 0.04 then Training.say(s, "tired") end
end

---------------------------------------------------------------------------- activities
local function activity(kind, name, label, dur, fields)
  local a = { kind = kind, name = name, label = label, dur = dur, t = 0 }
  for k, v in pairs(fields or {}) do a[k] = v end
  return a
end

local function drillSet(s, shot)
  local D = T.drill
  local n = irange(s.rng, D.reps)
  -- dur is set when the last rep starts (rep lengths come from the flights)
  return activity("drill", shot, "Drill: " .. T.shots[shot].label, math.huge,
    { lead = D.lead, reps = 0, started = 0, repsTarget = n, nextStart = D.lead,
      energyUse = "drill", onPlan = true, main = shot })
end

local function exerciseSet(s, name, energyUse)
  local E = T.exercises[name]
  local n = irange(s.rng, E.reps)
  local main, best = nil, -1
  for stat, g in pairs(E.gains) do if g > best then main, best = stat, g end end
  -- dur is set when the last rep starts (reps are quicker while the coach pushes him)
  return activity("exercise", name, E.label, math.huge,
    { lead = 2.0, repTime = E.repTime, contact = 0.5, reps = 0, started = 0, repsTarget = n, gains = E.gains,
      nextStart = 2.0,
      main = main, unit = E.unit, energyUse = energyUse or "gym", onPlan = true })
end

local function habit(s, name, def)
  def = def or T.habits[name] or T.free[name]
  local a = activity("habit", name, def.label, range(s.rng, def.dur), { energyUse = def.nap and "nap" or "rest" })
  if name == "chat" or name == "deskchat" then a.talkEvery, a.nextTalk = 2.6, 0.8 end
  return a
end

-- One room on the way to `dest` (through the door to the next room). A walk that carries on
-- from the last one starts at the door already, so it is shorter and he changes room sooner.
-- switchAt: activity time he passes the door (s.location changes).
local function walkToward(s, dest)
  local last = s.activity
  local on = last and last.kind == "walk" and last.to == s.location
  local to = Training.nextRoom(s.location, dest)
  local dur = on and T.walkOn or T.walk
  local switchAt = on and dur * 0.25 or dur / 2
  -- only passing through the next room: walk on across it to its far door
  if to ~= dest then dur = switchAt + T.walkAcross end
  return activity("walk", dest, "Walking to the " .. dest, dur,
    { to = to, from = s.location, final = dest, switchAt = switchAt, energyUse = "rest" })
end

-- Weighted random pick from { { w, make } }.
local function choose(s, pool)
  local total = 0
  for _, p in ipairs(pool) do total = total + p[1] end
  local r = s.rng() * total
  for _, p in ipairs(pool) do
    r = r - p[1]
    if r <= 0 then return p[2]() end
  end
  return pool[#pool][2]()
end

-- Habits in name order so the same seed always gives the same day (pairs order is not fixed).
local function orderedHabits(defs)
  local keys = {}
  for k in pairs(defs) do keys[#keys + 1] = k end
  table.sort(keys)
  local list = {}
  for _, k in ipairs(keys) do list[#list + 1] = { name = k, def = defs[k] } end
  return list
end
local HABITS, FREE, WARMUP = orderedHabits(T.habits), orderedHabits(T.free), orderedHabits(T.warmup)

local function addHabits(s, pool, list, scale)
  for _, h in ipairs(list) do
    local def = h.def
    if def.w > 0 and (not def.loc or def.loc == s.location) then
      local w = def.w * (scale or 1)
      if def.rest then w = w * (1 + T.tiredBreak * (1 - s.energy)) end
      if s.lastHabit == h.name then w = w * T.repeatHabit end
      pool[#pool + 1] = { w, function() return habit(s, h.name, def) end }
    end
  end
end

local function nextActivity(s)
  local last = s.activity
  if s.forced then
    local name = s.forced
    s.forced = nil
    return habit(s, name)
  end
  if s.wantSulk then s.wantSulk = false; return habit(s, "sulk") end
  if s.wantCelebrate then s.wantCelebrate = false; return habit(s, "celebrate") end

  local b = Training.block(s)
  if not b then
    -- day over: out through the room he arrived in
    if s.arriveAt and s.location ~= s.arriveAt then return walkToward(s, s.arriveAt) end
    return activity("home", "home", "Heading home", 5, { energyUse = "rest" })
  end
  -- napping through the end of lunch
  if last and last.name == "nap" and b.kind ~= "free" and not last.overslept and s.rng() < T.oversleep.chance then
    local a = habit(s, "nap")
    a.dur, a.label, a.overslept = range(s.rng, T.oversleep.extra), "Overslept!", true
    Training.say(s, "overslept")
    return a
  end
  if b.loc and b.loc ~= s.location then
    s.music = false
    return walkToward(s, b.loc)
  end

  local pool = {}
  local afterBreak = last and last.kind == "habit"
  local work = T.workWeight * (0.5 + s.energy) * (afterBreak and 2 or 1)
  if b.kind == "drill" then
    local shots = {}
    for _, f in ipairs(b.focus) do if f ~= s.lastShot or #b.focus == 1 then shots[#shots + 1] = f end end
    pool[#pool + 1] = { work, function() return drillSet(s, pick(s.rng, shots)) end }
    addHabits(s, pool, HABITS)
  elseif b.kind == "gym" then
    for _, f in ipairs(b.focus) do
      pool[#pool + 1] = { work / #b.focus, function() return exerciseSet(s, f) end }
    end
    addHabits(s, pool, HABITS)
  elseif b.kind == "warmup" then
    pool[#pool + 1] = { work, function() return exerciseSet(s, "jog", "warmup") end }
    addHabits(s, pool, WARMUP, 0.5)
  elseif b.kind == "cooldown" then
    pool[#pool + 1] = { 4, function() local a = habit(s, "stretch"); a.onPlan = true; return a end }
    for _, n in ipairs({ "juggle", "chat", "water" }) do
      pool[#pool + 1] = { 1, function() return habit(s, n) end }
    end
  elseif b.kind == "free" then
    addHabits(s, pool, FREE)
  elseif b.kind == "idle" then
    -- free time: whatever this room offers, or off through a door
    addHabits(s, pool, HABITS)
    local near = Training.neighbours(s.location)
    for _, r in ipairs(near) do
      pool[#pool + 1] = { T.wander / #near, function() return walkToward(s, r) end }
    end
  end
  return choose(s, pool)
end

local function start(s, a)
  s.activity = a
  a.block = Training.block(s)
  if a.kind == "habit" then s.lastHabit = a.name end
  if a.kind == "drill" then s.lastShot = a.name end
  if a.name == "music" then s.music = true end
  if a.kind == "drill" or a.kind == "exercise" then
    if s.energy < 0.35 and s.rng() < 0.4 then Training.say(s, "tired")
    elseif s.rng() < 0.25 then Training.say(s, "start") end
  elseif T.lines[a.name] and a.name ~= "chat" and s.rng() < 0.7 then
    Training.say(s, a.name)
  end
  if a.kind == "drill" or a.kind == "exercise" then
    log(s, string.format("%s (%d reps)", a.label, a.repsTarget))
  else
    log(s, a.label)
  end
end

-- New day: back at the first block, a few minutes early or late.
local function newDay(s)
  s.day = s.day + 1
  s.energy = 1
  local first = (s.schedule or SCHEDULE)[1]
  s.location = s.arriveAt or first.loc or T.rooms[1]
  s.clock = first.start + range(s.rng, T.lateMorning)
  s.music = false
  local a = activity("arrive", s.location, "Arriving", 4, { energyUse = "rest" })
  start(s, a)
  if s.clock > first.start + 3 then Training.say(s, "late") end
end

local function finish(s, a)
  if a.kind == "home" then
    newDay(s)
    return
  end
  if a.kind == "drill" or a.kind == "exercise" then s.setsDone = s.setsDone + 1 end
  start(s, nextActivity(s))
end

---------------------------------------------------------------------------- update
local function advance(s, a, dt)
  a.t = a.t + dt
  -- the schedule clock runs at real pace: his own time runs s.pace times faster (coach clicks)
  if a.kind ~= "home" then s.clock = s.clock + dt / (s.pace or 1) * T.minutesPerSecond end
  local E = T.energy
  local use = a.energyUse
  if use == "rest" then s.energy = math.min(1, s.energy + E.rest * dt)
  elseif use == "nap" then s.energy = math.min(1, s.energy + E.nap * dt)
  elseif use and E[use] and a.t > (a.lead or 0) then
    local drain = E[use]
    s.energy = math.max(0, s.energy - drain * dt)
  end

  if a.kind == "walk" and not a.switched and a.t >= (a.switchAt or a.dur / 2) then
    a.switched = true
    s.location = a.to
  end
  if a.talkEvery and a.t >= a.nextTalk then
    a.nextTalk = a.nextTalk + a.talkEvery
    a.talkWho = a.talkWho == "player" and "feeder" or "player"
    local desk = a.name == "deskchat"
    Training.say(s, a.talkWho == "player" and (desk and "deskchat" or "chat") or (desk and "desk" or "feeder"), a.talkWho)
  end
  -- the block ended mid-set: finish the rep in progress and stop there
  if a.nextStart and not a.cut and Training.block(s) ~= a.block then
    a.cut = true
    a.repsTarget = math.max(a.started, a.reps)
    a.dur = math.max(a.t, a.cur and a.cur.endT or a.t)
  end
  if a.nextStart then
    while true do
      if a.started == a.reps and a.started < a.repsTarget and a.t >= a.nextStart then
        startRep(s, a, a.nextStart)
      elseif a.reps < a.started and a.t >= a.cur.contactT then
        finishRep(s, a)
      else
        break
      end
    end
  end
end

function Training.update(s, dt)
  if s.bubble then s.bubble.t = s.bubble.t - dt; if s.bubble.t <= 0 then s.bubble = nil end end
  if s.feederBubble then s.feederBubble.t = s.feederBubble.t - dt; if s.feederBubble.t <= 0 then s.feederBubble = nil end end
  if s.coachLine then s.coachLine.t = s.coachLine.t - dt; if s.coachLine.t <= 0 then s.coachLine = nil end end
  -- coach clicks: his pace for this update, then the hype fades (real time)
  s.pace = Training.speed(s)
  s.hype = s.hype * 0.5 ^ (dt / T.coach.halfLife)
  dt = dt * s.pace
  local guard = 0
  while dt > 1e-9 and guard < 1000 do
    guard = guard + 1
    local a = s.activity
    local step = math.min(dt, math.max(0, a.dur - a.t))
    advance(s, a, step)
    dt = dt - step
    if a.t >= a.dur - 1e-9 then finish(s, a) end
  end
end

-- Skip to a time of day (demo / dev): he is already in that block's room and starts on
-- what he would do there. Skills and the day are kept.
function Training.jumpTo(s, clock)
  s.clock = clock
  local b = Training.block(s)
  if b and b.loc then s.location = b.loc end
  s.forced, s.wantSulk, s.wantCelebrate, s.bubble, s.feederBubble = nil, false, false, nil, nil
  s.activity = nil
  start(s, nextActivity(s))
end

-- opts: rng, clock (jump there), schedule (from Training.buildSchedule; default: the demo's
-- T.schedule), start (stat -> starting level; default T.start), statsHook (see Training.stats),
-- arriveAt (room he comes in through every morning and leaves by; default the first block's).
-- Blocks of kind "idle" (no loc) are free time: he stays where he is and does his own thing.
function Training.new(opts)
  opts = opts or {}
  local s = { rng = opts.rng or math.random, day = 0, events = {}, log = {}, skills = {},
              energy = 1, missStreak = 0, perfectStreak = 0, setsDone = 0, totalReps = 0, hype = 0, pace = 1,
              music = false, schedule = opts.schedule or SCHEDULE, statsHook = opts.statsHook,
              arriveAt = opts.arriveAt }
  for name, level in pairs(opts.start or T.start) do s.skills[name] = { level = level, progress = 0 } end
  newDay(s)
  if opts.clock then Training.jumpTo(s, opts.clock) end
  return s
end

return Training
