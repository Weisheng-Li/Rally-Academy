-- Title / build select: list of builds on the left, hovered build vs Kai on the right.
local Layout = require("src.config.layout")
local Athletes = require("src.data.athletes")
local Draw = require("src.view.draw")
local Assets = require("src.view.assets")

local Title = {}
Title.__index = Title

local C = Layout.colors
local GROUPS = {
  { name = "Technique", stats = { "clear", "lift", "drop", "net", "drive", "smash" } },
  { name = "Physical",  stats = { "power", "speed", "legs" } },
  { name = "Movement",  stats = { "reach" } },
}

local LIST = { x = 24, y = 96, w = 210, h = 34, gap = 4 }
local PANEL = { x = 250, y = 96, w = 366, h = 232 }

function Title.new(app)
  local self = setmetatable({ app = app, hover = nil, shown = 1 }, Title)
  self.buttons = {}
  for i, key in ipairs(Athletes.playable) do
    self.buttons[i] = { profile = key, x = LIST.x, y = LIST.y + (i - 1) * (LIST.h + LIST.gap), w = LIST.w, h = LIST.h }
  end
  return self
end

function Title:update()
  local mx, my = self.app.mouse.x, self.app.mouse.y
  self.hover = nil
  for i, b in ipairs(self.buttons) do
    if mx >= b.x and mx <= b.x + b.w and my >= b.y and my <= b.y + b.h then self.hover = i end
  end
  if self.hover then self.shown = self.hover end
end

function Title:_drawPanel(a)
  local kai = Athletes.kai.stats
  local p = PANEL
  Draw.panel(p.x, p.y, p.w, p.h)
  Draw.text(a.title, p.x + 8, p.y + 6, C.text, Assets.fonts.normal)
  Draw.text(a.tag, p.x + 8, p.y + 19, C.textDim, Assets.fonts.small)
  Draw.color(C.near); love.graphics.rectangle("fill", p.x + 240, p.y + 9, 6, 6)
  Draw.text("you", p.x + 250, p.y + 6, C.textDim, Assets.fonts.small)
  Draw.color(C.far); love.graphics.rectangle("fill", p.x + 290, p.y + 9, 6, 6)
  Draw.text("Kai", p.x + 300, p.y + 6, C.textDim, Assets.fonts.small)

  local y = p.y + 34
  local barX, unit = p.x + 110, 22
  for _, g in ipairs(GROUPS) do
    Draw.text(g.name, p.x + 8, y, C.text, Assets.fonts.small)
    y = y + 11
    for _, stat in ipairs(g.stats) do
      local v, k = a.stats[stat], kai[stat]
      local col = v > k and C.good or (v < k and C.bad or C.textDim)
      Draw.text(stat, p.x + 18, y, C.textDim, Assets.fonts.small)
      Draw.text(tostring(v), p.x + 80, y, col, Assets.fonts.small, "right", 20)
      -- bars: you (full) and Kai (thin marker)
      Draw.color(C.near, 0.85)
      love.graphics.rectangle("fill", barX, y + 2, v * unit, 5)
      Draw.color(C.far)
      love.graphics.rectangle("fill", barX + k * unit - 1, y, 2, 9)
      Draw.color(C.textDim, 0.25)
      love.graphics.rectangle("line", barX + 0.5, y + 1.5, 10 * unit, 6)
      y = y + 11
    end
    y = y + 3
  end
end

function Title:draw()
  Draw.text("RALLY ACADEMY", 0, 18, C.text, Assets.fonts.title, "center", Layout.width)
  Draw.text("Pick a build and beat Kai (intermediate), first to 11", 0, 58, C.textDim, Assets.fonts.normal, "center", Layout.width)

  for i, b in ipairs(self.buttons) do
    local a = Athletes[b.profile]
    Draw.panel(b.x, b.y, b.w, b.h)
    if self.shown == i then
      Draw.color(C.near)
      love.graphics.rectangle("line", b.x + 1.5, b.y + 1.5, b.w - 3, b.h - 3)
    end
    Draw.text(string.format("[%d] %s", i, a.title), b.x + 8, b.y + 5, C.text, Assets.fonts.normal)
    Draw.text(a.tag, b.x + 8, b.y + 19, C.textDim, Assets.fonts.small)
  end
  self:_drawPanel(Athletes[self.buttons[self.shown].profile])
  Draw.text("Click or press 1-6 to play  -  Esc to quit", 0, 340, C.textDim, Assets.fonts.small, "center", Layout.width)
end

function Title:mousepressed(x, y, button)
  if button == 1 and self.hover then self.app:switch("match", { profile = self.buttons[self.hover].profile }) end
end

function Title:keypressed(key)
  local i = tonumber(key)
  if i and self.buttons[i] then self.app:switch("match", { profile = self.buttons[i].profile }) end
  if key == "escape" then love.event.quit() end
end

return Title
