-- Body/racket numbers vs the numbers the rules use.
local Body = require("src.core.body")
local ShotData = require("src.data.shots")

return {
  ["racket is 0.75 m, about half the 1.75 m player"] = function(t)
    t:near(Body.HEIGHT, 1.75, 1e-9, "height")
    t:near(Body.RACKET_LENGTH, 0.75, 1e-9, "racket length")
    t:near(Body.RACKET_LENGTH / Body.HEIGHT, 0.43, 0.02, "racket / height")
  end,

  ["max reach = shoulder + racket"] = function(t)
    t:near(Body.MAX_REACH, Body.SHOULDER_HEIGHT + Body.RACKET_LENGTH, 1e-9, "max reach")
    t:ok(Body.SHOULDER_HEIGHT < Body.HEIGHT, "shoulder below the top of the head")
  end,

  ["every contact height in the shot data is within reach"] = function(t)
    for depth, row in pairs(ShotData.contactHeight) do
      for timing, h in pairs(row) do
        t:ok(h <= Body.MAX_REACH + 1e-9,
          string.format("%s/%s contact %.2f m is above max reach %.2f m", depth, timing, h, Body.MAX_REACH))
      end
    end
  end,

  ["every shot's minimum contact height is reachable on time"] = function(t)
    for id, def in pairs(ShotData.types) do
      if def.minContact then
        t:ok(def.minContact <= ShotData.contactHeight.back.ontime,
          string.format("%s needs %.2f m but on-time back contact is %.2f m", id, def.minContact,
            ShotData.contactHeight.back.ontime))
      end
    end
  end,

  ["racket angle points at the shuttle height"] = function(t)
    t:near(math.deg(Body.racketAngle(Body.MAX_REACH)), 90, 1e-6, "highest contact = straight up")
    t:near(math.deg(Body.racketAngle(Body.SHOULDER_HEIGHT)), 0, 1e-6, "shoulder height = level")
    t:near(math.deg(Body.racketAngle(Body.MIN_REACH)), -90, 1e-6, "lowest = straight down")
    for h = Body.MIN_REACH, Body.MAX_REACH, 0.1 do
      local tipH = Body.SHOULDER_HEIGHT + math.sin(Body.racketAngle(h)) * Body.RACKET_LENGTH
      t:near(tipH, h, 1e-6, string.format("tip height for h=%.2f", h))
    end
  end,

  ["real racket head (0.22 m) is wider than the real shuttle (0.065 m)"] = function(t)
    t:ok(Body.RACKET_HEAD_WIDTH > Body.SHUTTLE_DIAMETER, "head narrower than shuttle")
    t:ok(Body.RACKET_HEAD < Body.RACKET_LENGTH, "head longer than the racket")
  end,

  ["hitting spot is left of and behind the shuttle for both sides"] = function(t)
    -- near player faces -y (left = -x, behind = +y); far player faces +y (left = +x, behind = -y)
    local near = Body.hittingSpot({ x = 0, y = 3 }, 1)
    t:ok(near.x < 0 and near.y > 3, "near player spot should be at -x, +y")
    local far = Body.hittingSpot({ x = 0, y = -3 }, -1)
    t:ok(far.x > 0 and far.y < -3, "far player spot should be at +x, -y")
  end,
}
