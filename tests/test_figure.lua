-- Static sprite sizes (pixels) stay in proportion to the numbers in core/body.lua.
local Body = require("src.core.body")
local Layout = require("src.config.layout")
local Camera = require("src.view.camera")
local Figure = require("src.view.figure")

local cam = Camera.new(Layout.camera)

-- Depths to check: near baseline, near mid, near net, far net, far mid, far baseline.
local SPOTS = { { 6.0, 1 }, { 3.6, 1 }, { 1.5, 1 }, { -1.5, -1 }, { -3.6, -1 }, { -6.0, -1 } }

local function sprite(y, side, h)
  return Figure.athlete(cam, { pos = { x = 0, y = y }, side = side }, h)
end

local function each(fn)
  for _, sp in ipairs(SPOTS) do fn(sp[1], sp[2]) end
end

return {
  ["racket sprite : body sprite = 0.75 : 1.75"] = function(t)
    each(function(y, side)
      local f = sprite(y, side)
      t:near(f.racketLen / f.bodyH, Body.RACKET_LENGTH / Body.HEIGHT, 1e-9, string.format("y=%.1f", y))
      -- measured from the drawn endpoints too
      local px = math.sqrt((f.tipX - f.shoulderX) ^ 2 + (f.tipY - f.shoulderY) ^ 2)
      t:near(px / f.bodyH, Body.RACKET_LENGTH / Body.HEIGHT, 1e-9, string.format("endpoints y=%.1f", y))
    end)
  end,

  ["body sprite width : height matches the model"] = function(t)
    each(function(y, side)
      local f = sprite(y, side)
      t:near(f.bodyW / f.bodyH, Body.WIDTH / Body.HEIGHT, 1e-9, string.format("y=%.1f", y))
    end)
  end,

  ["racket handle is attached at the right shoulder"] = function(t)
    each(function(y, side)
      local f = sprite(y, side)
      t:near((f.feetY - f.shoulderY) / f.bodyH, Body.SHOULDER_HEIGHT / Body.HEIGHT, 1e-9, "shoulder height")
      -- right edge of the sprite: screen +x for the near player, -x for the far player
      t:near(f.shoulderX - f.feetX, side * f.bodyW / 2, 1e-9, "shoulder on the right edge")
    end)
  end,

  ["racket head sprite matches its share of the racket"] = function(t)
    each(function(y, side)
      local f = sprite(y, side)
      t:near(f.headLen / f.racketLen, Body.RACKET_HEAD / Body.RACKET_LENGTH, 1e-9, "head length share")
      t:near(f.headWidth / f.bodyH, Body.RACKET_HEAD_WIDTH / Body.HEIGHT, 1e-9, "head width")
    end)
  end,

  ["racket head is never smaller than the shuttle sprite"] = function(t)
    each(function(y, side)
      local f = sprite(y, side)
      local shuttleD = Figure.shuttleRadius(f.k) * 2
      t:ok(f.headWidth >= shuttleD, string.format("y=%.1f head %.2f px < shuttle %.2f px", y, f.headWidth, shuttleD))
    end)
  end,

  ["shuttle sprite = real size (or the visibility minimum)"] = function(t)
    each(function(y)
      local k = Figure.scale(cam, 0, y)
      t:near(Figure.shuttleRadius(k), math.max(Figure.MIN_SHUTTLE_RADIUS, Body.SHUTTLE_DIAMETER / 2 * k), 1e-9, "radius")
    end)
  end,

  ["racket sprite length is the same at every angle"] = function(t)
    for h = 0.3, 2.5, 0.2 do
      local f = sprite(3.6, 1, h)
      local px = math.sqrt((f.tipX - f.shoulderX) ^ 2 + (f.tipY - f.shoulderY) ^ 2)
      t:near(px, f.racketLen, 1e-9, string.format("h=%.1f", h))
    end
  end,
}
