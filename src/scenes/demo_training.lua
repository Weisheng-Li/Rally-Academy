-- Training demo (idle mode prototype): the athlete works through the coach's schedule on his
-- own - drill sets with a feeder on court, sets in the gym, and whatever else he feels like in
-- between. Every rep pops up and fills its stat bar a little.
--   lovec . --demo training [--clock HH:MM] [--speed N] [--seed N]   (or T on the title screen)
-- Keys: 1-4 speed (x1 x3 x10 x30)   Space pause   Esc title
-- Demo only: click a block in the coach's plan to jump there.
local Layout = require("src.config.layout")
local Camera = require("src.view.camera")
local Draw = require("src.view.draw")
local Assets = require("src.view.assets")
local Training = require("src.core.training")
local View = require("src.view.training_view")

local TL = Layout.training
local C, TC = Layout.colors, Layout.training.colors
local TD = Training.data
local SPEEDS = { 1, 3, 10, 30 }

local Demo = {}
Demo.__index = Demo

function Demo.new(app)
  local self = setmetatable({ app = app }, Demo)
  local seed = app.dev.seed or os.time()
  local rng = love.math.newRandomGenerator(seed)
  self.sim = Training.new({ rng = function() return rng:random() end,
                            clock = app.dev.clock and Training.minutes(app.dev.clock) or nil })
  self.cam = Camera.new(TL.camera)
  self.view = View.new(self.cam)
  self.speed = app.dev.speed or 1
  self.paused = false
  self.shown = {}         -- displayed stat progress (eases toward the real value)
  self.flash = {}         -- stat row highlight after a gain
  return self
end

function Demo:update(dt)
  local mx, my = self.app.mouse.x, self.app.mouse.y
  self.hoverRow = self:rowAt(mx, my)
  if self.paused then return end
  local sim = self.sim
  local step = dt * self.speed
  -- fast speeds: several small steps so no rep or pose is skipped over in one jump
  local n = math.max(1, math.ceil(step / 0.05))
  for _ = 1, n do
    Training.update(sim, step / n)
    self.view:update(sim, step / n)
    for _, e in ipairs(sim.events) do
      if e.type == "rep" or e.type == "levelup" then self.flash[e.skill] = e.type == "levelup" and 2.0 or 0.6 end
    end
    sim.events = {}
  end
  for k, v in pairs(self.flash) do self.flash[k] = v - dt; if self.flash[k] <= 0 then self.flash[k] = nil end end
  for name, sk in pairs(sim.skills) do
    local target = sk.level + sk.progress / Training.repsFor(sk.level)
    local cur = self.shown[name] or target
    self.shown[name] = cur + (target - cur) * math.min(1, dt * 8)
    if target < cur then self.shown[name] = target end
  end
end

function Demo:keypressed(key)
  local i = tonumber(key)
  if i and SPEEDS[i] then self.speed = SPEEDS[i] end
  if key == "space" then self.paused = not self.paused end
  if key == "escape" then self.app:switch("title") end
end

---------------------------------------------------------------------------- schedule (clickable)
local function rowRect(i)
  local S = TL.schedule
  return S.x + 2, S.y + 16 + (i - 1) * S.rowH - 1, S.w - 4, S.rowH
end

function Demo:rowAt(x, y)
  for i = 1, #Training.schedule do
    local rx, ry, rw, rh = rowRect(i)
    if x >= rx and x < rx + rw and y >= ry and y < ry + rh then return i end
  end
end

-- Demo only: jump to the start of a block.
function Demo:mousepressed(x, y, button)
  if button ~= 1 then return end
  local i = self:rowAt(x, y)
  if not i then return end
  Training.jumpTo(self.sim, Training.schedule[i].start)
  self.sim.events = {}
  self.view:reset()
end

function Demo:drawSchedule()
  local S = TL.schedule
  local sim = self.sim
  local rows = Training.schedule
  local h = 16 + #rows * S.rowH + 4
  Draw.panel(S.x, S.y, S.w, h)
  Draw.text("COACH'S PLAN", S.x + 5, S.y + 4, C.textDim, Assets.fonts.small)
  local cur = Training.block(sim)
  for i, b in ipairs(rows) do
    local rx, ry, rw, rh = rowRect(i)
    local y = ry + 1
    local now = cur == b
    local past = sim.clock >= b.stop
    if now then
      Draw.color(C.recovery, 0.18)
      love.graphics.rectangle("fill", rx, ry, rw, rh)
      local u = (sim.clock - b.start) / (b.stop - b.start)
      Draw.color(C.recovery, 0.7)
      love.graphics.rectangle("fill", rx, ry + rh - 1, rw * u, 1)
    elseif self.hoverRow == i then
      Draw.color(C.text, 0.08)
      love.graphics.rectangle("fill", rx, ry, rw, rh)
    end
    local col = now and C.text or (past and { 0.45, 0.47, 0.52 } or C.textDim)
    if self.hoverRow == i then col = C.text end
    Draw.text(Training.clockText(b.start), S.x + 5, y + 1, col, Assets.fonts.small)
    Draw.text(b.label, S.x + 36, y + 1, col, Assets.fonts.small)
  end
