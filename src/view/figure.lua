-- Sprite geometry (pixels) for athletes, rackets and the shuttle, from core/body.lua
-- numbers. No drawing and no love.* calls, so tests/ can check the sprites stay in
-- proportion to the model.
--
-- All sprite sizes use one scale per depth: k = pixels per meter on the camera's
-- squashed vertical (cam.hs * s), so body, racket and shuttle stay in proportion.
local Body = require("src.core.body")

local Figure = {}

Figure.MIN_SHUTTLE_RADIUS = 1.5   -- px, so the shuttle stays visible far away

-- Pixels per meter for sprites at a ground point.
function Figure.scale(cam, x, y)
  local _, _, s = cam:project(x, y, 0)
  return cam.hs * s
end

-- Static athlete sprite: fixed upright body, racket attached at the right shoulder,
-- rotated in 2D to point at `h` (the shuttle height it is playing), or ready if nil.
function Figure.athlete(cam, a, h)
  local fx, fy = cam:project(a.pos.x, a.pos.y, 0)
  local k = Figure.scale(cam, a.pos.x, a.pos.y)
  local bodyH, bodyW = Body.HEIGHT * k, Body.WIDTH * k
  local right = a.side                    -- near player's right is screen +x, far player's is -x
  local sx, sy = fx + right * bodyW / 2, fy - Body.SHOULDER_HEIGHT * k

  local ang = h and Body.racketAngle(h) or math.rad(Body.READY_ANGLE)
  local ux, uy = right * math.cos(ang), -math.sin(ang)
  local L = Body.RACKET_LENGTH * k
  local headLen = Body.RACKET_HEAD * k
  local tx, ty = sx + ux * L, sy + uy * L
  local hx, hy = tx - ux * headLen, ty - uy * headLen
  return {
    k = k, feetX = fx, feetY = fy, bodyH = bodyH, bodyW = bodyW,
    shoulderX = sx, shoulderY = sy,
    tipX = tx, tipY = ty, headStartX = hx, headStartY = hy,
    headCX = (tx + hx) / 2, headCY = (ty + hy) / 2, headAngle = math.atan2(uy, ux),
    headLen = headLen, headWidth = Body.RACKET_HEAD_WIDTH * k, racketLen = L,
  }
end

function Figure.shuttleRadius(k) return math.max(Figure.MIN_SHUTTLE_RADIUS, Body.SHUTTLE_DIAMETER / 2 * k) end

function Figure.shuttle(cam, sh)
  local x, y = cam:project(sh.pos.x, sh.pos.y, sh.h)
  return { x = x, y = y, r = Figure.shuttleRadius(Figure.scale(cam, sh.pos.x, sh.pos.y)) }
end

return Figure
