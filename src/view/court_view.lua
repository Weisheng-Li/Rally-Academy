-- Draws the 2.5D court, net, athletes and shuttle with placeholder shapes.
-- Replace drawAthlete / drawShuttle with sprite drawing when art exists.
local Court = require("src.core.court")
local Layout = require("src.config.layout")
local Draw = require("src.view.draw")

local CourtView = {}
local C = Layout.colors
local L, HD, HS = Court.LENGTH, Court.HALF_WIDTH_DOUBLES, Court.HALF_WIDTH_SINGLES

local function groundQuad(cam, x1, y1, x2, y2)
  local ax, ay = cam:project(x1, y1, 0)
  local bx, by = cam:project(x2, y1, 0)
  local cx, cy = cam:project(x2, y2, 0)
  local dx, dy = cam:project(x1, y2, 0)
  return { ax, ay, bx, by, cx, cy, dx, dy }
end

local function groundLine(cam, x1, y1, x2, y2)
  local ax, ay = cam:project(x1, y1, 0)
  local bx, by = cam:project(x2, y2, 0)
  love.graphics.line(ax, ay, bx, by)
end

function CourtView.drawFloor(cam)
  Draw.color(C.floor)
  love.graphics.polygon("fill", groundQuad(cam, -HD - 0.8, -L - 0.9, HD + 0.8, L + 0.4))
  Draw.color(C.court)
  love.graphics.polygon("fill", groundQuad(cam, -HD, -L, HD, L))

  Draw.color(C.lines)
  love.graphics.setLineWidth(1)
  for _, s in ipairs({ -1, 1 }) do
    groundLine(cam, s * HD, -L, s * HD, L)                         -- doubles sidelines
    groundLine(cam, s * HS, -L, s * HS, L)                         -- singles sidelines
    groundLine(cam, -HD, s * L, HD, s * L)                         -- baselines
    groundLine(cam, -HD, s * Court.LONG_SERVICE_DOUBLES, HD, s * Court.LONG_SERVICE_DOUBLES)
    groundLine(cam, -HD, s * Court.SHORT_SERVICE, HD, s * Court.SHORT_SERVICE)
    groundLine(cam, 0, s * Court.SHORT_SERVICE, 0, s * L)          -- center line
  end
end

function CourtView.drawNet(cam)
  local top, bottom = Court.NET_HEIGHT, Court.NET_HEIGHT - Court.NET_DEPTH
  local lx, lt = cam:project(-HD, 0, top)
  local rx, rt = cam:project(HD, 0, top)
  local _, lb = cam:project(-HD, 0, bottom)
  local _, rb = cam:project(HD, 0, bottom)
  local _, lg = cam:project(-HD, 0, 0)

  Draw.color(C.net)
  love.graphics.polygon("fill", lx, lt, rx, rt, rx, rb, lx, lb)
  love.graphics.setColor(1, 1, 1, 0.12)
  for x = lx + 4, rx - 1, 4 do love.graphics.line(x, lt, x, lb) end
  Draw.color(C.netTape)
  love.graphics.setLineWidth(2)
  love.graphics.line(lx, lt, rx, rt)
  love.graphics.setLineWidth(1)
  Draw.color(C.post)
  love.graphics.rectangle("fill", lx - 1, lt, 2, lg - lt)
  love.graphics.rectangle("fill", rx - 1, rt, 2, lg - rt)
end

function CourtView.drawAthlete(cam, a, color, alpha)
  local x, y, s = cam:project(a.pos.x, a.pos.y, 0)
  local cfg = Layout.actor
  local h = cfg.bodyHeight * cam.hs * s
  local w = math.max(3, cfg.width * s)
  alpha = alpha or 1

  Draw.color(C.shadow, 0.35 * alpha)
  love.graphics.ellipse("fill", x, y, w * 0.8, w * 0.3)

  -- legs, torso, head
  local legH = h * 0.42
  Draw.color({ 0.15, 0.15, 0.2 }, alpha)
  love.graphics.rectangle("fill", math.floor(x - w * 0.4), math.floor(y - legH), math.ceil(w * 0.8), math.ceil(legH))
  Draw.color(color, alpha)
  love.graphics.rectangle("fill", math.floor(x - w * 0.5), math.floor(y - h * 0.82), math.ceil(w), math.ceil(h * 0.42))
  Draw.color({ 0.95, 0.80, 0.65 }, alpha)
  love.graphics.circle("fill", x, y - h * 0.9, w * 0.32)

  -- racket on the player's right hand side (screen right for near, screen left for far)
  local dir = a.side == 1 and 1 or -1
  Draw.color({ 0.85, 0.85, 0.9 }, alpha)
  local hx, hy = x + dir * w * 0.55, y - h * 0.7
  love.graphics.line(hx, hy, hx + dir * w * 0.3, hy - h * 0.25)
  love.graphics.circle("line", hx + dir * w * 0.38, hy - h * 0.33, math.max(1.5, w * 0.22))
end

function CourtView.drawShuttleShadow(cam, sh)
  local x, y, s = cam:project(sh.pos.x, sh.pos.y, 0)
  Draw.color(C.shadow)
  love.graphics.ellipse("fill", x, y, math.max(1.5, 0.12 * s), math.max(1, 0.05 * s))
end

function CourtView.drawShuttle(cam, sh)
  local x, y, s = cam:project(sh.pos.x, sh.pos.y, sh.h)
  Draw.color(C.shuttle)
  love.graphics.circle("fill", x, y, math.max(1.5, 0.07 * s))
end

-- Draws everything in depth order (far to near).
function CourtView.drawWorld(cam, match, extra)
  CourtView.drawFloor(cam)
  local rally = match.rally
  if rally.shuttle then CourtView.drawShuttleShadow(cam, rally.shuttle) end
  if extra and extra.ground then extra.ground() end

  local items = {
    { y = 0, draw = function() CourtView.drawNet(cam) end },
  }
  for key, a in pairs(match.players) do
    items[#items + 1] = { y = a.pos.y, draw = function() CourtView.drawAthlete(cam, a, C[key]) end }
  end
  if rally.shuttle then
    items[#items + 1] = { y = rally.shuttle.pos.y + 0.01, draw = function() CourtView.drawShuttle(cam, rally.shuttle) end }
  end
  table.sort(items, function(a, b) return a.y < b.y end)
  for _, it in ipairs(items) do it.draw() end
end

return CourtView
