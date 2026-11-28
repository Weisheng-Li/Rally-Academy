-- Shots that come down before reaching the net: only short drops inside the court are "net";
-- wild mishits off to the side (common at low levels) are out (src/core/shot_model.lua
-- SM.shortOfNet, used by Shots.execute and the success estimate).
local SM = require("src.core.shot_model")
local Shots = require("src.core.shots")

-- rng returning a fixed sequence (to steer Shots.execute's normal() draws)
local function seq(list)
  local i = 0
  return function() i = i + 1; return list[(i - 1) % #list + 1] end
end

return {
  ["short of the net: inside the court is net, off the side or away from the net is out"] = function(t)
    t:ok(SM.shortOfNet(0, 0.1, 5, 3) == "net", "drops short in the court")
    t:ok(SM.shortOfNet(0, 0.9, 20, 8) == "wide", "veers past the sideline")
    t:ok(SM.shortOfNet(0, 0.5, -4, 3) == "wide", "heads away from the net")
    t:ok(SM.shortOfNet(0, 1, math.huge, 3) == "wide", "flies parallel to the net")
  end,

  ["a mishit that veers sideways is called out, not net"] = function(t)
    -- normal() draws: angle 0, speed 0, direction +1 sd (= 80 degrees off the aim)
    local rng = seq({ 0.5, 0.25, 0.5, 0.25, math.exp(-0.5), 0 })
    local ctx = { from = { x = 0, y = 3 }, h0 = 1.2 }
    local ev = { solution = { angle = math.rad(30), speed = 18 }, dir = { x = 0, y = -1 },
                 wobble = { angle = math.rad(2), speed = 0.05, dir = math.rad(80) },
                 classify = function() return "in" end }
    local res = Shots.execute(ctx, ev, rng)
    t:ok(res.outcome == "wide", "outcome " .. tostring(res.outcome))
    t:ok(res.ownSide, "landed on the hitter's side")
    t:ok(res.landing.y > 0, "landing on the near half")
  end,

  ["a shot into the tape is still net"] = function(t)
    local rng = seq({ 0.5, 0.25, 0.5, 0.25, 0.5, 0.25 })   -- no wobble at all
    local ctx = { from = { x = 0, y = 3 }, h0 = 1.0 }
    local ev = { solution = { angle = math.rad(-2), speed = 25 }, dir = { x = 0, y = -1 },
                 wobble = { angle = 0, speed = 0, dir = 0 }, classify = function() return "in" end }
    local res = Shots.execute(ctx, ev, rng)
    t:ok(res.outcome == "net" and not res.ownSide, "tape hit: " .. tostring(res.outcome))
  end,

  ["a wildly shaky hand can't launch a shot at hundreds of m/s (speed shake is capped)"] = function(t)
    local Data = require("src.data.shots")
    local w = { angle = 0, dir = 0, speed = 3, speedRange = Data.speedRange }
    t:ok(SM.speedFactor(8, w) == Data.speedRange[2] and SM.speedFactor(-8, w) == Data.speedRange[1], "clamped")
    -- the draw that used to give ~800 m/s and crash the flight: now it flies and lands
    local rng = seq({ 0.5, 0.25, 1e-9, 0, 0.5, 0.25 })
    local ev = { solution = { angle = math.rad(-20), speed = 30 }, dir = { x = 0, y = -1 },
                 wobble = w, classify = function() return "in" end }
    local res = Shots.execute({ from = { x = 0, y = 3 }, h0 = 1.7 }, ev, rng)
    t:ok(res.path and #res.path > 0 and res.outcome, "flew: " .. tostring(res.outcome))
  end,
}
