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

  ["posed sprite standing upright matches the static sprite"] = function(t)
    each(function(y, side)
      local still = sprite(y, side)
      local p = Figure.stance(cam, { cog = { x = 0, y = y }, dir = { x = 1, y = 0 }, hipH = Body.HIP_HEIGHT,
                                     front = 0.12, back = -0.12, lean = 0 }, side)
      local msg = string.format("y=%.1f", y)
      t:near(p.shoulderX, still.shoulderX, 1e-9, "shoulder x " .. msg)
      t:near(p.shoulderY, still.shoulderY, 1e-9, "shoulder y " .. msg)
      t:near(p.head.y - p.head.r, still.feetY - still.bodyH, 1e-9, "top of head " .. msg)
      t:near(p.racketLen, still.racketLen, 1e-9, "racket " .. msg)
    end)
  end,

  ["legs and torso keep fixed sizes in every pose (back foot lifts instead of stretching)"] = function(t)
    local dirs = { { 1, 0 }, { -1, 0 }, { 0, -1 }, { 0, 1 }, { 0.7071, -0.7071 }, { -0.7071, 0.7071 } }
    local stances = {   -- hipH, front, back, lean
      { Body.HIP_HEIGHT, 0.15, -0.15, 0 }, { 0.5, 0.7, -0.7, 0.1 }, { 0.45, 0.8, -1.6, Body.leanFor(0.3) },
      { 0.3, 0.9, -2.5, Body.leanFor(0.6) },
    }
    each(function(y, side)
      for _, d in ipairs(dirs) do
        for _, s in ipairs(stances) do
          local p = Figure.stance(cam, { cog = { x = 0, y = y }, dir = { x = d[1], y = d[2] }, hipH = s[1],
                                         front = s[2], back = s[3], lean = s[4] }, side)
          local msg = string.format("y=%.1f dir=(%g,%g) hip=%.2f back=%.1f", y, d[1], d[2], s[1], s[3])
          for _, L in ipairs(p.legs) do
            local thigh = math.sqrt((L[3] - L[1]) ^ 2 + (L[4] - L[2]) ^ 2)
            local shin = math.sqrt((L[5] - L[3]) ^ 2 + (L[6] - L[4]) ^ 2)
            if d[2] == 0 then        -- sideways: the whole leg is in the screen plane
              t:near(thigh, Figure.THIGH * p.k, 1e-6, "thigh " .. msg)
              t:near(shin, Figure.SHIN * p.k, 1e-6, "shin " .. msg)
            else                     -- a knee bending toward the camera is seen end-on: shorter, never longer
              t:ok(thigh <= Figure.THIGH * p.k + 1e-6, "thigh " .. msg)
              t:ok(shin <= Figure.SHIN * p.k + 1e-6, "shin " .. msg)
            end
          end
          t:ok(p.torsoLen <= Body.TORSO_LENGTH * p.k + 1e-9, "torso never longer than the model " .. msg)
          if d[2] == 0 then t:near(p.torsoLen, Body.TORSO_LENGTH * p.k, 1e-9, "sideways lean keeps length " .. msg) end
        end
      end
    end)
  end,

  ["controlled lunge: straight back leg reaches the floor at full length"] = function(t)
    for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0.6, -0.8 }, { -0.6, 0.8 } }) do
      each(function(y, side)
        local cog, dir = { x = 0, y = y }, { x = d[1], y = d[2] }
        local b = Figure.straightBack(cam, cog, dir, 0.5)
        local p = Figure.stance(cam, { cog = cog, dir = dir, hipH = 0.5, front = 0.35, back = b, lean = 0 }, side)
        local L = p.legs[2]
        local reach = math.sqrt((L[5] - L[1]) ^ 2 + (L[6] - L[2]) ^ 2)
        local msg = string.format("y=%.1f dir=(%g,%g)", y, d[1], d[2])
        t:ok(b < 0, "behind the hips " .. msg)
        t:ok(p.backPlanted, "foot on the floor " .. msg)
        t:near(reach, (Figure.THIGH + Figure.SHIN) * p.k, 0.002 * p.k, "leg straight " .. msg)
      end)
    end
  end,

  ["overreach lean covers exactly the extra distance"] = function(t)
    local lean = Body.leanFor(0.3)
    t:near(Body.TORSO_LENGTH * math.sin(lean), 0.3, 1e-9, "shoulder moves forward by the overreach")
    t:near(Body.leanFor(0), 0, 1e-12, "no overreach, no lean")
  end,

  ["serve: the racket head meets the shuttle at contact"] = function(t)
    local Shots = require("src.core.shots")
    each(function(y, side)
      local pos = { x = 0.7 * side, y = y }
      local g = Shots.serveGeometry(pos, side)
      local f = Figure.stance(cam, { cog = pos, dir = { x = 0, y = -side }, hipH = Body.HIP_HEIGHT,
        front = 0.12, back = -0.12, lean = 0, racketAngle = g.angle }, side)
      local sx, sy = cam:project(g.contact.x, g.contact.y, g.contact.h)
      -- height is exact; across, the shuttle lands on the strings (within the head's half width)
      t:near(f.headCY, sy, 1e-6, string.format("contact height y=%.1f", y))
      t:near(f.headCX, sx, f.headWidth / 2, string.format("on the strings y=%.1f", y))
      t:near(g.contact.h, Shots.data.serveHeight, 1e-9, "contact at the serve height")
      t:ok(g.contact.h < 1.15, "below the 1.15 m service rule")
    end)
  end,
}
