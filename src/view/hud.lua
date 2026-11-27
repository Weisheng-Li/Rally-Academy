-- Score board, prompts and floating popups.
local Layout = require("src.config.layout")
local Draw = require("src.view.draw")
local Assets = require("src.view.assets")

local Hud = {}
Hud.__index = Hud

local C = Layout.colors
local H = Layout.hud

local REASON = { winner = "WINNER!", net = "NET!", long = "OUT!", wide = "OUT!", short = "SHORT!" }

function Hud.new(cam)
  return setmetatable({ cam = cam, popups = {}, beats = {}, hrs = {} }, Hud)
end

function Hud:onEvents(match, events)
  for _, ev in ipairs(events) do
    if ev.type == "point" then
      local col = ev.winner == "near" and C.good or C.bad
      self.popups[#self.popups + 1] = { text = REASON[ev.reason], pos = ev.pos, t = 0, col = col }
    end
  end
end

function Hud:update(dt)
  for k, hr in pairs(self.hrs) do self.beats[k] = ((self.beats[k] or 0) + dt * hr / 60) % 1 end  -- beat phases
  for i = #self.popups, 1, -1 do
    local p = self.popups[i]
    p.t = p.t + dt
    if p.t > 1.4 then table.remove(self.popups, i) end
  end
end

function Hud:draw(match, prompt, timeScale)
  local font = Assets.fonts.normal

  -- score board
  Draw.panel(H.scoreX, H.scoreY, 132, 34)
  for i, key in ipairs({ "near", "far" }) do
    local a = match.players[key]
    local y = H.scoreY + 4 + (i - 1) * 13
    Draw.color(C[key])
    love.graphics.rectangle("fill", H.scoreX + 5, y + 3, 4, 7)
    Draw.text(a.name, H.scoreX + 13, y, C.text, font)
    if match.rally.server == key then Draw.text("*", H.scoreX + 119, y, C.ok, font) end   -- right of the score
    Draw.text(tostring(match.score[key]), H.scoreX + 80, y, C.text, font, "right", 34)
  end
  local P = match.players
  Draw.text(string.format("Lv%d vs Lv%d", P.near.level or 0, P.far.level or 0), H.scoreX, H.scoreY + 38, C.textDim, Assets.fonts.small)
  self:_drawHeart(P.near, "near", H.hr.y)
  if H.hr.showOpponent then self:_drawHeart(P.far, "far", H.hr.oppY, P.far.name) end   -- TEMPORARY debug

  -- popups
  for _, p in ipairs(self.popups) do
    -- bottom edge sits above the landing spot so the skidding shuttle stays visible
    local P = Layout.popup
    local x, y = self.cam:project(p.pos.x, p.pos.y, P.startHeight + p.t * P.rise)
    local font = Assets.fonts.big
    Draw.text(p.text, x - 50, y - font:getHeight(), p.col, font, "center", 100)
  end

  if prompt then
    Draw.text(prompt, 0, H.promptY, C.text, font, "center", Layout.width)
  end
  Draw.text(string.format("speed x%.2f  [ ]", timeScale), Layout.width - 110, H.promptY, C.textDim,
    Assets.fonts.small, "right", 104)
end

-- Your heart rate: a dot pulsing at that rate, the bpm, and what it does to you right now
-- (data/heart.lua: slower legs and shakier shots past the onset).
function Hud:_drawHeart(a, key, y, label)
  local Hd = require("src.data.heart")
  local R = H.hr
  self.hrs[key] = a.hr
  R = { x = R.x, y = y, textY = R.textY }
  local f = a:fatigue()
  local col = f <= 0 and C.good or (f < 0.6 and C.ok or C.bad)
  local pulse = math.max(0, 1 - (self.beats[key] or 0) * 4)    -- quick flash on each beat
  Draw.color(col, 0.5 + 0.5 * pulse)
  love.graphics.circle("fill", R.x + 4, R.y + 5, 2.5 + pulse)
  local bpm = string.format("%d bpm", math.floor(a.hr + 0.5))
  if label then bpm = label .. ": " .. bpm end
  Draw.text(bpm, R.x + 11, R.y, label and C[key] or C.text, Assets.fonts.small)
  local effect = "Fresh"
  local slower = math.floor(Hd.slowAtMax * f * 100 + 0.5)
  if slower >= 1 then
    effect = string.format("%s: %d%% slower, shakier", f < 0.6 and "Tiring" or "Exhausted", slower)
  end
  Draw.text(effect, R.x, R.y + R.textY, col, Assets.fonts.small)
end

return Hud
