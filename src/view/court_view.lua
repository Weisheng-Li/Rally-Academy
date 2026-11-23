-- Draws the 2.5D court, net, athletes and shuttle with placeholder shapes.
-- Replace drawAthlete / drawShuttle with sprite drawing when art exists.
local Court = require("src.core.court")
local Layout = require("src.config.layout")
local Draw = require("src.view.draw")
local Figure = require("src.view.figure")
local Body = require("src.core.body")
local Bal = require("src.data.balance")

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

-- Fixed upright sprite sized from core/body.lua (via Figure). The racket handle is
-- attached at the right shoulder and rotates in 2D to point at the shuttle's height.
function CourtView.drawAthlete(cam, a, color, alpha)
  local pose = a.pose
  local h = pose and (pose.h or (pose.state == "stretched" and Body.MIN_REACH)) or nil
  local f = Figure.athlete(cam, a, h)
  local x, y = f.feetX, f.feetY
  local bh, w = f.bodyH, f.bodyW
  local torsoTop = Body.SHOULDER_HEIGHT / Body.HEIGHT
  alpha = alpha or 1

  Draw.color(C.shadow, 0.35 * alpha)
  love.graphics.ellipse("fill", x, y, w * 0.8, w * 0.3)

  -- off-balance bar under the feet (empty = balanced, full red = completely off balance)
  if a.offBalance then
    local bw = math.max(16, w * 3)
    local bx, by = math.floor(x - bw / 2), math.floor(y + 3)
    Draw.color(C.panel, 0.9 * alpha)
    love.graphics.rectangle("fill", bx - 1, by - 1, bw + 2, 4)
    local ob = a.offBalance
    Draw.color(ob >= Bal.restrictAt and C.bad or C.ok, alpha)
    love.graphics.rectangle("fill", bx, by, math.floor(bw * ob + 0.5), 2)
  end

  -- legs, torso (top = shoulder), head
  local legH = bh * 0.42
  Draw.color({ 0.15, 0.15, 0.2 }, alpha)
  love.graphics.rectangle("fill", x - w * 0.4, y - legH, w * 0.8, legH)
  Draw.color(color, alpha)
  love.graphics.rectangle("fill", x - w * 0.5, y - bh * torsoTop, w, bh * (torsoTop - 0.42))
  Draw.color({ 0.95, 0.80, 0.65 }, alpha)
  local headR = bh * (1 - torsoTop) / 2
  love.graphics.circle("fill", x, y - bh + headR, headR)

  -- racket: handle from the shoulder to the head, oval head ending at the tip
  Draw.color({ 0.85, 0.85, 0.9 }, alpha)
  love.graphics.setLineWidth(1)
  love.graphics.line(f.shoulderX, f.shoulderY, f.headStartX, f.headStartY)
  love.graphics.push()
  love.graphics.translate(f.headCX, f.headCY)
  love.graphics.rotate(f.headAngle)
  love.graphics.ellipse("line", 0, 0, f.headLen / 2, f.headWidth / 2)
  love.graphics.pop()
end

function CourtView.drawShuttleShadow(cam, sh)
  local x, y = cam:project(sh.pos.x, sh.pos.y, 0)
  local r = Figure.shuttleRadius(Figure.scale(cam, sh.pos.x, sh.pos.y))
  Draw.color(C.shadow)
  love.graphics.ellipse("fill", x, y, r * 1.2, r * 0.5)
end

function CourtView.drawShuttle(cam, sh)
  local f = Figure.shuttle(cam, sh)
  Draw.color(C.shuttle)
  love.graphics.circle("fill", f.x, f.y, f.r)
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
