-- The frozen-at-contact UI: pick a target (success % bubbles, breakdown tooltip, landing
-- spread, flight path), then pick a recovery spot inside the reachable area.
local Layout = require("src.config.layout")
local Draw = require("src.view.draw")
local Assets = require("src.view.assets")
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
    if forced and forced.hover and rally.decision.options[forced.hover] then self.hover = forced.hover end
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

-- Path color = how long the shuttle takes to land: fast (hard) shots one color,
-- slow (floaty) shots the other, blended in between. No reading of the opponent.
function DecisionUI.flightColor(t)
  local fc = Layout.flightColors
  local u = math.max(0, math.min(1, (t - fc.fastTime) / (fc.slowTime - fc.fastTime)))
  local a, b = fc.fast, fc.mid
  if u > 0.5 then a, b, u = fc.mid, fc.slow, u - 0.5 end
  u = u * 2
  return { a[1] + (b[1] - a[1]) * u, a[2] + (b[2] - a[2]) * u, a[3] + (b[3] - a[3]) * u }
end

function DecisionUI:_drawPath(o)
  local path = o.eval.path
  if not path then return end
  Draw.color(DecisionUI.flightColor(o.eval.flight), 0.95)
  for i = 2, #path - 1, 2 do
    local p = path[i]
    local x, y = self.cam:project(p.x, p.y, p.h)
    love.graphics.rectangle("fill", math.floor(x), math.floor(y), 2, 2)
  end
end

function DecisionUI:_drawLandings(o)
  local l = o.eval.landings
  if not l then return end
  Draw.color(Draw.successColor(o.eval.success), 0.7)
  for i = 1, #l, 6 do
    local x, y = self.cam:project(l[i].x, l[i].y, 0)
    love.graphics.rectangle("fill", math.floor(x), math.floor(y), 1, 1)
  end
end

-- Reachable recovery area (a circle on the ground), clipped to own half.
function DecisionUI:_drawRecoveryArea(rally, o, strong)
  local d = rally.decision
  local hitter = rally.players[d.hitterKey]
  local cam = self.cam
  local c = hitter.pos
  local r = math.max(0.05, hitter:recoveryRadius(o.recoverTime, o.recoverPause))
  local pts = cam:groundCircle(c.x, c.y, r, 48)
  love.graphics.stencil(function()
    local a = Court.HALF_WIDTH_SINGLES
    local y1, y2 = hitter.side * 0.4, hitter.side * (Court.LENGTH + 0.3)
    local p = {}
    for _, q in ipairs({ { -a, y1 }, { a, y1 }, { a, y2 }, { -a, y2 } }) do
      local x, y = cam:project(q[1], q[2], 0)
      p[#p + 1] = x; p[#p + 1] = y
    end
    love.graphics.polygon("fill", p)
  end, "replace", 1)
  love.graphics.setStencilTest("greater", 0)
  Draw.color(C.recovery, strong and 0.18 or 0.08)
  local ok = pcall(love.graphics.polygon, "fill", pts)
  if not ok then love.graphics.polygon("line", pts) end
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
    self:_drawRecoveryArea(rally, o, self.mode == "recovery")
    self:_drawLandings(o)
  end
end

local CONTACT_LABEL = { early = "EARLY", ontime = nil, stretched = "STRETCHED" }

-- Overlay layer: bubbles, path, tooltip.
function DecisionUI:drawOverlay(rally)
  local d = rally.decision
  local cam = self.cam
  local focus = d.options[self.selected or self.hover or 0]
  if focus and not focus.disabled then self:_drawPath(focus) end

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

  local hitter = rally.players[d.hitterKey]
  if self.mode == "recovery" then
    local o = d.options[self.selected]
    local spot = self:_recoverySpot(rally, o)
    local fx, fy = cam:project(hitter.pos.x, hitter.pos.y, 0)
    local sx, sy = cam:project(spot.x, spot.y, 0)
    Draw.color(C.recovery, 0.9)
    Draw.dashed({ fx, fy, sx, sy }, false)
    local CourtView = require("src.view.court_view")
    CourtView.drawAthlete(cam, { pos = spot, side = hitter.side }, C.recovery, 0.45)
    Draw.color(C.recovery)
    love.graphics.line(sx - 3, sy - 3, sx + 3, sy + 3)
    love.graphics.line(sx - 3, sy + 3, sx + 3, sy - 3)
  end

  -- contact badge over the hitter
  local ct = d.contact
  local label = CONTACT_LABEL[ct.state]
  local x, y = cam:project(hitter.pos.x, hitter.pos.y, require("src.core.body").MAX_REACH + 0.4)
  if label then
    if ct.state == "stretched" then label = string.format("%s %d%%", label, math.floor(ct.stretch * 100 + 0.5)) end
    Draw.text(label, x - 50, y, ct.state == "early" and C.good or C.bad, Assets.fonts.normal, "center", 100)
    y = y - 11
  end
  if hitter.offBalance >= 0.05 then
    Draw.text(string.format("OFF BALANCE %d%%", math.floor(hitter.offBalance * 100 + 0.5)), x - 60, y,
      C.bad, Assets.fonts.normal, "center", 120)
  end

  local hovered = self.mode == "target" and self.hover and d.options[self.hover]
  if hovered then self:_drawTooltip(rally, hovered) end
end

local RECEIVER = { winner = "Can't reach", stretched = "Stretched", ontime = "On time", early = "Comfortable" }

function DecisionUI:_drawTooltip(rally, o)
  local tt = Layout.tooltip
  local font = Assets.fonts.normal
  local ev = o.eval
  local lines = {}
  local function add(l, r, col) lines[#lines + 1] = { l = l, r = r, col = col } end
  local function pct(p) return string.format("%d%%", math.floor(p * 100 + 0.5)) end

  add(ev.name .. " > " .. o.label, nil, C.text)
  for _, f in ipairs(ev.factors) do
    local col = f.effect == "good" and C.good or (f.effect == "bad" and C.bad or C.textDim)
    add(f.label, f.value, col)
  end
  add("-", nil)
  if o.disabled then
    add(o.disabled, nil, C.bad)
  else
    local risk = string.format("Net %s  Long %s  Wide %s", pct(ev.pNet), pct(ev.pLong), pct(ev.pWide))
    if (ev.pShort or 0) > 0 then risk = risk .. "  Short " .. pct(ev.pShort) end
    add(risk, nil, C.textDim)
    add("Success", pct(ev.success), Draw.successColor(ev.success))
    add(string.format("Flight %.2fs  %.1fm", ev.flight, ev.distance),
      string.format("Over net %+.2fm", ev.overNet), C.textDim)
    add(string.format("Recovery pause %.2fs", o.recoverPause),
      string.format("then %.2fs", math.max(0, o.recoverTime - o.recoverPause)), C.textDim)
    local a = o.receiver
    local st = RECEIVER[a.state]
    if a.state == "stretched" then st = string.format("%s %d%%", st, math.floor(a.stretch * 100 + 0.5)) end
    local col = (a.state == "winner" or a.state == "stretched") and C.good or (a.state == "early" and C.bad or C.ok)
    add("Opponent reach", st, col)
    local recv = rally.players[rally.decision.hitterKey == "near" and "far" or "near"]
    if recv.offBalance >= 0.05 then
      add("Opponent off balance", pct(recv.offBalance), C.good)
    end
  end

  local w = tt.width
  local h = tt.padding * 2 + #lines * tt.lineH
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
