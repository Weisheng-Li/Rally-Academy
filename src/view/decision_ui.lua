-- The frozen-at-contact UI: pick a target (with success % bubbles and a breakdown
-- tooltip), then pick a recovery spot inside the reachable circle.
local Layout = require("src.config.layout")
local Draw = require("src.view.draw")
local Assets = require("src.view.assets")
local Shots = require("src.core.shots")
local Court = require("src.core.court")

local DecisionUI = {}
DecisionUI.__index = DecisionUI

local C = Layout.colors
local T = Layout.targets

function DecisionUI.new(cam)
  local self = setmetatable({}, DecisionUI)
  self.cam = cam
  self.mode = "target"     -- "target" | "recovery"
  self.hover = nil
  self.selected = nil
  self.mouse = { x = 0, y = 0 }
  self.decisionRef = nil
  return self
end

function DecisionUI:reset()
  self.mode, self.hover, self.selected = "target", nil, nil
end

-- Screen geometry for an option's ground ring and floating bubble.
function DecisionUI:geom(o)
  local cam = self.cam
  local gx, gy, s = cam:project(o.pos.x, o.pos.y, 0)
  local bx, by = cam:project(o.pos.x, o.pos.y, T.bubbleHeight)
  bx = bx + (o.pos.x >= 0 and 1 or -1) * T.bubbleOffsetX
  return {
    gx = gx, gy = gy, s = s,
    bx = math.floor(bx - T.bubbleW / 2), by = math.floor(by - T.bubbleH / 2),
    px = bx, py = by,
  }
end

function DecisionUI:_hitTest(rally, mx, my)
  for i, o in ipairs(rally.decision.options) do
    local g = self:geom(o)
    if mx >= g.bx and mx <= g.bx + T.bubbleW and my >= g.by and my <= g.by + T.bubbleH then return i end
    local rx, ry = T.ringRadius * g.s * 1.3, T.ringRadius * g.s * 0.6
    local dx, dy = (mx - g.gx) / rx, (my - g.gy) / ry
    if dx * dx + dy * dy <= 1 then return i end
  end
  return nil
end

function DecisionUI:_recoverySpot(rally, option)
  local d = rally.decision
  local g = self.cam:unproject(self.mouse.x, self.mouse.y)
  if not g then return Court.basePos(rally.players[d.hitterKey].side) end
  return rally:clampRecovery(option, g)
end

function DecisionUI:update(rally, mx, my, forced)
  if rally.decision ~= self.decisionRef then
    self.decisionRef = rally.decision
    self:reset()
  end
  self.mouse.x, self.mouse.y = mx, my
  if self.mode == "target" then
    self.hover = self:_hitTest(rally, mx, my)
    if forced and forced.hover then self.hover = forced.hover end
  end
end

function DecisionUI:mousepressed(rally, x, y, button)
  if button == 2 then
    if self.mode == "recovery" then self.mode = "target"; self.selected = nil end
    return
  end
  if button ~= 1 then return end
  if self.mode == "target" then
    local i = self:_hitTest(rally, x, y)
    if i and not rally.decision.options[i].disabled then
      self.selected = i
      self.mode = "recovery"
    end
  else
    local o = rally.decision.options[self.selected]
    rally:commit(self.selected, self:_recoverySpot(rally, o))
  end
end

function DecisionUI:keypressed(rally, key)
  if self.mode == "recovery" and key == "space" then
    local hitter = rally.players[rally.decision.hitterKey]
    rally:commit(self.selected, Court.basePos(hitter.side))
  elseif key == "escape" and self.mode == "recovery" then
    self.mode = "target"; self.selected = nil
  end
end

-- Force UI state from dev flags (screenshots).
function DecisionUI:force(rally, forced)
  if forced.pick and rally.decision.options[forced.pick] then
    self.selected = forced.pick
    self.mode = "recovery"
  end
end

---------------------------------------------------------------------------- drawing

