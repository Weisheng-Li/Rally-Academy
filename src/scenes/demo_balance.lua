-- Prototype demo (not gameplay): lunge poses for the centre-of-gravity balance model.
-- One near-side player lunges in eight directions (shuffle in, short moves) and after two
-- long diagonal runs (running steps), each as:
--   controlled lunge : front knee over the foot, upper body upright, quick recovery
--   overreach        : upper body tilts toward the shuttle (Body.leanFor), back foot
--                      lifts and trails, long recovery before the next split step
-- Menu on the left (click a move, or Up/Down; Left/Right or the buttons switch controlled /
-- overreach). Keys: A auto-play all   Space pause   S slow motion   Z zoom
--       2 pose on/off (off = current fixed sprite)   3 ready ring   Esc title
local Layout = require("src.config.layout")
local Camera = require("src.view.camera")
local CourtView = require("src.view.court_view")
local Figure = require("src.view.figure")
local Draw = require("src.view.draw")
local Assets = require("src.view.assets")
local Body = require("src.core.body")

local Animator = require("src.view.animator")
local Anim = require("src.config.animation")    -- gait + lunge numbers, shared with the match

local C = Layout.colors
local STAND = Body.HIP_HEIGHT
local BASE = { x = 0, y = 3.6 }

local DIRS = {
  { name = "Front right", x = 0.6, y = -0.8, h = 0.5 },
  { name = "Right", x = 1, y = 0, h = 1.0 },
  { name = "Back right", x = 0.6, y = 0.8, h = 1.6 },
  { name = "Back left", x = -0.6, y = 0.8, h = 1.6 },
  { name = "Left", x = -1, y = 0, h = 1.0 },
  { name = "Front left", x = -0.6, y = -0.8, h = 0.5 },
  { name = "Forward", x = 0, y = -1, h = 0.5, dist = 1.8 },   -- base to the net: a few running steps
  { name = "Back", x = 0, y = 1, h = 1.6, dist = 1.5 },
}

-- lunge poses come from config/animation.lua (same as the match); the demo shows a full
-- stretch for the overreach and adds its own recovery timing
local function kind(name, label, recover)
  local L = Anim.lunge[name]
  local lean = L.lean or Body.leanFor(L.base + L.perStretch * 1)
  return { label = label, hip = L.hip, front = L.front, back = L.back, lean = lean, straight = L.straight,
           recover = recover }
end
local KINDS = {
  controlled = kind("controlled", "controlled lunge", 0.2),   -- back leg locked straight
  overreach = kind("overreach", "overreach", 0.8),            -- back foot lifts and trails
}

-- Long moves: run (alternating strides) instead of shuffling, then lunge. No run back
-- (the clip just restarts), since the player would turn around for that.
local LONG = {
  { name = "Diagonal run, back left to front right", short = "Run to front right", from = { x = -2.4, y = 5.9 }, to = { x = 2.1, y = 1.3 }, h = 0.5 },
  { name = "Diagonal run, front right to back left", short = "Run to back left", from = { x = 2.0, y = 1.6 }, to = { x = -2.3, y = 5.6 }, h = 1.6 },
}
local RUN_SPEED = 5.0         -- m/s average for the demo runs

