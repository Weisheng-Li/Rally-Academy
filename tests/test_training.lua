-- Training sim (src/core/training.lua) and the training demo's extra sprite geometry.
local Training = require("src.core.training")
local Body = require("src.core.body")
local Layout = require("src.config.layout")
local Camera = require("src.view.camera")
local Figure = require("src.view.figure")

local function lcg(seed)
  local x = seed
  return function()
    x = (x * 1103515245 + 12345) % 2147483648
    return x / 2147483648
  end
end

-- Run the sim for `seconds` in small steps; collect events and what happened.
local function run(seed, seconds, onStep)
  local s = Training.new({ rng = lcg(seed) })
  local events, kinds, habits = {}, {}, {}
  local dt = 0.05
  for _ = 1, math.floor(seconds / dt) do
    Training.update(s, dt)
    for _, e in ipairs(s.events) do events[#events + 1] = e end
    s.events = {}
    local a = s.activity
    kinds[a.kind] = true
    if a.kind == "habit" then habits[a.name] = true end
    if onStep then onStep(s) end
  end
  return s, events, kinds, habits
end

local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

return {
  ["core training never touches love"] = function(t)
    for _, path in ipairs({ "src/core/training.lua", "src/data/training.lua" }) do
      local f = assert(io.open(path, "r"))
      local src = f:read("*a")
      f:close()
      t:ok(not src:find("love%.%a"), path .. " calls love.*")
    end
  end,

  ["each level needs more reps than the last"] = function(t)
    for level = 1, 15 do
      t:ok(Training.repsFor(level + 1) > Training.repsFor(level), "level " .. level)
    end
  end,

  ["a day: he follows the schedule's rooms and does both drills and gym work"] = function(t)
    local wrongRoom, checks = 0, 0
    local s, events, kinds, habits = run(7, 1040, function(s)
      local b = Training.block(s)
      local a = s.activity
      if b and (a.kind == "drill" or a.kind == "exercise") then
        checks = checks + 1
        if s.location ~= b.loc then wrongRoom = wrongRoom + 1 end
        if a.kind == "drill" then t:ok(s.location == "court", "drills happen on court") end
      end
    end)
    t:ok(kinds.drill and kinds.exercise and kinds.walk, "drill, gym and walking between them")
    t:ok(count(habits) >= 4, "does a few different things of his own, got " .. count(habits))
    t:ok(checks > 0 and wrongRoom / checks < 0.05, "works in the room the plan says")
    local reps = 0
    for _, e in ipairs(events) do if e.type == "rep" then reps = reps + 1 end end
    t:ok(reps > 150, "plenty of reps in a day, got " .. reps)
  end,

  ["every rep moves its stat forward"] = function(t)
    local s = Training.new({ rng = lcg(3) })
    local last = {}
    local function total(name) local sk = s.skills[name] return sk.level * 1000 + sk.progress end
    for name in pairs(s.skills) do last[name] = total(name) end
    local reps = 0
    for _ = 1, 4000 do
      Training.update(s, 0.05)
      for _, e in ipairs(s.events) do
        if e.type == "rep" then
          reps = reps + 1
          t:ok(total(e.skill) > last[e.skill], "rep of " .. e.skill .. " added nothing")
        end
      end
      s.events = {}
      for name in pairs(s.skills) do
        t:ok(total(name) >= last[name], name .. " went backwards")
        last[name] = total(name)
      end
    end
    t:ok(reps > 0, "some reps happened")
  end,

  ["levels go up with training"] = function(t)
    local s = run(11, 1040)
    local up = 0
    for name, level in pairs(Training.data.start) do up = up + (s.skills[name].level - level) end
    t:ok(up >= 3, "a day of training gives a few levels, got " .. up)
  end,

  ["same seed, same day"] = function(t)
    local a = run(42, 300)
    local b = run(42, 300)
    t:near(#a.log, #b.log, 0, "log length")
    for i = 1, #a.log do t:ok(a.log[i].text == b.log[i].text, "log line " .. i) end
  end,

  ["the day ends and the next one starts at the first block"] = function(t)
    local s = run(5, 1200)
    t:ok(s.day >= 2, "reached day 2")
    t:ok(s.clock < Training.schedule[#Training.schedule].stop, "clock went back to the morning")
  end,

  ["drill reps fly the match physics: only shots over the tape count as in"] = function(t)
    local Court = require("src.core.court")
    local s = Training.new({ rng = lcg(9) })
    local rng = lcg(21)
    local outcomes = {}
    for name in pairs(Training.data.shots) do
      for _ = 1, 40 do
        local r = Training.drillRep(s, name, rng)
        outcomes[r.outcome] = true
        -- feed: from the feeder, over the net, ends at the contact on his half
        local f1, fn = r.feed[1], r.feed[#r.feed]
        t:ok(f1.y < 0 and fn.y > 0, name .. ": feed crosses to his half")
        t:near(fn.h, r.h, 1e-6, name .. ": contact at the path's end")
        -- return: where the path crosses the net plane decides it
        local crossH
        for i = 2, #r.ret do
          local a, b = r.ret[i - 1], r.ret[i]
          if a.y > 0 and b.y <= 0 then crossH = a.h + (b.h - a.h) * a.y / (a.y - b.y) end
        end
        if r.outcome == "net" then
          t:ok(not crossH or crossH < Court.NET_HEIGHT + 0.01, name .. ": net outcome but flew over the tape")
          t:ok(r.quality == "miss", name .. ": net is a miss")
        else
          t:ok(crossH and crossH >= Court.NET_HEIGHT - 1e-6, name .. ": over the tape")
          t:ok(r.ret[#r.ret].y < 0, name .. ": lands on the far half")
        end
        if r.outcome == "in" then t:ok(r.quality ~= "miss", name .. ": in is not a miss") end
      end
    end
    t:ok(outcomes["in"] and outcomes["net"], "both makes and net misses happen")
  end,

  ["he walks around the courtside bench, never through it"] = function(t)
    local View = require("src.view.training_view")
    local CS, BL = Layout.training.court, Layout.training.courtBench
    local B = CS.bench
    for seed = 1, 3 do
      local s = Training.new({ rng = lcg(seed) })
      local v = View.new(Camera.new(Layout.training.camera))
      for _ = 1, 400 / 0.05 do
        Training.update(s, 0.05)
        v:update(s, 0.05)
        s.events = {}
        if s.location == "court" then
          local p = v.pos
          t:ok(not (math.abs(p.x - B.x) < BL.hx + 0.15 and math.abs(p.y - B.y) < BL.hy + 0.15),
            string.format("seed %d: standing in the bench at (%.2f, %.2f)", seed, p.x, p.y))
        end
      end
    end
  end,

  ["coach clicks: every click speeds him up, less and less, toward max"] = function(t)
    local C = Training.data.coach
    local s = Training.new({ rng = lcg(4) })
    t:near(Training.speed(s), 1, 1e-12, "no clicks, normal pace")
    local last, gains = 1, {}
    for i = 1, 30 do
      Training.coach(s)
      t:ok(s.coachLine ~= nil, "the coach says something every click")
      local sp = Training.speed(s)
      gains[i] = sp - last
      t:ok(gains[i] > 0, "every click helps a bit")
      if i > 1 then t:ok(gains[i] < gains[i - 1], "each click helps less than the one before") end
      last = sp
    end
    local s10 = Training.new({ rng = lcg(4) })
    for _ = 1, 10 do Training.coach(s10) end
    t:ok(Training.speed(s10) > 1.85 and Training.speed(s10) < 2.0, "10 clicks: close to 2x")
    t:ok(Training.speed(s) < C.max, "never past max")
    t:ok(Training.speed(s) - Training.speed(s10) < 0.3, "20 more clicks add little")
  end,

  ["coach hype fades over time"] = function(t)
    local C = Training.data.coach
    local s = Training.new({ rng = lcg(4) })
    for _ = 1, 10 do Training.coach(s) end
    local h = s.hype
    Training.update(s, C.halfLife)
    t:near(s.hype, h / 2, 1e-6, "halves every halfLife s")
    Training.update(s, 60)
    t:ok(Training.speed(s) < 1.01, "back to normal after a while")
  end,

  ["cheering packs more reps into the same schedule time"] = function(t)
    local function reps(click)
      local s = Training.new({ rng = lcg(12), clock = Training.minutes("09:55") })
      local n, t0 = 0, s.clock
      while s.clock < t0 + 20 do
        if click then Training.coach(s); Training.coach(s) end   -- spamming
        Training.update(s, 0.05)
        for _, e in ipairs(s.events) do if e.type == "rep" then n = n + 1 end end
        s.events = {}
      end
      return n
    end
    local calm, cheered = reps(false), reps(true)
    t:ok(cheered > calm * 1.5, string.format("%d reps cheered vs %d calm", cheered, calm))
  end,

  ["arm sprite is the model's arm length"] = function(t)
    local cam = Camera.new(Layout.training.camera)
    for _, y in ipairs({ 1.0, 3.3, 5.5 }) do
      local f = Figure.stance(cam, { cog = { x = 0, y = y }, dir = { x = 1, y = 0 }, hipH = Body.HIP_HEIGHT,
                                     front = 0.12, back = -0.12, lean = 0 }, 1)
      for _, ang in ipairs({ -1.2, 0, 0.7, 1.5 }) do
        local g = Figure.arm(f, ang)
        local len = math.sqrt((g.handX - g.shoulderX) ^ 2 + (g.handY - g.shoulderY) ^ 2)
        t:near(len, Body.ARM_LENGTH * f.k, 1e-9, "arm length")
        t:near(g.shoulderY, f.shoulderY, 1e-9, "arm hangs from the shoulder")
        t:near(math.abs(g.shoulderX - f.shoulderMidX), f.bodyW / 2, 1e-9, "at the torso edge")
      end
    end
  end,

  ["lying sprite is as long as he is tall"] = function(t)
    local cam = Camera.new(Layout.training.camera)
    for _, y in ipairs({ 1.0, 4.3 }) do
      for _, facing in ipairs({ 1, -1 }) do
        local g = Figure.lying(cam, { x = 0, y = y }, facing)
        local headEnd = g.head.x + facing * g.head.r
        t:near(math.abs(headEnd - g.feetX), Body.HEIGHT * g.k, 1e-9, "feet to top of head")
        t:near(math.abs(g.legs[3] - g.legs[1]), Body.HIP_HEIGHT * g.k, 1e-9, "legs")
        t:near(math.abs(g.torso[3] - g.torso[1]), Body.TORSO_LENGTH * g.k, 1e-9, "torso")
      end
    end
  end,
}
