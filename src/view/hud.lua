-- Score board, rally log, prompts and floating popups.
local Layout = require("src.config.layout")
local Draw = require("src.view.draw")
local Assets = require("src.view.assets")

local Hud = {}
Hud.__index = Hud

local C = Layout.colors
local H = Layout.hud

local REASON = { winner = "WINNER!", net = "NET!", long = "OUT!", wide = "OUT!", short = "SHORT!" }

function Hud.new(cam)
  return setmetatable({ cam = cam, log = {}, popups = {} }, Hud)
end

function Hud:push(line, col)
  table.insert(self.log, 1, { text = line, col = col or C.textDim })
  while #self.log > H.logLines do table.remove(self.log) end
end

function Hud:onEvents(match, events)
  for _, ev in ipairs(events) do
    if ev.type == "hit" then
      self:push(string.format("%s: %s (%d%%)", ev.who, ev.shot, math.floor(ev.success * 100 + 0.5)), C[ev.key])
    elseif ev.type == "point" then
      local who = match.players[ev.winner].name
      local col = ev.winner == "near" and C.good or C.bad
      self:push(string.format("Point %s - %s", who, REASON[ev.reason]), col)
      self.popups[#self.popups + 1] = { text = REASON[ev.reason], pos = ev.pos, t = 0, col = col }
    end
  end
end

function Hud:update(dt)
  for i = #self.popups, 1, -1 do
    local p = self.popups[i]
    p.t = p.t + dt
    if p.t > 1.4 then table.remove(self.popups, i) end
  end
end

function Hud:draw(match, prompt, timeScale)
  local font = Assets.fonts.normal

  -- score board
  Draw.panel(H.scoreX, H.scoreY, 120, 34)
  for i, key in ipairs({ "near", "far" }) do
    local a = match.players[key]
    local y = H.scoreY + 4 + (i - 1) * 13
    Draw.color(C[key])
    love.graphics.rectangle("fill", H.scoreX + 5, y + 3, 4, 7)
    Draw.text(a.name, H.scoreX + 13, y, C.text, font)
    if match.rally.server == key then Draw.text("*", H.scoreX + 70, y, C.ok, font) end
    Draw.text(tostring(match.score[key]), H.scoreX + 80, y, C.text, font, "right", 34)
  end
  Draw.text(match.players.near.title, H.scoreX, H.scoreY + 38, C.textDim, Assets.fonts.small)

  -- rally log
  Draw.panel(H.logX, H.logY, H.logWidth, 8 + H.logLines * 10)
  for i, l in ipairs(self.log) do
    Draw.text(l.text, H.logX + 4, H.logY + 4 + (i - 1) * 10, l.col, Assets.fonts.small)
  end

  -- popups
  for _, p in ipairs(self.popups) do
    local x, y = self.cam:project(p.pos.x, p.pos.y, 0.5 + p.t * 1.5)
    Draw.text(p.text, x - 50, y, p.col, Assets.fonts.big, "center", 100)
  end

  if prompt then
    Draw.text(prompt, 0, H.promptY, C.text, font, "center", Layout.width)
  end
  Draw.text(string.format("speed x%.2f  [ ]", timeScale), Layout.width - 110, H.promptY, C.textDim,
    Assets.fonts.small, "right", 104)
end

return Hud
