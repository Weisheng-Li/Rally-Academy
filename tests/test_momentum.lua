-- Movement (run + reach with acceleration) and momentum rules (core only).
local Athlete = require("src.core.athlete")
local Shots = require("src.core.shots")
local M = require("src.data.momentum")

local function athlete(level, legs)
  local s = {}
  for _, k in ipairs({ "clear", "lift", "drop", "net", "drive", "smash", "power", "speed",
                       "legs", "reach" }) do s[k] = level end
  if legs then s.legs = legs end
  return Athlete.new({ name = "T", stats = s }, 1)
end

-- near player hitting from the back right; cross target = far back right (screen -x side)
local function ctx(a, contact, mom)
  return { stats = a.stats, from = { x = 1.8, y = 5.6 }, h0 = 2.0, contact = contact,
           momentum = mom or 0, maxSpeed = a:maxLaunchSpeed() }
end
local STRAIGHT = { x = 1.85, y = -5.8 }
local CROSS = { x = -1.85, y = -5.8 }
local ONTIME = { state = "ontime", stretch = 0 }
local LATE = { state = "stretched", stretch = 0.6 }

return {
  ["from rest: accelerate, then top speed"] = function(t)
    local a = athlete(1)                       -- Speed Lv1: no split-step push-off
    t:near(a:firstStep(), 0, 1e-12, "beginners start from a standstill")
    local v = a:speed()
    local tAcc = v / M.accel
    t:near(a:distanceIn(1, 0, tAcc), v * tAcc / 2, 1e-9, "distance while accelerating")
    t:near(a:distanceIn(1, 0, tAcc + 1), v * tAcc / 2 + v, 1e-9, "then top speed")
  end,

  ["split step: better players start each move already moving"] = function(t)
    local a = athlete(8)
    local v0, v = a:firstStep(), a:speed()
    t:ok(v0 > 0.5, "push-off speed")
    local tAcc = (v - v0) / M.accel
    t:near(a:distanceIn(1, 0, tAcc), v0 * tAcc + 0.5 * M.accel * tAcc * tAcc, 1e-9, "starts at the push-off speed")
  end,

  ["time to cover is the inverse of distance covered"] = function(t)
    local a = athlete(5)
    for _, m in ipairs({ { 0, 0 }, { 1.2, 0 }, { -1.5, 0 }, { 0, 1 } }) do
      a.momentum = { x = m[1], y = m[2] }
      for _, d in ipairs({ 0.3, 1.0, 2.5, 4.0 }) do
        local tt = a:timeToCover(1, 0, d)
        t:near(a:distanceIn(1, 0, tt), d, 1e-6, string.format("m=(%g,%g) d=%g", m[1], m[2], d))
      end
    end
  end,

  ["momentum: along helps, sideways neutral, against hurts"] = function(t)
    local a = athlete(5)
    local rest = a:distanceIn(1, 0, 1.0)
    a.momentum = { x = 1.5, y = 0 }
    t:ok(a:distanceIn(1, 0, 1.0) > rest, "along should cover more")
    t:near(a:distanceIn(0, 1, 1.0), rest, 1e-9, "sideways = from rest")
    t:ok(a:distanceIn(-1, 0, 1.0) < rest, "against should cover less")
  end,

  ["carried the wrong way: no progress until stopped"] = function(t)
    local a = athlete(5)
    a.momentum = { x = 1.8, y = 0 }
    local tStop = 1.8 / M.accel
    t:near(a:distanceIn(-1, 0, tStop), 0, 1e-9, "still braking")
    t:ok(a:distanceIn(-1, 0, tStop + 0.5) > 0, "moving after stopping")
  end,

  ["animated sprite moves with the same kinematics as the timing model"] = function(t)
    for _, m in ipairs({ { 0, 0 }, { 1.2, 0 }, { -1.2, 0 } }) do
      local a = athlete(5)
      a.momentum = { x = m[1], y = m[2] }
      local expected = a:distanceIn(1, 0, 0.6)
      local probe = athlete(5)
      probe.pos = { x = 0, y = 0 }
      probe.momentum = { x = m[1], y = m[2] }
      probe.fadeRate = function() return 0 end   -- compare against the no-fade timing formula
      probe:moveTo({ x = 10, y = 0 }, 0)
      for _ = 1, 60 do probe:update(0.01) end
      t:near(probe.pos.x, expected, 0.02, string.format("momentum %g", m[1]))
    end
  end,

  ["after a full stretch the recovery pause is much longer"] = function(t)
    local a = athlete(5)
    t:near(a:swingPause() + 1 * a:stretchPause() - a:swingPause(), M.stretchPause, 1e-9, "stretch pause")
    t:ok(M.stretchPause >= 2 * M.swingPause, "a full stretch should cost far more than a normal swing")
  end,

  ["recovery area is a circle: balance is back after the pause, momentum doesn't skew it"] = function(t)
    local a = athlete(5)
    a.momentum = { x = 1.4, y = 0 }
    local along = a:recoveryRadius(1, 0, 1.5, 0.25)
    local side = a:recoveryRadius(0, 1, 1.5, 0.25)
    local against = a:recoveryRadius(-1, 0, 1.5, 0.25)
    t:near(along, side, 1e-12, "along = sideways")
    t:near(against, side, 1e-12, "against = sideways")
    t:ok(a:recoveryRadius(1, 0, 1.5, 0.8) < along, "a longer pause (deep lunge) still shrinks it")
  end,

  ["a ball behind you is reached later"] = function(t)
    local a = athlete(5)
    a.pos = { x = 0, y = 3 }
    local calm = a:arrival({ x = 0, y = 5 }, 1.5, 0.3)
    a.momentum = { x = 0, y = -1.5 }                      -- carried toward the net
    local carried = a:arrival({ x = 0, y = 5 }, 1.5, 0.3)  -- ball behind
    t:ok(carried.slack < calm.slack, "less spare time when carried away from it")
  end,

  ["stronger legs keep less momentum and regain balance faster"] = function(t)
    local weak, strong = athlete(5, 2), athlete(5, 8)
    local mw = weak:momentumFromRun(0, -1, 3, 4, 0, 0)
    local ms = strong:momentumFromRun(0, -1, 3, 4, 0, 0)
    t:ok(math.abs(ms.y) < math.abs(mw.y), "strong legs should keep less")
    t:ok(strong:fadeRate() > weak:fadeRate(), "strong legs should fade it faster")
    t:near(weak:fadeRate(), 1.0, 0.01, "Lv2 fades ~1.0 m/s per s")
  end,

  ["momentum lingers long enough to be read"] = function(t)
    local a = athlete(5)
    a.momentum = { x = 0, y = -1.6 }
    a:update(0.5)
    t:ok(a:momentumSize() > M.yellow, "a hard lunge should still show after 0.5 s")
    a:update(1.0)
    t:near(a:momentumSize(), 0, 1e-9, "and be gone after ~1.1 s at Legs Lv5")
  end,

  ["momentum points along the run, grows with a lunge, fades with spare time"] = function(t)
    local a = athlete(5)
    local m = a:momentumFromRun(0, -2, 2, 4, 0, 0)
    t:ok(m.y < 0 and math.abs(m.x) < 1e-9, "should point along the run (-y)")
    local lunge = a:momentumFromRun(0, -2, 2, 4, 1, 0)
    t:near(lunge.y / m.y, 1 + M.lungeBoost, 1e-9, "full lunge multiplier")
    local settled = a:momentumFromRun(0, -2, 2, 4, 0, 5)
    t:near(settled.y, 0, 1e-9, "plenty of spare time settles it")
  end,

  ["arrow levels: low, yellow, red"] = function(t)
    local a = athlete(5)
    a.momentum = { x = M.yellow - 0.01, y = 0 }; t:ok(a:momentumLevel() == "low", "low")
    a.momentum = { x = M.yellow, y = 0 };        t:ok(a:momentumLevel() == "yellow", "yellow")
    a.momentum = { x = 0, y = M.red };           t:ok(a:momentumLevel() == "red", "red")
  end,

  ["momentum adds wobble per m/s"] = function(t)
    local a = athlete(5)
    local calm = Shots.evaluate(ctx(a, ONTIME, 0), STRAIGHT, "clear")
    local moving = Shots.evaluate(ctx(a, ONTIME, 1.0), STRAIGHT, "clear")
    t:near(moving.wobbleMul / calm.wobbleMul, 1 + M.wobblePerMS * 1.0, 1e-9, "wobble multiplier")
  end,

  ["late or red momentum: cross shots cost far more with a weak technique, no smash at all"] = function(t)
    local Curve = require("src.core.curve")
    local TQ = Shots.data.technique
    for _, lv in ipairs({ 2, 5, 9 }) do
      local a = athlete(lv)
      local late = Shots.evaluate(ctx(a, LATE, 0), CROSS, "clear")
      local straight = Shots.evaluate(ctx(a, LATE, 0), STRAIGHT, "clear")
      t:near(late.wobbleMul / straight.wobbleMul, Curve.at(TQ.cross, lv) * Curve.at(TQ.lateCross, lv), 1e-9,
        "late cross wobble Lv" .. lv)
      local redCross = Shots.evaluate(ctx(a, ONTIME, M.red), CROSS, "clear")
      local calmCross = Shots.evaluate(ctx(a, ONTIME, M.red - 0.01), CROSS, "clear")
      t:ok(redCross.wobbleMul > calmCross.wobbleMul * Curve.at(TQ.lateCross, lv) * 0.99, "red counts as late Lv" .. lv)
      t:ok(not Shots.evaluate(ctx(a, LATE, 0), STRAIGHT, "smash").available, "no smash when late Lv" .. lv)
    end
    local weak = Shots.evaluate(ctx(athlete(2), LATE, 0), CROSS, "clear")
    local strong = Shots.evaluate(ctx(athlete(9), LATE, 0), CROSS, "clear")
    t:ok(weak.success < 0.2, string.format("weak late cross clear nearly hopeless (%.0f%%)", weak.success * 100))
    t:ok(strong.success > 0.6, string.format("strong late cross clear playable (%.0f%%)", strong.success * 100))
  end,

  ["being late hurts less with a good technique"] = function(t)
    local lo = Shots.timingMul(LATE, 2)
    local hi = Shots.timingMul(LATE, 9)
    t:ok(lo > hi and hi > 1, "late penalty shrinks with technique")
    t:near(Shots.timingMul(ONTIME, 2), 1, 1e-12, "on time: no penalty")
  end,

  ["beginners have no overhead: low contact ceiling, so no smash"] = function(t)
    local beg = athlete(1)
    local h = Shots.contactHeight("back", ONTIME, beg.stats)
    t:ok(h < Shots.data.types.smash.minContact, "beginner contact below the smash minimum")
    t:near(Shots.contactHeight("back", ONTIME, athlete(6).stats), Shots.data.contactHeight.back.ontime, 1e-12,
      "good players hit at the normal height")
  end,

  ["weak technique floats net shots higher over the tape"] = function(t)
    local from = { x = 0, y = 1.5 }
    local function netH(lv)
      local a = athlete(lv)
      local c = { stats = a.stats, from = from, h0 = 0.6, contact = ONTIME, momentum = 0, maxSpeed = a:maxLaunchSpeed() }
      return Shots.evaluate(c, { x = 1.85, y = -1.5 }, "net").overNet
    end
    t:ok(netH(1) > netH(5) + 0.1 and netH(5) > netH(10), "higher clearance at low technique")
  end,

  ["reaction: the receiver waits before moving"] = function(t)
    local slow, fast = athlete(1), athlete(9)
    slow.stats.reaction, fast.stats.reaction = 1, 9
    local p = { x = 1.5, y = 3.6 }
    t:near(slow:arrival(p, 1.0, 0.3).delay, slow:reaction(), 1e-12, "delay = reaction")
    t:ok(slow:reaction() > fast:reaction() + 0.2, "slow reaction waits longer")
  end,
}
