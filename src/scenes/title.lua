-- Title / level picker: pick your level (left) and the opponent's (right), stats compared in
-- the middle. Same 6 levels for both (src/data/athletes.lua).
--   mouse: click a level in either column, click Play
--   keys:  Up/Down your level, W/S the opponent's, 1-6 your level, Enter play, D footwork demo
local Layout = require("src.config.layout")
local Athletes = require("src.data.athletes")
local Draw = require("src.view.draw")
local Assets = require("src.view.assets")

local Title = {}
Title.__index = Title

local C = Layout.colors
local M = Layout.menu
local N = #Athletes.levels
local GROUPS = {
  { name = "Technique", stats = { "clear", "lift", "drop", "net", "drive", "smash" } },
  { name = "Physical",  stats = { "power", "speed", "legs", "stamina" } },
  { name = "Movement",  stats = { "reach", "reaction", "recovery" } },
}

function Title.new(app, params)
  local self = setmetatable({ app = app, hover = nil }, Title)
  self.you = params.you or 3
  self.opp = params.opp or 3
  self.rows = {}
  for i = 1, N do
    local y = M.listY + (i - 1) * (M.rowH + M.rowGap)
    self.rows[#self.rows + 1] = { side = "you", level = i, x = M.youX, y = y, w = M.rowW, h = M.rowH }
    self.rows[#self.rows + 1] = { side = "opp", level = i, x = M.oppX, y = y, w = M.rowW, h = M.rowH }
  end
  self.play = { x = M.statsX + M.statsW / 2 - 50, y = M.statsY + M.statsH + 8, w = 100, h = 22 }
  return self
end

local function inside(b, x, y) return x >= b.x and x <= b.x + b.w and y >= b.y and y <= b.y + b.h end

function Title:update()
  local mx, my = self.app.mouse.x, self.app.mouse.y
  self.hover = nil
  for _, r in ipairs(self.rows) do if inside(r, mx, my) then self.hover = r end end
  self.hoverPlay = inside(self.play, mx, my)
end

function Title:_start()
  self.app:switch("match", { you = self.you, opp = self.opp })
end

function Title:_drawRow(r)
  local L = Athletes.levels[r.level]
  local picked = (r.side == "you" and self.you or self.opp) == r.level
  Draw.panel(r.x, r.y, r.w, r.h)
  if picked or self.hover == r then
    Draw.color(r.side == "you" and C.near or C.far, picked and 1 or 0.5)
    love.graphics.rectangle("line", r.x + 1.5, r.y + 1.5, r.w - 3, r.h - 3)
  end
  Draw.text(string.format("Lv%d %s", r.level, L.title), r.x + 8, r.y + 5, picked and C.text or C.textDim, Assets.fonts.normal)
  Draw.text(L.tag, r.x + 8, r.y + 19, C.textDim, Assets.fonts.small)
end

function Title:_drawStats()
  local you, opp = Athletes.levels[self.you].stats, Athletes.levels[self.opp].stats
  local x, y, w = M.statsX, M.statsY, M.statsW
  Draw.panel(x, y, w, M.statsH)
  Draw.color(C.near); love.graphics.rectangle("fill", x + 8, y + 9, 6, 6)
  Draw.text("you", x + 18, y + 6, C.textDim, Assets.fonts.small)
  Draw.color(C.far); love.graphics.rectangle("fill", x + 50, y + 9, 6, 6)
  Draw.text("opponent", x + 60, y + 6, C.textDim, Assets.fonts.small)
  y = y + 20
  local barX, unit = x + 96, 12
  for _, g in ipairs(GROUPS) do
    Draw.text(g.name, x + 8, y, C.text, Assets.fonts.small)
    y = y + 11
    for _, stat in ipairs(g.stats) do
      local v, k = you[stat], opp[stat]
      local col = v > k and C.good or (v < k and C.bad or C.textDim)
      Draw.text(stat, x + 16, y, C.textDim, Assets.fonts.small)
      Draw.text(tostring(v), x + 70, y, col, Assets.fonts.small, "right", 20)
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
  Draw.text("RALLY ACADEMY", 0, M.titleY, C.text, Assets.fonts.title, "center", Layout.width)
  Draw.text("Pick your level and your opponent's - first to 5", 0, M.subtitleY, C.textDim, Assets.fonts.normal,
    "center", Layout.width)
  Draw.text("You", M.youX, M.listY - 14, C.near, Assets.fonts.normal)
  Draw.text("Opponent", M.oppX, M.listY - 14, C.far, Assets.fonts.normal)
  for _, r in ipairs(self.rows) do self:_drawRow(r) end
  self:_drawStats()

  local p = self.play
  Draw.panel(p.x, p.y, p.w, p.h)
  if self.hoverPlay then Draw.color(C.good); love.graphics.rectangle("line", p.x + 1.5, p.y + 1.5, p.w - 3, p.h - 3) end
  Draw.text("Play", p.x, p.y + 6, C.text, Assets.fonts.normal, "center", p.w)
  Draw.text("Up/Down: your level   W/S: opponent   Enter: play   D: footwork demo   Esc: quit",
    0, M.hintY, C.textDim, Assets.fonts.small, "center", Layout.width)
end

function Title:mousepressed(x, y, button)
  if button ~= 1 then return end
  if self.hover then
    if self.hover.side == "you" then self.you = self.hover.level else self.opp = self.hover.level end
  elseif self.hoverPlay then
    self:_start()
  end
end

function Title:keypressed(key)
  local i = tonumber(key)
  if i and Athletes.levels[i] then self.you = i end
  if key == "up" then self.you = math.max(1, self.you - 1) end
  if key == "down" then self.you = math.min(N, self.you + 1) end
  if key == "w" then self.opp = math.max(1, self.opp - 1) end
  if key == "s" then self.opp = math.min(N, self.opp + 1) end
  if key == "return" or key == "space" then self:_start() end
  if key == "d" then self.app:switch("demo_balance") end
  if key == "escape" then love.event.quit() end
end

return Title
