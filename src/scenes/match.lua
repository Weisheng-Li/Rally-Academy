-- Match scene: wires the pure-logic Match to the views and input.
local Layout = require("src.config.layout")
local Athletes = require("src.data.athletes")
local Match = require("src.core.match")
local Camera = require("src.view.camera")
local CourtView = require("src.view.court_view")
local DecisionUI = require("src.view.decision_ui")
local Hud = require("src.view.hud")
local Draw = require("src.view.draw")
local Assets = require("src.view.assets")
local Animator = require("src.view.animator")

local MatchScene = {}
MatchScene.__index = MatchScene

-- params: you / opp (levels, quick match) or near / far (athlete defs, career), seed,
-- points / cap (score to win), onDone(won, score) (career: called when you leave the
-- finished match; Esc mid-match retires = a loss). Without onDone, back to the quick match.
function MatchScene.new(app, params)
  local self = setmetatable({}, MatchScene)
  self.app = app
  self.you, self.opp = params.you or 3, params.opp or 3   -- levels (src/data/athletes.lua)
  self.onDone = params.onDone
  local rng = love.math.newRandomGenerator(params.seed or os.time())
  local human = { near = true }
  if app.dev.autoDecisions then human = {} end   -- AI plays for you until N decisions have passed
  self.match = Match.new({
    near = params.near or Athletes.level(self.you, "You"), far = params.far or Athletes.level(self.opp),
    human = human, rng = function() return rng:random() end, server = app.dev.server,
    pointsToWin = params.points, cap = params.cap,
  })
  self.decisionsSeen = 0
  self.cam = Camera.new(Layout.camera)
  self.ui = DecisionUI.new(self.cam)
  self.hud = Hud.new(self.cam)
  self.timeScale = Layout.timeScale
  self.anims = { near = Animator.new(1), far = Animator.new(-1) }   -- footwork animation
  return self
end

function MatchScene:update(dt)
  local m = self.match
  local dev = self.app.dev
  if self.retireAsk then return end
  if dev.autoplay and self.onDone then                -- dev: career matches play themselves
    self.timeScale = 3
    if m.over then
      self.overT = (self.overT or 0) + dt
      if self.overT > 1 then
        print(string.format("[autoplay] match over %d-%d", m.score.near, m.score.far))
        self:_leave(m.winner == "near"); return
      end
    end
  end
  if not m.over then m:update(dt * self.timeScale) end
  for key, anim in pairs(self.anims) do anim:update(m.players[key], dt * self.timeScale, self.cam) end
  local events = m:drainEvents()
  if dev.autoDecisions then
    -- AI plays your first N shots, then control comes back to you
    for _, ev in ipairs(events) do
      if ev.type == "hit" and ev.key == "near" then self.decisionsSeen = self.decisionsSeen + 1 end
    end
    if self.decisionsSeen >= dev.autoDecisions then m.human.near = true end
  end
  self.hud:onEvents(m, events)
  self.hud:update(dt)

  if m.rally:isHumanDecision() then
    local mx, my = self.app.mouse.x, self.app.mouse.y
    self.ui:update(m.rally, mx, my, dev)
    if dev.pick and not self.forcedOnce then
      self.forcedOnce = true
      self.ui:force(m.rally, dev)
    end
  end
end

-- Dev screenshots wait for a frozen decision (one frame after it appears, so hover is applied).
function MatchScene:readyForShot()
  local d = self.match.rally:isHumanDecision() and self.match.rally.decision
  if not d then self.shotDecision = nil; return self.match.over end
  if self.shotDecision == d then return true end
  self.shotDecision = d
  return false
end

function MatchScene:_prompt()
  local m = self.match
  if m.over then return nil end
  if not m.rally:isHumanDecision() then return nil end
  if self.ui.mode == "target" then
    return m.rally.decision.kind == "serve" and "Your serve - pick short or long" or "Pick where to hit (hover for details)"
  end
  return "Pick your recovery spot   (Space: center, Right-click: back)"
end

function MatchScene:draw()
  local m = self.match
  local deciding = m.rally:isHumanDecision()
  CourtView.drawWorld(self.cam, m, {
    anims = self.anims,
    ground = deciding and function() self.ui:drawGround(m.rally) end or nil,
  })
  if deciding then self.ui:drawOverlay(m.rally) end
  self.hud:draw(m, self:_prompt(), self.timeScale)

  if m.over then
    local won = m.winner == "near"
    Draw.panel(170, 130, 300, 90)
    Draw.text(won and "YOU WIN" or (m.players.far.name:upper() .. " WINS"), 170, 145, won and Layout.colors.good or Layout.colors.bad,
      Assets.fonts.big, "center", 300)
    Draw.text(string.format("%d - %d", m.score.near, m.score.far), 170, 172, Layout.colors.text,
      Assets.fonts.normal, "center", 300)
    Draw.text(self.onDone and "Click or press Enter to continue" or "Click or press Enter for the menu", 170, 194,
      Layout.colors.textDim, Assets.fonts.normal, "center", 300)
  elseif self.retireAsk then
    Draw.panel(190, 150, 260, 40)
    Draw.text("Retire from this match?", 190, 156, Layout.colors.text, Assets.fonts.normal, "center", 260)
    Draw.text("Esc again: retire (counts as a loss)   any other key: play on", 190, 172, Layout.colors.textDim,
      Assets.fonts.small, "center", 260)
  end
end

-- Leave the match: career -> onDone(won, score); quick match -> back to the level picker.
function MatchScene:_leave(won)
  local m = self.match
  if self.onDone then
    self.onDone(won, string.format("%d-%d", m.score.near, m.score.far))
  else
    self.app:switch("quickmatch", { you = self.you, opp = self.opp })
  end
end

function MatchScene:mousepressed(x, y, button)
  if self.match.over then self:_leave(self.match.winner == "near"); return end
  if self.match.rally:isHumanDecision() then self.ui:mousepressed(self.match.rally, x, y, button) end
end

function MatchScene:keypressed(key)
  if self.match.over and (key == "return" or key == "space") then
    self:_leave(self.match.winner == "near"); return
  end
  if self.retireAsk then
    self.retireAsk = false
    if key == "escape" then self:_leave(false) end
    return
  end
  if key == "[" then self.timeScale = math.max(0.25, self.timeScale - 0.25) end
  if key == "]" then self.timeScale = math.min(3, self.timeScale + 0.25) end
  if key == "escape" and not (self.match.rally:isHumanDecision() and self.ui.mode == "recovery") then
    if self.onDone then self.retireAsk = true else self:_leave(false) end
    return
  end
  if self.match.rally:isHumanDecision() then self.ui:keypressed(self.match.rally, key) end
end

return MatchScene
