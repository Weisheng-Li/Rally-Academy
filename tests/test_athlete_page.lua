-- Athlete page: practice shots (real shot model) and the reps-a-day estimate behind it
-- (src/core/training.lua Training.practice, src/core/career.lua Career.dailyReps), and that
-- the page's cards fit the screen (src/view/athlete_view.lua).
local Training = require("src.core.training")
local Career = require("src.core.career")
local Layout = require("src.config.layout")

local function lcg(seed)
  local s = seed
  return function() s = (s * 16807) % 2147483647; return s / 2147483647 end
end

local function stats(tech, power)
  local st = { reach = 3, reaction = 3, recovery = 3, power = power or 6, speed = 3, legs = 3, stamina = 3 }
  for _, k in ipairs({ "clear", "lift", "drop", "net", "drive", "smash" }) do st[k] = tech end
  return st
end

return {
  ["practice: a better technique lands more of the same shots"] = function(t)
    local lo = Training.practice(stats(1), "drop", 120, lcg(7))
    local hi = Training.practice(stats(8), "drop", 120, lcg(7))
    t:ok(lo.available and hi.available and #lo.points == 120, "120 shots flown")
    t:ok(hi.inCount > lo.inCount + 30, string.format("Lv8 %d vs Lv1 %d in", hi.inCount, lo.inCount))
    t:ok(lo.from.y > 0 and lo.aim.y < 0, "hit from his half to the far half")
  end,

  ["practice: too weak to reach the back = not playable at all"] = function(t)
    t:ok(not Training.practice(stats(5, 1), "clear", 10, lcg(1)).available, "Power Lv1 can't clear from the back")
    t:ok(Training.practice(stats(5, 6), "clear", 10, lcg(1)).available, "Power Lv6 can")
  end,

  ["reps a day follow the plan"] = function(t)
    local empty = Career.dailyReps(Career.new({ rng = lcg(3) }))
    t:ok(next(empty) == nil, "nothing planned: nothing trained")
    local d = Career.dailyReps(Career.new({ rng = lcg(3), plan = { "net_lift", false, false, false } }))
    t:ok(d.net > 5 and d.lift > 5, "net and lift trained")
    t:ok(not d.clear and not d.power, "clear and power not")
    t:ok((d.legs or 0) > 0, "drill reps add a little legs")
  end,

  ["athlete page rows fit the screen without overlapping, left of the detail pane"] = function(t)
    local AV = require("src.view.athlete_view")
    local rows = AV.new(Career.new({ rng = lcg(4) })):rows()
    t:ok(#rows == 10, "4 body + 6 shot rows")
    for i, a in ipairs(rows) do
      t:ok(a.x >= 0 and a.x + a.w <= Layout.hub.athlete.split.paneX and a.y + a.h <= Layout.height, a.k .. " on screen, left of the pane")
      for j = i + 1, #rows do
        local b = rows[j]
        t:ok(a.y + a.h <= b.y or b.y + b.h <= a.y, a.k .. " overlaps " .. b.k)
      end
    end
  end,
}
