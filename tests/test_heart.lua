-- Heart rate within a rally (src/core/athlete.lua, data/heart.lua).
local Athlete = require("src.core.athlete")
local Rally = require("src.core.rally")
local Shots = require("src.core.shots")
local H = require("src.data.heart")

local function athlete(stamina)
  local s = {}
  for _, k in ipairs({ "clear", "lift", "drop", "net", "drive", "smash", "power", "speed", "legs", "reach",
                       "reaction", "recovery" }) do s[k] = 6 end
  s.stamina = stamina or 5
  return Athlete.new({ name = "T", stats = s }, 1)
end

local function run(a, seconds, speed)
  for _ = 1, math.floor(seconds * 60) do a:heartStep(1 / 60, speed) end
end

return {
  ["heart: sprinting raises it, jogging much less, standing brings it back to the floor"] = function(t)
    local a = athlete()
    run(a, 1.0, a:baseSpeed())
    local sprint = a.hr - H.start
    t:ok(sprint > 20, string.format("1 s sprint +%.0f bpm", sprint))
    local b = athlete()
    run(b, 1.0, b:baseSpeed() * 0.4)
    t:ok(b.hr - H.start < sprint * 0.3, "jogging costs far less than sprinting")
    run(a, 10, 0)
    t:near(a.hr, a.hrFloor, 1e-9, "standing: back down to the floor")
    t:ok(a.hr <= H.max, "never above max")
  end,

  ["heart: your floor rises with your own exertion; the one who runs tires more"] = function(t)
    local runner, stander = athlete(), athlete()
    for _ = 1, 10 do                               -- 10 s: one sprints half of every second
      run(runner, 0.5, runner:baseSpeed()); run(runner, 0.5, 0)
      run(stander, 1.0, stander:baseSpeed() * 0.3)
    end
    t:ok(runner.hrFloor > stander.hrFloor + 5, string.format("runner floor %.0f vs %.0f", runner.hrFloor, stander.hrFloor))
    local floor = runner.hrFloor
    run(runner, 10, 0)
    t:ok(runner.hr >= floor - 1e-9, "can't rest below your floor mid-rally")
  end,

  ["heart: a hard rally carries over into the next one, then fades"] = function(t)
    local a = athlete()
    for _ = 1, 20 do run(a, 0.5, a:baseSpeed()); run(a, 0.5, 0) end
    a:resetHeart()
    local after = a.hr
    t:ok(after > H.start + 3, string.format("next rally starts higher (%.0f)", after))
    a:resetHeart()                                  -- a quiet rally (no load)
    t:ok(a.hr < after and a.hr > H.start, "the extra fades")
    for _ = 1, 10 do a:resetHeart() end
    t:near(a.hr, H.start, 0.1, "fully recovered after a few quiet points")
    local b = athlete()
    local r = Rally.new({ players = { near = a, far = b }, server = "near", serverScore = 0, human = {} })
    t:near(b.hr, H.start, 1e-12, "a fresh player starts a rally at the start value")
  end,

  ["heart: past the onset you move slower and shake more; below it nothing changes"] = function(t)
    local a = athlete()
    local fresh = a:speed()
    a.hr = H.onset - 1
    t:near(a:speed(), fresh, 1e-12, "below onset: full speed")
    t:near(a:hrWobbleMul(), 1, 1e-12, "below onset: steady")
    a.hr = H.max
    t:near(a:speed(), fresh * (1 - H.slowAtMax), 1e-9, "at max: slower")
    t:near(a:hrWobbleMul(), 1 + H.wobbleAtMax, 1e-9, "at max: shakier")
    -- the slower legs feed the timing model: the same shuttle is reached later, more stretched
    local p = { x = 2.0, y = 2.0 }
    local tired = a:arrival(p, 0.9, 0.3)
    a.hr = H.start
    local rested = a:arrival(p, 0.9, 0.3)
    t:ok((tired.slack or 0) < (rested.slack or 0), "tired: less time to spare")
  end,

  ["heart: a deep lunge costs heart rate, more stamina costs less"] = function(t)
    local lo, hi = athlete(1), athlete(10)
    lo:lungeHeart(1); hi:lungeHeart(1)
    t:ok(lo.hr > hi.hr and hi.hr > H.start, "lunge raises it, less with stamina")
    local a, b = athlete(1), athlete(10)
    run(a, 1, a:baseSpeed()); run(b, 1, b:baseSpeed())
    t:ok(a.hr > b.hr, "low stamina rises faster")
  end,

  ["heart: shot breakdown shows your heart rate when it hurts"] = function(t)
    local a = athlete()
    a.hr = H.max
    local ctx = { stats = a.stats, from = { x = 0, y = 5.8 }, h0 = 2.0, contact = { state = "ontime", stretch = 0 },
                  momentum = 0, maxSpeed = a:maxLaunchSpeed(), hr = a.hr, hrMul = a:hrWobbleMul() }
    local ev = Shots.evaluate(ctx, { x = 1.85, y = -5.8 }, "clear")
    local found = false
    for _, f in ipairs(ev.factors) do if f.label:find("Heart rate") then found = true end end
    t:ok(found, "heart rate factor listed")
  end,
}
