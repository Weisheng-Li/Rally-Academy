-- Title screen hall: the match camera on an empty, lit centre court, with the rest of the
-- academy busy around it. The other courts run real AI-vs-AI matches (src/core/match.lua) and
-- people walk the aisles between courts. Dark walls, lights overhead, no windows.
-- Numbers and colours in layout.lua `hall`; sprites via src/view/figure.lua.
local Layout = require("src.config.layout")
local Camera = require("src.view.camera")
local CourtView = require("src.view.court_view")
local Figure = require("src.view.figure")
local Animator = require("src.view.animator")
local Draw = require("src.view.draw")
local Court = require("src.core.court")
local Match = require("src.core.match")
local Athletes = require("src.data.athletes")
local Body = require("src.core.body")
local TrainingView = require("src.view.training_view")

local HL = Layout.hall
local HC = HL.colors
local L, HD, HS = Court.LENGTH, Court.HALF_WIDTH_DOUBLES, Court.HALF_WIDTH_SINGLES
local STEP_X = 2 * HD + HL.gap                 -- centre-to-centre between side-by-side courts
local BACK_Y = -(2 * L + HL.backGap)           -- back row offset

local Hall = {}
Hall.__index = Hall

-- The match camera, shifted so a court centred at (ox, oy) draws with its own coordinates.
local function offsetCam(cam, ox, oy)
  return { hs = cam.hs, project = function(_, x, y, h) return cam:project(x + ox, y + oy, h) end }
end