end

function Demo:drawStats()
  local S = TL.stats
  local sim = self.sim
  local groups = { { "TECHNIQUE", TD.skills.technique }, { "PHYSICAL", TD.skills.physical } }
  local rows = #TD.skills.technique + #TD.skills.physical
  local h = 6 + 2 * 12 + rows * S.rowH + 4
  Draw.panel(S.x, S.y, S.w, h)
  local y = S.y + 4
  for _, g in ipairs(groups) do
    Draw.text(g[1], S.x + 5, y, C.textDim, Assets.fonts.small)
    y = y + 12
    for _, name in ipairs(g[2]) do
      local sk = sim.skills[name]
      local shown = self.shown[name] or sk.level
      local lvl = math.floor(shown)
      local frac = shown - lvl
      local fl = self.flash[name]
      if fl then
        Draw.color(fl > 0.6 and TC.levelup or C.good, math.min(0.35, fl * 0.5))
        love.graphics.rectangle("fill", S.x + 2, y - 1, S.w - 4, S.rowH)
      end
      Draw.text(name, S.x + 5, y, C.text, Assets.fonts.small)
      Draw.text(tostring(sk.level), S.x + 44, y, TC.levelup, Assets.fonts.small, "right", 12)
      local bx, bw = S.x + 60, S.w - 98
      Draw.color(C.textDim, 0.25)
      love.graphics.rectangle("fill", bx, y + 2, bw, 5)
      Draw.color(fl and C.good or C.recovery)
      love.graphics.rectangle("fill", bx, y + 2, bw * frac, 5)
      local need = Training.repsFor(sk.level)
      Draw.text(string.format("%d/%d", math.floor(sk.progress), need), S.x + S.w - 36, y, C.textDim,
        Assets.fonts.small, "right", 32)
      y = y + S.rowH
    end
  end
end

-- Top centre: day, clock, speed, and what he is doing right now.
function Demo:drawNow()
  local N = TL.now
  local sim = self.sim
  local a = sim.activity
  local x = (Layout.width - N.w) / 2
  Draw.panel(x, N.y, N.w, 30)
  Draw.text(string.format("Day %d", sim.day), x + 6, N.y + 4, C.textDim, Assets.fonts.small)
  Draw.text(Training.clockText(sim.clock), x, N.y + 2, C.text, Assets.fonts.normal, "center", N.w)
  local speed = self.paused and "paused" or ("x" .. self.speed)
  Draw.text(speed, x, N.y + 4, C.textDim, Assets.fonts.small, "right", N.w - 6)

  local label = a.label
  if a.repsTarget then
    label = string.format("%s  -  %s %d/%d", a.label, a.unit or "rep", math.min(a.reps + 1, a.repsTarget), a.repsTarget)
    if a.reps >= a.repsTarget then label = string.format("%s  -  set done", a.label) end
  end
  Draw.text(label, x, N.y + 17, C.text, Assets.fonts.small, "center", N.w)
end

function Demo:draw()
  local sim = self.sim
  self.view:draw(sim)
  if sim.activity.kind == "home" or sim.activity.kind == "arrive" then
    local a = sim.activity
    local u = a.kind == "home" and math.min(1, a.t / 2) or math.max(0, 1 - a.t / 1.2)
    love.graphics.setColor(0, 0, 0, u * 0.9)
    love.graphics.rectangle("fill", 0, 0, Layout.width, Layout.height)
    if a.kind == "home" and a.t > 1 then
      Draw.text(string.format("Day %d done - %d reps", sim.day, sim.totalReps), 0, 160, C.text, Assets.fonts.big, "center", Layout.width)
    end
  end
  self:drawSchedule()
  self:drawStats()
  self:drawNow()
  Draw.text("Click the plan to jump   1-4 speed   Space pause   Esc title", 0, TL.hintY, C.textDim,
    Assets.fonts.small, "right", Layout.width - 6)
end

return Demo
