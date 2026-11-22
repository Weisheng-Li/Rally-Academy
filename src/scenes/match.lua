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

local MatchScene = {}
MatchScene.__index = MatchScene

function MatchScene.new(app, params)
  local self = setmetatable({}, MatchScene)
  self.app = app
  self.profile = params.profile or "rookie"
  local rng = love.math.newRandomGenerator(params.seed or os.time())
  local human = { near = true }
  if app.dev.autoDecisions then human = {} end   -- AI plays for you until N decisions have passed
  self.match = Match.new({
    near = Athletes[self.profile], far = Athletes.kai,
    human = human, rng = function() return rng:random() end,
  })
  self.decisionsSeen = 0
  self.cam = Camera.new(Layout.camera)
  self.ui = DecisionUI.new(self.cam)
  self.hud = Hud.new(self.cam)
  self.timeScale = Layout.timeScale
  return self
end

function MatchScene:update(dt)
  local m = self.match
  local dev = self.app.dev
  if not m.over then m:update(dt * self.timeScale) end
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
    ground = deciding and function() self.ui:drawGround(m.rally) end or nil,
  })
  if deciding then self.ui:drawOverlay(m.rally) end
  self.hud:draw(m, self:_prompt(), self.timeScale)

  if m.over then
    local won = m.winner == "near"
    Draw.panel(170, 130, 300, 90)
    Draw.text(won and "YOU WIN" or "KAI WINS", 170, 145, won and Layout.colors.good or Layout.colors.bad,
      Assets.fonts.big, "center", 300)
    Draw.text(string.format("%d - %d", m.score.near, m.score.far), 170, 172, Layout.colors.text,
      Assets.fonts.normal, "center", 300)
    Draw.text("Click or press Enter for the menu", 170, 194, Layout.colors.textDim, Assets.fonts.normal, "center", 300)
  end
end

function MatchScene:mousepressed(x, y, button)
  if self.match.over then self.app:switch("title"); return end
  if self.match.rally:isHumanDecision() then self.ui:mousepressed(self.match.rally, x, y, button) end
end

function MatchScene:keypressed(key)
  if self.match.over and (key == "return" or key == "space") then self.app:switch("title"); return end
  if key == "[" then self.timeScale = math.max(0.25, self.timeScale - 0.25) end
  if key == "]" then self.timeScale = math.min(3, self.timeScale + 0.25) end
  if key == "escape" and not (self.match.rally:isHumanDecision() and self.ui.mode == "recovery") then
    self.app:switch("title"); return
  end
  if self.match.rally:isHumanDecision() then self.ui:keypressed(self.match.rally, key) end
end

return MatchScene
