-- Title / profile select.
local Layout = require("src.config.layout")
local Athletes = require("src.data.athletes")
local Draw = require("src.view.draw")
local Assets = require("src.view.assets")

local Title = {}
Title.__index = Title

local C = Layout.colors
local STAT_ORDER = { "speed", "reaction", "recovery", "power", "clear", "drop", "smash", "net", "drive", "lift" }

function Title.new(app)
  local self = setmetatable({ app = app, hover = nil }, Title)
  self.buttons = {
    { profile = "rookie",  x = 120, y = 150, w = 180, h = 150, key = "1" },
    { profile = "trained", x = 340, y = 150, w = 180, h = 150, key = "2" },
  }
  return self
end

function Title:update()
  local mx, my = self.app.mouse.x, self.app.mouse.y
  self.hover = nil
  for i, b in ipairs(self.buttons) do
    if mx >= b.x and mx <= b.x + b.w and my >= b.y and my <= b.y + b.h then self.hover = i end
  end
end

function Title:draw()
  Draw.text("RALLY ACADEMY", 0, 40, C.text, Assets.fonts.title, "center", Layout.width)
  Draw.text("Interaction demo - vs Kai, first to 11", 0, 82, C.textDim, Assets.fonts.normal, "center", Layout.width)
  Draw.text("Pick your athlete", 0, 126, C.text, Assets.fonts.normal, "center", Layout.width)

  local kai = Athletes.kai.stats
  for i, b in ipairs(self.buttons) do
    local a = Athletes[b.profile]
    Draw.panel(b.x, b.y, b.w, b.h)
    if self.hover == i then
      Draw.color(C.near)
      love.graphics.rectangle("line", b.x + 1.5, b.y + 1.5, b.w - 3, b.h - 3)
    end
    Draw.text(string.format("[%s] %s", b.key, a.title), b.x + 8, b.y + 6, C.text, Assets.fonts.normal)
    Draw.text("you / Kai", b.x + 8, b.y + 20, C.textDim, Assets.fonts.small, "right", b.w - 16)
    for j, stat in ipairs(STAT_ORDER) do
      local y = b.y + 30 + (j - 1) * 11
      local v, k = a.stats[stat], kai[stat]
      local col = v > k and C.good or (v < k and C.bad or C.textDim)
      Draw.text(stat, b.x + 8, y, C.textDim, Assets.fonts.small)
      Draw.text(string.format("%d / %d", v, k), b.x + 8, y, col, Assets.fonts.small, "right", b.w - 16)
    end
  end
  Draw.text("Esc to quit", 0, 330, C.textDim, Assets.fonts.small, "center", Layout.width)
end

function Title:mousepressed(x, y, button)
  if button == 1 and self.hover then self.app:switch("match", { profile = self.buttons[self.hover].profile }) end
end

function Title:keypressed(key)
  if key == "1" then self.app:switch("match", { profile = "rookie" }) end
  if key == "2" then self.app:switch("match", { profile = "trained" }) end
  if key == "escape" then love.event.quit() end
end

return Title
