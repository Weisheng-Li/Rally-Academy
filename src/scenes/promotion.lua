-- Promotion: the old league emblem shakes, cracks and bursts into its own facets, light
-- floods the screen, and the new emblem forms with a shine sweeping across it.
-- params: { from, to, champion } (Career.finish). Click / Enter (once it has landed): hub.
local Layout = require("src.config.layout")
local Draw = require("src.view.draw")
local Assets = require("src.view.assets")
local Emblem = require("src.view.emblem")
local Athletes = require("src.data.athletes")
local CD = require("src.data.career")

local PR = Layout.promotion
local C = Layout.colors
local ACCENT = Layout.hub.accent

local Scene = {}
Scene.__index = Scene

-- timeline (s)
local SHAKE, BURST, FORM, LAND = 1.3, 1.3, 1.55, 2.4

function Scene.new(app, params)
  local self = setmetatable({ app = app, t = 0 }, Scene)
  self.from = params.from or 1
  self.to = params.champion and 7 or (params.to or 2)
  self.champion = params.champion
  self.cx, self.cy = Layout.width / 2, PR.emblemY
  -- shards: the old emblem's own polygons, each flying off from where it sits
  local rng = love.math.newRandomGenerator(7)
  self.shards = {}
  for _, p in ipairs(Emblem.geometry(self.from, PR.emblemR)) do
    if p.part ~= "hole" then
      local sx, sy, n = 0, 0, #p.pts / 2
      for i = 1, #p.pts, 2 do sx = sx + p.pts[i]; sy = sy + p.pts[i + 1] end
      sx, sy = sx / n, sy / n
      local d = math.sqrt(sx * sx + sy * sy) + 1
      local sp = 120 + rng:random() * 160
      self.shards[#self.shards + 1] = { poly = p, cx = sx, cy = sy, vx = sx / d * sp + (rng:random() - 0.5) * 60,
        vy = sy / d * sp - 60 - rng:random() * 80, spin = (rng:random() - 0.5) * 8 }
    end
  end
  self.cracks = {}
  for i = 1, 7 do
    local a = (i / 7) * math.pi * 2 + rng:random() * 0.5
    local pts, r = { 0, 0 }, 0
    for _ = 1, 4 do
      r = r + PR.emblemR * (0.15 + rng:random() * 0.15)
      a = a + (rng:random() - 0.5) * 0.7
      pts[#pts + 1] = math.cos(a) * r; pts[#pts + 1] = math.sin(a) * r
    end
    self.cracks[i] = pts
  end
  return self
end

function Scene:update(dt)
  self.t = self.t + dt
  if self.app.dev.autoplay and self.t > LAND + 1.5 and not self.left then   -- dev: move on by itself
    self.left = true
    print(string.format("[autoplay] promoted to %d", self.to))
    self.app:switch("hub")
  end
end

local function easeOutBack(u)
  local c1 = 1.70158
  return 1 + (c1 + 1) * (u - 1) ^ 3 + c1 * (u - 1) ^ 2
end


function Scene:_drawRays(alpha)
  local n = 14
  love.graphics.push()
  love.graphics.translate(self.cx, self.cy)
  love.graphics.rotate(self.t * 0.15)
  for i = 1, n do
    local a = i / n * math.pi * 2
    Draw.color(ACCENT, alpha * (i % 2 == 0 and 0.08 or 0.04))
    love.graphics.polygon("fill", 0, 0, math.cos(a - 0.12) * 500, math.sin(a - 0.12) * 500,
      math.cos(a + 0.12) * 500, math.sin(a + 0.12) * 500)
  end
  love.graphics.pop()
end

-- A bright band sweeping across the emblem, clipped to its hexagon.
function Scene:_drawShine(u)
  local R = PR.emblemR
  love.graphics.stencil(function()
    local pts = {}
    for i = 0, 5 do
      local a = math.rad(-90 + i * 60)
      pts[#pts + 1] = self.cx + math.cos(a) * R; pts[#pts + 1] = self.cy + math.sin(a) * R
    end
    love.graphics.polygon("fill", pts)
  end, "replace", 1)
  love.graphics.setStencilTest("greater", 0)
  local x = self.cx - R * 1.6 + u * R * 3.2
  love.graphics.setColor(1, 1, 1, 0.35)
  love.graphics.polygon("fill", x - 8, self.cy + R, x + 4, self.cy + R, x + 22, self.cy - R, x + 10, self.cy - R)
  love.graphics.setStencilTest()
end

function Scene:draw()
  local t, R = self.t, PR.emblemR
  local W, H = Layout.width, Layout.height
  love.graphics.clear(0.05, 0.06, 0.09)
  if t < SHAKE then
    -- old emblem shakes harder and cracks
    local u = t / SHAKE
    local sh = u * u * 4
    local ox, oy = math.sin(t * 61) * sh, math.cos(t * 47) * sh
    Emblem.draw(self.from, self.cx + ox, self.cy + oy, R)
    if u > 0.35 then
      love.graphics.setColor(1, 1, 1, math.min(1, (u - 0.35) * 2))
      love.graphics.setLineWidth(1)
      local shown = math.floor((u - 0.35) / 0.65 * #self.cracks) + 1
      for i = 1, math.min(#self.cracks, shown) do
        love.graphics.push(); love.graphics.translate(self.cx + ox, self.cy + oy)
        love.graphics.line(self.cracks[i]); love.graphics.pop()
      end
    end
    Draw.text(Athletes.levels[self.from].title, 0, PR.textY, C.textDim, Assets.fonts.normal, "center", W)
  else
    local since = t - BURST
    -- shards of the old emblem flying out
    local m = Layout.emblems.tiers[self.from]
    for _, s in ipairs(self.shards) do
      local a = math.max(0, 1 - since / 1.4)
      if a > 0 then
        local px = self.cx + s.cx + s.vx * since
        local py = self.cy + s.cy + s.vy * since + 260 * since * since
        love.graphics.push()
        love.graphics.translate(px, py)
        love.graphics.rotate(s.spin * since)
        love.graphics.translate(-s.cx, -s.cy)
        local col = s.poly.part == "frame" and m.frame or (m.gem or m.frame)
        local k = 1 + s.poly.shade * 0.3
        love.graphics.setColor(col[1] * k, col[2] * k, col[3] * k, a)
        love.graphics.polygon("fill", s.poly.pts)
        love.graphics.pop()
      end
    end
    -- rays, then the new emblem growing in
    if t > FORM then
      local u = math.min(1, (t - FORM) / (LAND - FORM))
      self:_drawRays(u)
      local scale = easeOutBack(u)
      if scale > 0.02 then
        Emblem.draw(self.to, self.cx, self.cy, R * scale)
        if u >= 1 then
          local s = ((t - LAND) % 3.2) / 1.1
          if s <= 1 then self:_drawShine(s) end
        end
      end
    end
    -- flash
    local f = math.max(0, 1 - since / 0.5)
    if f > 0 then love.graphics.setColor(1, 1, 1, f * 0.9); love.graphics.rectangle("fill", 0, 0, W, H) end
  end
  if t > LAND then
    local a = math.min(1, (t - LAND) / 0.4)
    local head = self.champion and "WORLD CHAMPION" or "PROMOTED"
    local name = self.champion and "Gold and diamond, the top of the sport" or
      string.format("Lv%d %s", self.to, Athletes.levels[self.to].title)
    Draw.text(head, 0, PR.textY - 8, { ACCENT[1], ACCENT[2], ACCENT[3], a }, Assets.fonts.title, "center", W)
    Draw.text(name, 0, PR.textY + 30, { 1, 1, 1, a }, Assets.fonts.big, "center", W)
    if not self.champion then
      local ev = CD.events[self.to]
      Draw.text(string.format("Next: %s  -  %d players", ev.name, ev.size), 0, PR.textY + 58, C.textDim,
        Assets.fonts.normal, "center", W)
    end
    Draw.text("Click to continue", 0, H - 18, C.textDim, Assets.fonts.small, "center", W)
  end
end

function Scene:mousepressed(_, _, button)
  if button == 1 and self.t > LAND then self.app:switch("hub") end
end

function Scene:keypressed(key)
  if (key == "return" or key == "space" or key == "escape") and self.t > LAND then self.app:switch("hub") end
end

-- dev screenshots: once the new emblem has landed
function Scene:readyForShot() return self.t > LAND + 0.6 end

return Scene
