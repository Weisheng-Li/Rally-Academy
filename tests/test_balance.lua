-- Off-balance and late-shot rules (core only).
local Athlete = require("src.core.athlete")
local Shots = require("src.core.shots")
local Bal = require("src.data.balance")

local function athlete(level)
  local s = {}
  for _, k in ipairs({ "clear", "lift", "drop", "net", "drive", "smash", "power", "speed",
                       "reaction", "reach", "balance" }) do s[k] = level end
  return Athlete.new({ name = "T", stats = s }, 1)
end

-- near player hitting from the back right; cross target = far back right (screen -x side)
local function ctx(a, contact, ob)
  return { stats = a.stats, from = { x = 1.8, y = 5.6 }, h0 = 2.0, contact = contact,
           offBalance = ob or 0, maxSpeed = a:maxLaunchSpeed() }
end
local STRAIGHT = { x = 1.85, y = -5.8 }
local CROSS = { x = -1.85, y = -5.8 }
local ONTIME = { state = "ontime", stretch = 0 }
local LATE = { state = "stretched", stretch = 0.6 }

return {
  ["off balance slows reaction and running"] = function(t)
    local a = athlete(5)
    local r0, v0 = a:reaction(), a:speed()
    a.offBalance = 1
    t:near(a:reaction() - r0, Bal.reactionAdd, 1e-9, "reaction added")
    t:near(a:speed() / v0, 1 - Bal.speedLoss, 1e-9, "speed fraction")
  end,

  ["off balance recovers over time, faster with Balance stat"] = function(t)
    local slow, fast = athlete(2), athlete(8)
    slow.offBalance, fast.offBalance = 1, 1
    slow:update(1); fast:update(1)
    t:ok(fast.offBalance < slow.offBalance, "higher Balance should recover faster")
    t:near(1 - slow.offBalance, Bal.recoverBase + 2 * Bal.recoverPerLevel, 1e-9, "recovery per second")
  end,

  ["late cross shot is disabled below the technique threshold"] = function(t)
    local a = athlete(Bal.crossMinTechnique - 1)
    local ev = Shots.evaluate(ctx(a, LATE), CROSS, "clear")
    t:ok(not ev.available, "cross clear should be unavailable when late")
    local st = Shots.evaluate(ctx(a, LATE), STRAIGHT, "clear")
    t:ok(st.available, "straight clear should still be available")
  end,

  ["late cross shot is allowed with high technique but shakier"] = function(t)
    local a = athlete(Bal.crossMinTechnique)
    local late = Shots.evaluate(ctx(a, LATE), CROSS, "clear")
    t:ok(late.available, "cross clear should be available at the threshold")
    local straight = Shots.evaluate(ctx(a, LATE), STRAIGHT, "clear")
    t:near(late.wobbleMul / straight.wobbleMul, Bal.lateCrossWobble, 1e-9, "late cross wobble")
  end,

  ["badly off balance counts as late even with on-time contact"] = function(t)
    local a = athlete(5)
    local ev = Shots.evaluate(ctx(a, ONTIME, Bal.restrictAt), CROSS, "clear")
    t:ok(not ev.available, "cross should be limited when off balance")
    local ok = Shots.evaluate(ctx(a, ONTIME, Bal.restrictAt - 0.01), CROSS, "clear")
    t:ok(ok.available, "just below the limit it is allowed")
  end,

  ["off balance adds wobble"] = function(t)
    local a = athlete(5)
    local calm = Shots.evaluate(ctx(a, ONTIME, 0), STRAIGHT, "clear")
    local shaky = Shots.evaluate(ctx(a, ONTIME, 0.5), STRAIGHT, "clear")
    t:near(shaky.wobbleMul / calm.wobbleMul, 1 + Bal.wobbleAdd * 0.5, 1e-9, "wobble multiplier")
  end,
}