-- keyframes: t, phase, cog s (m along dir from start), front, back, hip, lean, racket h, lift,
-- straight. dist = s at contact.
local function clip(def, kindName)
  local k = KINDS[kindName]
  local start = def.from or BASE
  local dx, dy = (def.to and def.to.x - start.x) or def.x, (def.to and def.to.y - start.y) or def.y
  local l = math.sqrt(dx * dx + dy * dy)
  local dist = def.to and (l - 0.45) or def.dist or 1.0
  -- long moves are run; so are short forward/back ones (real players turn side-on and
  -- shuffle there, which this sprite cannot show, so it just runs)
  local long = dist > Anim.run.from
  local gait = (long or math.abs(dx / l) < Anim.run.inOut) and "run" or "shuffle"
  local K, t = {}, 0
  local function add(dt, phase, s, f, b, hip, lean, h, lift, straight)
    t = t + dt
    K[#K + 1] = { t, phase, s, f, b, hip, lean, h, lift or 0, straight or 0 }
  end
  local moveTime = gait == "run" and 0.15 + (dist - 0.3) / RUN_SPEED or 0.40
  local backTime = math.max(0.55, dist / 3.5)
  add(0, "split", 0, 0.12, -0.12, STAND, 0, nil)
  add(0.07, "split", 0, 0.12, -0.12, STAND, 0, nil, 0.12)
  add(0.08, "move", 0, 0.12, -0.12, STAND, 0, nil)
  add(moveTime, "lunge", dist - 0.3, 0.3, -0.3, STAND, 0, nil)
  add(0.15, "push back", dist, k.front, k.back, k.hip, k.lean, def.h, 0, k.straight)   -- contact
  local contact = t
  add(0.25, "recover", dist - 0.05, k.front * 0.9, k.back * 0.9, k.hip + 0.05, k.lean * 0.7, nil, 0, k.straight)
  add(k.recover, "split", dist - 0.1, 0.12, -0.12, STAND, 0, nil)
  local ready = t
  add(0.06, "split", dist - 0.1, 0.12, -0.12, STAND, 0, nil, 0.12)
  if long then
    add(0.06, "ready", dist - 0.1, 0.12, -0.12, STAND, 0, nil)
    add(0.9, "ready", dist - 0.1, 0.12, -0.12, STAND, 0, nil)
  else
    add(0.06, "move back", dist - 0.1, 0.12, -0.12, STAND, 0, nil)
    add(backTime, "ready", 0, 0.12, -0.12, STAND, 0, nil)
    add(0.6, "ready", 0, 0.12, -0.12, STAND, 0, nil)
  end
  return { K = K, contact = contact, ready = ready, length = t, kind = k, dir = { x = dx / l, y = dy / l },
           start = start, dist = dist, gait = gait, long = long, name = def.name, h = def.h }
end

-- one menu entry per move, each with a controlled and an overreach clip
local MOVES = {}
for _, list in ipairs({ DIRS, LONG }) do
  for _, d in ipairs(list) do
    MOVES[#MOVES + 1] = { name = d.short or d.name, controlled = clip(d, "controlled"), overreach = clip(d, "overreach") }
  end
end

-- menu panel (virtual pixels)
local MENU = { x = 4, y = 20, w = 118, rowH = 12, kindY = 20, listY = 40 }

local Demo = {}
Demo.__index = Demo

function Demo.new(app)
  local self = setmetatable({}, Demo)
  self.app = app
  self.cam = Camera.new(Layout.camera)
  self.m, self.kind, self.t = 1, "controlled", 0
  self.auto = false                -- A: play every clip in turn
  self.slow, self.paused = false, false
  self.zoom = true
  self.pose, self.ring = true, false
  if app.dev.clip then             -- --clip N: N-th clip in menu order (controlled, overreach, ...)
    self.m = math.floor((app.dev.clip - 1) / 2) + 1
    self.kind = (app.dev.clip % 2 == 0) and "overreach" or "controlled"
  end
  return self
end

function Demo:current() return MOVES[self.m][self.kind] end

function Demo:select(m, kind)
  self.m = ((m - 1) % #MOVES) + 1
  self.kind = kind or self.kind
  self.t = 0
end

local function smooth(u) return u * u * (3 - 2 * u) end

local function sample(c, t)
  local K = c.K
  for i = 1, #K - 1 do
    local a, b = K[i], K[i + 1]
    if t <= b[1] then
      local u = (b[1] > a[1]) and (t - a[1]) / (b[1] - a[1]) or 1
      local e = (a[2] == "move" or a[2] == "move back") and u or smooth(u)
      local function mix(j)
        if a[j] == nil or b[j] == nil then return (u < 0.5) and a[j] or b[j] end
        return a[j] + (b[j] - a[j]) * e
      end
      return { phase = a[2], s = mix(3), front = mix(4), back = mix(5), hip = mix(6), lean = mix(7),
               h = mix(8), lift = mix(9), straight = mix(10) }
    end
  end
  local z = K[#K]
  return { phase = z[2], s = z[3], front = z[4], back = z[5], hip = z[6], lean = z[7], h = z[8], lift = z[9], straight = 0 }
end

function Demo:update(dt)
  if self.paused then return end
  self.t = self.t + dt * (self.slow and 0.3 or 1)
  if self.t > self:current().length then
    self.t = 0
    if self.auto then             -- controlled -> overreach -> next move
      if self.kind == "controlled" then self.kind = "overreach"
      else self.m, self.kind = self.m % #MOVES + 1, "controlled" end
    end
  end
end

local function other(kind) return kind == "controlled" and "overreach" or "controlled" end

function Demo:keypressed(key)
  if key == "down" then self:select(self.m + 1)
  elseif key == "up" then self:select(self.m - 1)
  elseif key == "left" or key == "right" or key == "tab" then self:select(self.m, other(self.kind))
  elseif key == "a" then self.auto = not self.auto
  elseif key == "space" then self.paused = not self.paused
  elseif key == "s" then self.slow = not self.slow
  elseif key == "z" then self.zoom = not self.zoom
  elseif key == "2" then self.pose = not self.pose
  elseif key == "3" then self.ring = not self.ring
  elseif key == "escape" then self.app:switch("title") end
end

local function at(c, s) return { x = c.start.x + c.dir.x * s, y = c.start.y + c.dir.y * s } end

-- shuttle: in from the far court to the contact point, then back out
local function shuttle(c, t)
  local hit = at(c, c.dist + 0.45)
  local from = { x = 0, y = -5.0 }
  if t < c.contact then
    local u = t / c.contact
    return { pos = { x = from.x + (hit.x - from.x) * u, y = from.y + (hit.y - from.y) * u },
             h = 2.6 + (c.h - 2.6) * u + math.sin(u * math.pi) * 2.0 }
  end
  local u = (t - c.contact) / 0.8
  if u >= 1 then return nil end
  return { pos = { x = hit.x + (from.x - hit.x) * u, y = hit.y + (from.y - hit.y) * u },
           h = c.h + (1.5 - c.h) * u + math.sin(u * math.pi) * 3.5 }
end

function Demo:drawPlayer(c, t)
  local cam = self.cam
  local p = sample(c, t)
  local front, back, hip, lift = p.front, p.back, p.hip, p.lift
  local frontLift, backLift, runKnees = 0, 0, false
  local cog = at(c, p.s)
  local moving = p.phase == "move" or p.phase == "move back"
  if moving then
    -- same gait as the match (Animator.gaitPose): run or side shuffle, stepping in time with
    -- the distance covered so the feet don't skate
    front, back, hip, lift, frontLift, backLift, runKnees = Animator.gaitPose(c.gait, p.s)
  elseif p.straight > 0 then
    back = back + (Figure.straightBack(cam, cog, c.dir, hip) - back) * p.straight
  end

  if self.ring and t >= c.contact and t < c.ready + 0.2 then
    local frac = math.min(1, (t - c.contact) / (c.ready - c.contact))
    local pts = cam:groundCircle(cog.x, cog.y, 0.4, 40)
    Draw.color(C.panel, 0.35)
    love.graphics.setLineWidth(2)
    love.graphics.polygon("line", pts)
    local arc = {}
    for i = 0, math.max(1, math.floor(frac * 40 + 0.5)) do
      local j = i % 40
      arc[#arc + 1] = pts[j * 2 + 1]; arc[#arc + 1] = pts[j * 2 + 2]
    end
    Draw.color(t >= c.ready and C.good or C.ok)
    if #arc >= 4 then love.graphics.line(arc) end
    love.graphics.setLineWidth(1)
  end

  if not self.pose then
    CourtView.drawAthlete(cam, { pos = cog, side = 1, pose = p.h and { h = p.h } or nil }, C.near)
    return p
  end
  local f = Figure.stance(cam, { cog = cog, dir = c.dir, hipH = hip, front = front, back = back,
                                 lean = p.lean, h = p.h, frontLift = frontLift, backLift = backLift,
                                 runKnees = runKnees }, 1)
  CourtView.drawStance(f, lift, C.near)
  return p
end

---------------------------------------------------------------------------- menu
-- Left panel: [Controlled] [Overreach] toggle, then one row per move. Click or use the keys.
local function kindButtons()
  local w = (MENU.w - 4) / 2
  return { { kind = "controlled", label = "Controlled", x = MENU.x + 2, y = MENU.kindY, w = w, h = 13 },
           { kind = "overreach", label = "Overreach", x = MENU.x + 2 + w, y = MENU.kindY, w = w, h = 13 } }
end

local function rowAt(i) return MENU.x, MENU.listY + (i - 1) * MENU.rowH, MENU.w, MENU.rowH end

local function inside(px, py, x, y, w, h) return px >= x and px < x + w and py >= y and py < y + h end

function Demo:mousepressed(x, y, button)
  if button ~= 1 then return end
  for _, b in ipairs(kindButtons()) do
    if inside(x, y, b.x, b.y, b.w, b.h) then self:select(self.m, b.kind) return end
  end
  for i = 1, #MOVES do
    if inside(x, y, rowAt(i)) then self:select(i) return end
  end
end

function Demo:drawMenu()
  local mx, my = self.app.mouse.x, self.app.mouse.y
  local h = MENU.listY + #MOVES * MENU.rowH + 4 - MENU.y + 6
  Draw.panel(MENU.x - 2, MENU.y - 4, MENU.w + 4, h)
  for _, b in ipairs(kindButtons()) do
    local on = self.kind == b.kind
    if on then Draw.color(b.kind == "overreach" and C.bad or C.good, 0.35); love.graphics.rectangle("fill", b.x, b.y, b.w - 2, b.h) end
    Draw.text(b.label, b.x, b.y + 2, on and C.text or C.textDim, Assets.fonts.small, "center", b.w - 2)
  end
  for i, mv in ipairs(MOVES) do
    local x, y, w, rh = rowAt(i)
    if i == self.m then
      Draw.color(C.recovery, 0.25); love.graphics.rectangle("fill", x, y, w, rh)
    elseif inside(mx, my, x, y, w, rh) then
      Draw.color(C.text, 0.08); love.graphics.rectangle("fill", x, y, w, rh)
    end
    local gait = mv.controlled.gait == "run" and "run" or "shuffle"
    Draw.text(mv.name, x + 4, y + 2, i == self.m and C.text or C.textDim, Assets.fonts.small)
    Draw.text(gait, x, y + 2, C.textDim, Assets.fonts.small, "right", w - 4)
  end
end

function Demo:draw()
  local cam = self.cam
  local c = self:current()
  love.graphics.push()
  if self.zoom then                              -- 2x, following the player (inspection only)
    local cog = at(c, sample(c, self.t).s)
    local bx, by = cam:project(cog.x, cog.y, 0.9)
    love.graphics.translate((Layout.width + MENU.x + MENU.w) / 2, Layout.height / 2)   -- centre right of the menu
    love.graphics.scale(2)
    love.graphics.translate(-bx, -by)
  end
  CourtView.drawFloor(cam)
  CourtView.drawNet(cam)
  local sh = shuttle(c, self.t)
  if sh then CourtView.drawShuttleShadow(cam, sh) end
  local p = self:drawPlayer(c, self.t)
  if sh then CourtView.drawShuttle(cam, sh) end
  love.graphics.pop()

  self:drawMenu()
  local left = MENU.x + MENU.w + 4
  local title = string.format("%s - %s", c.name, c.kind.label)
  if c.kind == KINDS.overreach then title = title .. string.format(" (lean %d deg)", math.floor(math.deg(c.kind.lean) + 0.5)) end
  Draw.text("LUNGE DEMO", MENU.x, 6, C.textDim, Assets.fonts.small)
  Draw.panel(left + 40, 18, Layout.width - left - 84, 32)
  Draw.text(title, left, 24, C.text, Assets.fonts.normal, "center", Layout.width - left)
  local sub = p.phase == "move" and c.gait or p.phase == "move back" and (c.gait .. " back") or p.phase
  if self.t >= c.contact and self.t < c.ready then sub = string.format("%s - can split step in %.1fs", p.phase, c.ready - self.t) end
  Draw.text(sub, left, 38, C.textDim, Assets.fonts.small, "center", Layout.width - left)
  local on = function(b) return b and "on" or "off" end
  Draw.text(string.format("Up/Down move  Left/Right kind  A auto [%s]  Space pause  S slow [%s]  Z zoom  2 pose [%s]  3 ring [%s]",
    on(self.auto), on(self.slow), on(self.pose), on(self.ring)), 8, 346, C.textDim, Assets.fonts.small)
end

return Demo