local function drawRing(cam, pos, r, filled)
  local pts = cam:groundCircle(pos.x, pos.y, r, 24)
  if filled then love.graphics.polygon("fill", pts) end
  love.graphics.polygon("line", pts)
end

function DecisionUI:_drawTrajectory(rally, o)
  local d = rally.decision
  local path = {
    from = d.from, h0 = d.contactH, to = o.pos,
    h1 = Shots.contactHeight(Court.depthOf(o.pos), "ontime"), apex = o.eval.def.apex,
  }
  Draw.color(C.text, 0.7)
  for i = 1, 19 do
    local p = rally:pathPoint(path, i / 20)
    local x, y = self.cam:project(p.pos.x, p.pos.y, p.h)
    love.graphics.rectangle("fill", math.floor(x), math.floor(y), 1, 1)
  end
end

function DecisionUI:_drawRecoveryCircle(rally, o, strong)
  local d = rally.decision
  local side = rally.players[d.hitterKey].side
  local cam = self.cam
  -- clip to the hitter's own half (where they are allowed to recover)
  love.graphics.stencil(function()
    local a = Court.HALF_WIDTH_SINGLES
    local y1, y2 = side * 0.4, side * (Court.LENGTH + 0.3)
    local p = {}
    for _, c in ipairs({ { -a, y1 }, { a, y1 }, { a, y2 }, { -a, y2 } }) do
      local x, y = cam:project(c[1], c[2], 0)
      p[#p + 1] = x; p[#p + 1] = y
    end
    love.graphics.polygon("fill", p)
  end, "replace", 1)
  love.graphics.setStencilTest("greater", 0)
  Draw.color(C.recovery, strong and 0.18 or 0.08)
  local pts = cam:groundCircle(d.from.x, d.from.y, math.max(0.05, o.recoveryRadius), 48)
  love.graphics.polygon("fill", pts)
  Draw.color(C.recovery, strong and 0.9 or 0.5)
  Draw.dashed(pts, true)
  love.graphics.setStencilTest()
end

-- Ground layer: drawn under athletes.
function DecisionUI:drawGround(rally)
  local d = rally.decision
  for i, o in ipairs(d.options) do
    local col = o.disabled and C.disabled or Draw.successColor(o.eval.success)
    local active = (i == self.hover and self.mode == "target") or i == self.selected
    Draw.color(col, active and 0.35 or 0.12)
    drawRing(self.cam, o.pos, T.ringRadius, true)
  end

  local o = d.options[self.selected or self.hover or 0]
  if o and not o.disabled then
    self:_drawRecoveryCircle(rally, o, self.mode == "recovery")
  end
end

-- Overlay layer: bubbles, preview, tooltip.
function DecisionUI:drawOverlay(rally)
  local d = rally.decision
  local cam = self.cam
  local focus = d.options[self.selected or self.hover or 0]
  if focus and not focus.disabled then self:_drawTrajectory(rally, focus) end

  -- bubbles with pins
  for i, o in ipairs(d.options) do
    local g = self:geom(o)
    local col = o.disabled and C.disabled or Draw.successColor(o.eval.success)
    local active = (i == self.hover and self.mode == "target") or i == self.selected
    local dim = self.mode == "recovery" and i ~= self.selected
    Draw.color(col, dim and 0.3 or 0.9)
    love.graphics.line(g.gx, g.gy, g.px, g.by + T.bubbleH)
    Draw.color(C.panel, dim and 0.4 or 0.95)
    love.graphics.rectangle("fill", g.bx, g.by, T.bubbleW, T.bubbleH, 3, 3)
    Draw.color(col, dim and 0.3 or 1)
    love.graphics.setLineWidth(active and 2 or 1)
    love.graphics.rectangle("line", g.bx + 0.5, g.by + 0.5, T.bubbleW - 1, T.bubbleH - 1, 3, 3)
    love.graphics.setLineWidth(1)
    local label = o.disabled and "--" or string.format("%d%%", math.floor(o.eval.success * 100 + 0.5))
    if not dim then
      Draw.text(label, g.bx, g.by + 1, col, Assets.fonts.normal, "center", T.bubbleW)
    end
  end

  -- recovery ghost
  if self.mode == "recovery" then
    local o = d.options[self.selected]
    local spot = self:_recoverySpot(rally, o)
    local hitter = rally.players[d.hitterKey]
    local fx, fy = cam:project(d.from.x, d.from.y, 0)
    local sx, sy = cam:project(spot.x, spot.y, 0)
    Draw.color(C.recovery, 0.9)
    Draw.dashed({ fx, fy, sx, sy }, false)
    local CourtView = require("src.view.court_view")
    CourtView.drawAthlete(cam, { pos = spot, side = hitter.side }, C.recovery, 0.45)
    Draw.color(C.recovery)
    love.graphics.line(sx - 3, sy - 3, sx + 3, sy + 3)
    love.graphics.line(sx - 3, sy + 3, sx + 3, sy - 3)
  end

  -- timing badge over the hitter
  local hitter = rally.players[d.hitterKey]
  if d.timing ~= "ontime" then
    local x, y = cam:project(hitter.pos.x, hitter.pos.y, Layout.actor.bodyHeight + 0.9)
    local tm = Shots.data.timing[d.timing]
    local col = d.timing == "late" and C.bad or C.good
    Draw.text(string.format("%s %+d%%", tm.label:upper(), math.floor(tm.success * 100 + 0.5)),
      x - 40, y, col, Assets.fonts.normal, "center", 80)
  end

  if self.mode == "target" and self.hover then self:_drawTooltip(rally, d.options[self.hover]) end
end

function DecisionUI:_drawTooltip(rally, o)
  local tt = Layout.tooltip
  local font = Assets.fonts.normal
  local ev = o.eval
  local lines = {}
  local function add(l, r, col) lines[#lines + 1] = { l = l, r = r, col = col } end

  add(ev.name .. " > " .. o.label, nil, C.text)
  for i, row in ipairs(ev.breakdown) do
    local v = math.floor(row.value * 100 + (row.value >= 0 and 0.5 or -0.5))
    local col = (i == 1 or v == 0) and C.textDim or (v > 0 and C.good or C.bad)
    add(row.label, i == 1 and string.format("%d%%", v) or string.format("%+d%%", v), col)
  end
  add("-", nil)
  add("Success", string.format("%d%%", math.floor(ev.success * 100 + 0.5)), Draw.successColor(ev.success))
  add(string.format("Flight %.2fs", ev.flight), string.format("Recover %.1fm", o.recoveryRadius), C.textDim)
  local st = o.receiverState
  local stCol = (st == "winner" or st == "late") and C.good or (st == "early" and C.bad or C.ok)
  add("Opponent", string.format("%s (%+.2fs)", Shots.REACH_LABEL[st], o.receiverSlack), stCol)
  if o.disabled then add(o.disabled, nil, C.bad) end

  local w = tt.width
  local h = tt.padding * 2 + #lines * tt.lineH
  -- Fixed panel beside the far court, on the side away from the hovered target,
  -- so it never covers the other targets or the opponent.
  local x = (o.pos.x < 0) and tt.rightX or tt.leftX
  local y = tt.y

  Draw.panel(x, y, w, h)
  for i, ln in ipairs(lines) do
    local ly = y + tt.padding + (i - 1) * tt.lineH
    if ln.l == "-" then
      Draw.color(C.textDim, 0.6)
      love.graphics.line(x + tt.padding, ly + tt.lineH / 2, x + w - tt.padding, ly + tt.lineH / 2)
    else
      Draw.text(ln.l, x + tt.padding, ly, ln.col, font)
      if ln.r then Draw.text(ln.r, x + tt.padding, ly, ln.col, font, "right", w - tt.padding * 2) end
    end
  end
end

return DecisionUI