function Hall.new(rng)
  local self = setmetatable({}, Hall)
  self.rng = rng
  self.cam = Camera.new(HL.camera or Layout.camera)
  self.time = 0
  self.courts = {}
  local function addCourt(ox, oy, busy)
    local ct = { ox = ox, oy = oy, cam = offsetCam(self.cam, ox, oy), busy = busy }
    self.courts[#self.courts + 1] = ct
    return ct
  end
  for _, k in ipairs(HL.backCourts) do addCourt(k * STEP_X, BACK_Y, true) end
  for _, k in ipairs(HL.sideCourts) do addCourt(k * STEP_X, 0, true) end
  self.centre = addCourt(0, 0, false)
  for _, ct in ipairs(self.courts) do if ct.busy then self:_newMatch(ct, self.rng() * 6) end end
  self:_makeWalkers()
  return self
end

-- A fresh AI-vs-AI match on a busy court (levels 2-6); `skip` s are played instantly so
-- the courts aren't all at the first serve.
function Hall:_newMatch(ct, skip)
  local a = 2 + math.floor(self.rng() * 5)
  local b = math.max(2, math.min(6, a + math.floor(self.rng() * 3) - 1))
  local rng = self.rng
  ct.match = Match.new({ near = Athletes.level(a, "A"), far = Athletes.level(b, "B"), human = {},
                         rng = rng, server = rng() < 0.5 and "near" or "far" })
  ct.anims = { near = Animator.new(1), far = Animator.new(-1) }
  local shirts = HC.shirts
  ct.colors = { near = shirts[1 + math.floor(rng() * #shirts)], far = shirts[1 + math.floor(rng() * #shirts)] }
  ct.restart = nil
  for _ = 1, math.floor((skip or 0) / 0.05) do ct.match:update(0.05) end
  ct.match:drainEvents()
end

---------------------------------------------------------------------------- walkers
-- Aisles: between the front-row courts, and the cross aisle between the rows. People walk
-- back and forth along a route, pausing at each end (a chat, a drink).
function Hall:_makeWalkers()
  local ax = HD + HL.gap / 2                    -- aisle beside the centre court
  local bx = ax + STEP_X                        -- next aisle out
  local cy = -L - HL.backGap / 2                -- cross aisle
  local routes = {
    { { -ax, L - 0.6 }, { -ax, cy }, { -bx, cy } },
    { { ax, L - 0.6 }, { ax, cy }, { bx + 1, cy } },
    { { -bx - 2, cy }, { bx + 2, cy } },
    { { -bx, cy + 0.4 }, { -bx, L - 2 } },
    { { bx, L - 2.5 }, { bx, cy + 0.3 }, { ax, cy + 0.3 } },
    { { ax + 0.3, cy - 0.2 }, { -ax - 0.3, cy - 0.2 } },
  }
  self.walkers = {}
  local shirts = HC.shirts
  for i = 1, math.min(HL.walkers, #routes) do
    local r = routes[i]
    local len = 0
    for j = 2, #r do len = len + math.sqrt((r[j][1] - r[j - 1][1]) ^ 2 + (r[j][2] - r[j - 1][2]) ^ 2) end
    local sp = HL.walkSpeed[1] + (HL.walkSpeed[2] - HL.walkSpeed[1]) * self.rng()
    self.walkers[i] = { route = r, len = len, speed = sp, d = self.rng() * len, dirSign = self.rng() < 0.5 and 1 or -1,
                        pause = 0, color = shirts[1 + (i * 3) % #shirts], travelled = 0 }
  end
end

local function along(route, d)
  for j = 2, #route do
    local a, b = route[j - 1], route[j]
    local seg = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
    if d <= seg or j == #route then
      local u = seg > 0 and math.min(1, d / seg) or 0
      return { x = a[1] + (b[1] - a[1]) * u, y = a[2] + (b[2] - a[2]) * u }, { x = (b[1] - a[1]) / seg, y = (b[2] - a[2]) / seg }
    end
    d = d - seg
  end
end

function Hall:_updateWalker(w, dt)
  if w.pause > 0 then w.pause = w.pause - dt; return end
  local step = w.speed * dt
  w.d = w.d + w.dirSign * step
  w.travelled = w.travelled + step
  if w.d >= w.len or w.d <= 0 then
    w.d = math.max(0, math.min(w.len, w.d))
    w.dirSign = -w.dirSign
    w.pause = 2 + self.rng() * 5
  end
end

---------------------------------------------------------------------------- update
function Hall:update(dt)
  self.time = self.time + dt
  for _, ct in ipairs(self.courts) do
    if ct.match then
      local m = ct.match
      if m.over then
        ct.restart = (ct.restart or 3) - dt
        if ct.restart <= 0 then self:_newMatch(ct) end
      else
        m:update(dt)
      end
      for key, anim in pairs(ct.anims) do anim:update(m.players[key], dt, ct.cam) end
      m:drainEvents()
    end
  end
  for _, w in ipairs(self.walkers) do self:_updateWalker(w, dt) end
end

---------------------------------------------------------------------------- drawing
local function quad(cam, x1, y1, x2, y2)
  local ax, ay = cam:project(x1, y1, 0)
  local bx, by = cam:project(x2, y1, 0)
  local cx, cy = cam:project(x2, y2, 0)
  local dx, dy = cam:project(x1, y2, 0)
  return { ax, ay, bx, by, cx, cy, dx, dy }
end

local function gline(cam, x1, y1, x2, y2)
  local ax, ay = cam:project(x1, y1, 0)
  local bx, by = cam:project(x2, y2, 0)
  love.graphics.line(ax, ay, bx, by)
end

local function drawCourt(cam)
  Draw.color(HC.court)
  love.graphics.polygon("fill", quad(cam, -HD, -L, HD, L))
  Draw.color(HC.lines)
  love.graphics.setLineWidth(1)
  for _, s in ipairs({ -1, 1 }) do
    gline(cam, s * HD, -L, s * HD, L)
    gline(cam, s * HS, -L, s * HS, L)
    gline(cam, -HD, s * L, HD, s * L)
    gline(cam, -HD, s * Court.LONG_SERVICE_DOUBLES, HD, s * Court.LONG_SERVICE_DOUBLES)
    gline(cam, -HD, s * Court.SHORT_SERVICE, HD, s * Court.SHORT_SERVICE)
    gline(cam, 0, s * Court.SHORT_SERVICE, 0, s * L)
  end
end

-- Net with yellow posts (like the hall's real ones).
local function drawNet(cam)
  local top, bottom = Court.NET_HEIGHT, Court.NET_HEIGHT - Court.NET_DEPTH
  local lx, lt = cam:project(-HD - 0.1, 0, top)
  local rx, rt = cam:project(HD + 0.1, 0, top)
  local _, lb = cam:project(-HD, 0, bottom)
  local _, rb = cam:project(HD, 0, bottom)
  local _, lg = cam:project(-HD, 0, 0)
  Draw.color(Layout.colors.net)
  love.graphics.polygon("fill", lx, lt, rx, rt, rx, rb, lx, lb)
  Draw.color(Layout.colors.netTape)
  love.graphics.line(lx, lt, rx, rt)
  Draw.color(HC.post)
  love.graphics.rectangle("fill", lx - 1, lt, 2, lg - lt)
  love.graphics.rectangle("fill", rx - 1, rt, 2, lg - rt)
  local _, _, s = cam:project(-HD, 0, 0)
  local fw = math.max(2, s * 0.3)
  love.graphics.rectangle("fill", lx - fw / 2, lg - 1, fw, 2)
  love.graphics.rectangle("fill", rx - fw / 2, lg - 1, fw, 2)
end

function Hall:_drawBackdrop()
  local W, H = Layout.width, Layout.height
  local cam = self.cam
  local wallY = BACK_Y - L - HL.wallBehind
  local _, wallFoot = cam:project(0, wallY, 0)
  -- ceiling and wall
  Draw.color(HC.ceiling)
  love.graphics.rectangle("fill", 0, 0, W, H)
  Draw.color(HC.wall)
  love.graphics.rectangle("fill", 0, HL.ceilingY, W, wallFoot - HL.ceilingY + 1)
  Draw.color(HC.wallTrim)
  love.graphics.rectangle("fill", 0, HL.ceilingY, W, 2)
  for i = 0, 6 do                                   -- steel columns on the back wall
    local x = (i + 0.5) * W / 7
    love.graphics.rectangle("fill", x - 1, HL.ceilingY, 3, wallFoot - HL.ceilingY)
  end
  -- light strips: rows running toward the back, bright bars with a faint glow
  local rows, per = HL.lights.rows, HL.lights.perRow
  for r = 1, rows do
    local x = (r - (rows + 1) / 2) * STEP_X
    for i = 1, per do
      local u = (i - 1) / (per - 1)
      local y = wallY + 1 + u * (BACK_Y + L - wallY)
      local sx, _, s = cam:project(x, y, 0)
      local ly = math.floor(HL.ceilingY - 4 - u * (HL.ceilingY - 8))   -- far ones low, near ones high
      local w = math.max(2, math.floor(s * 0.6))
      Draw.color(HC.glow, 0.06)
      love.graphics.rectangle("fill", sx - w, ly - 1, w * 2, 4)
      Draw.color(HC.light)
      love.graphics.rectangle("fill", math.floor(sx - w / 2), ly, w, u > 0.5 and 2 or 1)
    end
  end
  -- floor: the whole hall is court mat, wood strip at the front
  Draw.color(HC.floor)
  love.graphics.polygon("fill", quad(cam, -60, wallY, 60, L + HL.woodStrip))
  Draw.color(HC.wood)
  love.graphics.polygon("fill", quad(cam, -60, L + HL.woodStrip, 60, L + 12))
  Draw.color(HC.woodLine)
  for k = -14, 14 do gline(cam, k * 0.9, L + HL.woodStrip, k * 0.9, L + 12) end
end

-- Soft light pool on the empty centre court.
function Hall:_drawSpot()
  local pulse = 0.5 + 0.5 * math.sin(self.time * 1.3)
  for i = 6, 1, -1 do
    Draw.color(HC.spot, 0.025 + 0.01 * pulse)
    love.graphics.polygon("fill", self.cam:groundCircle(0, 2.6, i * 0.75, 40))
  end
end

local function drawWalker(cam, w)
  local pos, dir = along(w.route, w.d)
  if w.dirSign < 0 then dir = { x = -dir.x, y = -dir.y } end
  local front, back, hip, fl, bl = TrainingView.walkPose(w.pause > 0 and 0 or w.travelled)
  local st = { cog = pos, dir = dir, hipH = hip, front = front, back = back, frontLift = fl, backLift = bl, lean = 0 }
  if w.pause > 0 then st.front, st.back, st.hipH = 0.08, -0.08, Body.HIP_HEIGHT end
  CourtView.drawStance(Figure.stance(cam, st, 1), 0, w.color)
end

function Hall:draw()
  self:_drawBackdrop()
  for _, ct in ipairs(self.courts) do drawCourt(ct.cam) end
  self:_drawSpot()
  -- everything standing up, far to near across all courts
  local items = {}
  for _, ct in ipairs(self.courts) do
    items[#items + 1] = { y = ct.oy, draw = function() drawNet(ct.cam) end }
    local m = ct.match
    if m then
      for key, a in pairs(m.players) do
        items[#items + 1] = { y = ct.oy + a.pos.y, draw = function()
          CourtView.drawAnimated(ct.cam, a, ct.anims[key], ct.colors[key])
        end }
      end
      local sh = m.rally.shuttle
      if sh then
        items[#items + 1] = { y = ct.oy + sh.pos.y + 0.01, draw = function()
          CourtView.drawShuttleShadow(ct.cam, sh)
          CourtView.drawShuttle(ct.cam, sh)
        end }
      end
    end
  end
  for _, w in ipairs(self.walkers) do
    local pos = along(w.route, w.d)
    items[#items + 1] = { y = pos.y, draw = function() drawWalker(self.cam, w) end }
  end
  table.sort(items, function(a, b) return a.y < b.y end)
  for _, it in ipairs(items) do it.draw() end
end

-- Screen rectangle of the New career button (on the empty court).
function Hall:buttonRect()
  local x, y = self.cam:project(0, HL.buttonDepth, 0)
  return x - HL.buttonW / 2, y - HL.buttonH / 2, HL.buttonW, HL.buttonH
end

return Hall
