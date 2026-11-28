-- Tournament: the draw for this league's event, your next opponent, and the way back.
--   Bracket (left)   every round's matches; you in blue, winners bright, your path marked.
--   Preview (right)  you vs this round's opponent, stat by stat, then Play match.
-- Your matches are real matches (src/scenes/match.lua); the rest of each round is decided
-- from ratings (src/core/tournament.lua). When it's over: Continue -> promotion or the hub.
-- Withdraw (button, or Esc) before your first match: back to the hub, nothing recorded.
local Layout = require("src.config.layout")
local Progress = require("src.data.progress")
local Draw = require("src.view.draw")
local Assets = require("src.view.assets")
local Emblem = require("src.view.emblem")
local Avatar = require("src.view.avatar")
local Career = require("src.core.career")
local Tournament = require("src.core.tournament")

local TT = Layout.tournament
local C = Layout.colors
local ACCENT = Layout.hub.accent

local Scene = {}
Scene.__index = Scene

local function inside(r, x, y) return x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h end

function Scene.new(app, params)
  local self = setmetatable({ app = app }, Scene)
  self.career = app.career
  self.t = self.career.tournament or Career.enter(self.career)
  self.last = params.last          -- { won, score } of the match you just played
  for _ = 1, params.wins or 0 do       -- dev (--open bracket:N): you have won N matches already
    if not self.t.over then Tournament.report(self.t, true, "5-3") end
  end
  if app.dev.player then self.selected = self.t.field[1][app.dev.player] end   -- dev: --player K looks up seed K
  self.button = { x = TT.previewX + (TT.previewW - TT.buttonW) / 2, y = TT.buttonY, w = TT.buttonW, h = TT.buttonH }
  -- before your first match you can still back out (nothing is recorded)
  self.withdrawButton = { x = TT.previewX + (TT.previewW - TT.withdrawW) / 2, y = TT.buttonY + TT.buttonH + 6,
                          w = TT.withdrawW, h = TT.withdrawH }
  self.time = 0
  return self
end

function Scene:update(dt)
  self.time = self.time + dt
  self.hot = inside(self.button, self.app.mouse.x, self.app.mouse.y)
  self.hotWithdraw = self:_canWithdraw() and inside(self.withdrawButton, self.app.mouse.x, self.app.mouse.y)
  self.hoverPlayer = nil
  for _, h in ipairs(self.hits or {}) do
    if inside(h, self.app.mouse.x, self.app.mouse.y) then self.hoverPlayer = h.p end
  end
  love.mouse.setCursor((self.hot or self.hotWithdraw or self.hoverPlayer) and love.mouse.getSystemCursor("hand") or nil)
  if self.app.dev.autoplay and self.time > 1 then     -- dev: move on by itself
    if self.t.over then
      print(string.format("[autoplay] %s over: %s", self.t.name, self.t.won and "won" or "lost round " .. self.t.lostRound))
      self:_continue()
    else
      print(string.format("[autoplay] %s %s vs %s", self.t.name, Tournament.roundName(self.t.rounds, self.t.round),
        Tournament.opponent(self.t).name))
      self:_play()
    end
  end
end

function Scene:_play()
  local t, c, app = self.t, self.career, self.app
  local opp = Tournament.opponent(t)
  app:switch("match", {
    near = Career.athleteDef(c), far = opp, points = Career.data.match.points, cap = Career.data.match.cap,
    onDone = function(won, score)
      Tournament.report(t, won, score)
      app:switch("tournament", { last = { won = won, score = score, opp = opp } })
    end,
  })
end

function Scene:_continue()
  local res = Career.finish(self.career)
  if res and (res.promoted or res.champion) then self.app:switch("promotion", res)
  else self.app:switch("hub") end
end

function Scene:_canWithdraw() return not self.t.over and self.t.round == 1 and not self.t.results[1] end

function Scene:_withdraw()
  self.career.tournament = nil
  self.app:switch("hub")
end

function Scene:mousepressed(x, y, button)
  if button ~= 1 then return end
  if inside(self.button, x, y) then
    if self.t.over then self:_continue() else self:_play() end
  elseif self.hotWithdraw then
    self:_withdraw()
  elseif self.hoverPlayer then
    -- look someone up; them again (or yourself) goes back to your opponent
    local p = self.hoverPlayer
    self.selected = (p.you or p == self.selected) and nil or p
  end
end

function Scene:keypressed(key)
  if key == "return" or key == "space" then
    if self.t.over then self:_continue() else self:_play() end
  elseif key == "escape" and self:_canWithdraw() then
    self:_withdraw()
  end
end

---------------------------------------------------------------------------- drawing
-- The draw as a mirrored tree (half the field on each side, the final in the middle):
--   round 1      pills with a portrait and the name; knocked out = dimmed
--   later rounds portraits only (who got through), dashed seats where nobody is yet
--   centre       FINAL tag on the line joining the two finalists, the champion's seat above
-- Lines light up along each winner's way through; yours in your blue. Sizes adapt to the
-- draw (4 .. 32): rows share the height, later-round columns squeeze before the pills do.
function Scene:_drawBracket()
  local t = self.t
  local x0, y0, W, H = TT.bracketX, TT.bracketY, TT.bracketW, TT.bracketH
  Draw.panel(x0 - 6, y0 - 6, W + 12, H + 12)
  local font = Assets.fonts.small
  local R = t.rounds
  local half = t.size / 2
  local S = (W - TT.centerW) / 2                       -- one side's width
  local colW = math.min(TT.headColW, (S - TT.minPillW - 8) / math.max(1, R - 1))
  local pillW = math.min(TT.maxPillW, S - (R - 1) * colW - 8)
  local avail = H - 16
  local rowH = math.min(TT.maxRowH, avail / half)       -- small draws: rows stay together, centred
  local top = y0 + 8 + (avail - rowH * half) / 2
  local pillH = math.max(9, math.min(TT.maxPillH, rowH - 3))
  local pr = math.max(3, math.min(10, pillH / 2 - 2))  -- portrait radius in a pill
  local hr = math.max(4, math.min(10, rowH - 2, colW / 2 - 2))   -- later-round portrait radius
  local cx = x0 + W / 2
  local pulse = 0.6 + 0.4 * math.sin(self.time * 4)
  local opp = not t.over and Tournament.opponent(t)
  local sel = self.selected
  self.hits = {}                                       -- clickable players (rect + player), for update/click
  local function hit(x, y, w, h, p) if p then self.hits[#self.hits + 1] = { x = x, y = y, w = w, h = h, p = p } end end
  -- everyone knocked out so far (dimmed wherever they appear)
  local out = {}
  for _, round in pairs(t.results) do
    for _, m in ipairs(round) do out[m.winner == m.a and m.b or m.a] = true end
  end

  -- column c (0 = round 1) entry j on a side: centre y, and x of its left / right edge
  local function ey(c, j) return top + (j - 0.5) * rowH * 2 ^ c end
  local function ex(c, side)                            -- side -1 left, 1 right: inner x (toward the centre)
    if c == 0 then
      return side < 0 and x0 + pillW or x0 + W - pillW
    end
    local cxL = x0 + pillW + (c - 0.5) * colW + 4
    return side < 0 and cxL or x0 + W - (cxL - x0)
  end
  local function playerAt(c, side, j)                  -- field[c+1], split into halves
    local f = t.field[c + 1]
    if not f then return nil end
    local n = #f / 2
    return f[(side < 0 and 0 or n) + j]
  end
  local function lineCol(p) return p and (p.you and C.near or C.text) or { 0.35, 0.37, 0.42 } end

  for _, side in ipairs({ -1, 1 }) do
    -- connectors: each pair in column c joins at the entry in column c + 1
    for c = 0, R - 2 do
      local n = half / 2 ^ c
      for j = 1, n, 2 do
        local yA, yB, yP = ey(c, j), ey(c, j + 1), ey(c + 1, (j + 1) / 2)
        local xA = ex(c, side) + (c == 0 and 0 or -side * -hr)
        if c > 0 then xA = ex(c, side) - side * hr end
        local xP = ex(c + 1, side) + side * hr
        local mx = (xA + xP) / 2
        local winner = playerAt(c + 1, side, (j + 1) / 2)
        for k, yC in ipairs({ yA, yB }) do
          local p = playerAt(c, side, j + k - 1)
          local on = winner and p == winner
          Draw.color(on and lineCol(p) or C.textDim, on and 0.9 or 0.25)
          love.graphics.line(xA, yC, mx, yC, mx, yP)
        end
        Draw.color(winner and lineCol(winner) or C.textDim, winner and 0.9 or 0.25)
        love.graphics.line(mx, yP, xP, yP)
      end
    end
    -- round 1 pills
    for j = 1, half do
      local p = playerAt(0, side, j)
      local x = side < 0 and x0 or x0 + W - pillW
      local y = ey(0, j) - pillH / 2
      local a = out[p] and 0.4 or 1
      Draw.color(p and p.you and { 0.16, 0.26, 0.42 } or { 0.17, 0.20, 0.27 }, a)
      love.graphics.rectangle("fill", x, y, pillW, pillH, pillH / 2, pillH / 2)
      hit(x, y, pillW, pillH, p)
      local ring = (p == sel and C.text) or ((p and p.you) and C.near or ((p == opp) and ACCENT or nil))
      if ring then
        Draw.color(ring, (p == opp and p ~= sel) and pulse or 1)
        love.graphics.rectangle("line", x + 0.5, y + 0.5, pillW - 1, pillH - 1, pillH / 2, pillH / 2)
      end
      local ax = side < 0 and x + pillH / 2 or x + pillW - pillH / 2
      Avatar.draw(p, ax, y + pillH / 2, pr, a)
      local tx = side < 0 and x + pillH + 1 or x + 3
      local tw = pillW - pillH - 4
      local name = p.name
      while #name > 1 and font:getWidth(name) > tw do name = name:sub(1, -2) end
      Draw.text(name, tx, y + math.floor((pillH - 10) / 2) + 1, out[p] and { 0.42, 0.44, 0.50 } or (p.you and C.near or C.text), font,
        side < 0 and "left" or "right", tw)
    end
    -- later rounds: who got through (portraits), dashed seats for the rest
    for c = 1, R - 1 do
      for j = 1, half / 2 ^ c do
        local p = playerAt(c, side, j)
        local x, y = ex(c, side), ey(c, j)
        if p then
          hit(x - hr, y - hr, hr * 2, hr * 2, p)
          Avatar.draw(p, x, y, hr, out[p] and 0.4 or 1, p == sel and C.text or (p.you and C.near or (p == opp and ACCENT or nil)))
        else
          Avatar.empty(x, y, hr)
        end
      end
    end
  end

  -- the final: the two finalists' line through the centre, its tag, the champion's seat above
  local fy = ey(R - 1, 1)
  local fL, fR = ex(R - 1, -1) + hr, ex(R - 1, 1) - hr
  local champ = t.field[R + 1] and t.field[R + 1][1]
  Draw.color(champ and lineCol(champ) or C.textDim, champ and 0.9 or 0.25)
  love.graphics.line(fL, fy, fR, fy)
  local cr = math.min(12, hr + 4)
  local cy = fy - cr - 22
  love.graphics.line(cx, fy - 7, cx, cy + cr)
  local tw = font:getWidth("FINAL") + 10
  Draw.color({ 0.20, 0.24, 0.32 })
  love.graphics.rectangle("fill", cx - tw / 2, fy - 7, tw, 13, 6, 6)
  Draw.color(t.round == R and not t.over and ACCENT or C.textDim)
  love.graphics.rectangle("line", cx - tw / 2 + 0.5, fy - 6.5, tw - 1, 12, 6, 6)
  Draw.sign("FINAL", cx - tw / 2, fy - 7, tw, 13, t.round == R and not t.over and ACCENT or C.text, font)
  if champ then
    hit(cx - cr, cy - cr, cr * 2, cr * 2, champ)
    Avatar.draw(champ, cx, cy, cr, 1, champ == sel and C.text or ACCENT)
  else
    Avatar.empty(cx, cy, cr, ACCENT, 0.6)
  end
  -- trophy over the champion's seat
  local ty = cy - cr - 4
  Draw.color(Layout.training.colors.trophy)
  love.graphics.arc("fill", cx, ty - 9, 6, 0, math.pi)
  love.graphics.rectangle("fill", cx - 6, ty - 12, 12, 3)
  love.graphics.rectangle("fill", cx - 1, ty - 4, 2, 3)
  love.graphics.rectangle("fill", cx - 4, ty - 1, 8, 2)
  if champ then Draw.text(champ.name, cx - 50, ty - 26, champ.you and C.near or C.text, font, "center", 100) end
end

local GROUPS = {
  { "Technique", { "clear", "lift", "drop", "net", "drive", "smash" } },
  { "Physical", { "power", "speed", "legs", "stamina" } },
  { "Movement", { "reach", "reaction", "recovery" } },
}

function Scene:_drawPreview(you, opp)
  local x, y, w = TT.previewX, TT.previewY, TT.previewW
  Draw.panel(x - 6, y - 6, w + 12, TT.previewH + 12)
  local font = Assets.fonts.small
  -- who: portrait and name (no overall number: you learn how good they are by playing them) (bars below: blue you, red them)
  for i, p in ipairs({ you, opp }) do
    local px = i == 1 and x or x + w / 2 + 4
    Avatar.draw(p, px + 7, y + 8, 7, 1, i == 1 and C.near or C.far)
    Draw.text(p.name, px + 18, y + 4, C.text, font)
  end
  y = y + 20
  local barX, unit = x + 70, 12
  for _, g in ipairs(GROUPS) do
    Draw.text(g[1], x, y, C.textDim, font)
    y = y + 10
    for _, k in ipairs(g[2]) do
      local v, o = you.stats[k], opp.stats[k]
      local col = v > o + 0.05 and C.good or (v < o - 0.05 and C.bad or C.textDim)
      Draw.text(Progress.name(k), x + 6, y, C.textDim, font)
      Draw.text(string.format("%g", v), x + 44, y, col, font, "right", 22)
      Draw.color(C.near, 0.85)
      love.graphics.rectangle("fill", barX, y + 2, v * unit, 5)
      Draw.color(C.far)
      love.graphics.rectangle("fill", barX + o * unit - 1, y, 2, 9)
      Draw.color(C.textDim, 0.25)
      love.graphics.rectangle("line", barX + 0.5, y + 1.5, 10 * unit, 6)
      y = y + 10
    end
    y = y + 2
  end
end

function Scene:draw()
  local t, c = self.t, self.career
  local W = Layout.width
  love.graphics.clear(Layout.colors.bg)
  Emblem.draw(t.level, 30, TT.headerY + 20, 18)
  Draw.text(t.name, 56, TT.headerY + 2, C.text, Assets.fonts.big)
  local sub = string.format("%d players  -  win %d matches to move up a league", t.size, t.rounds)
  if t.level == #Career.data.events then sub = string.format("%d players  -  win %d matches to be World Champion", t.size, t.rounds) end
  Draw.text(sub, 56, TT.headerY + 28, C.textDim, Assets.fonts.small)
  self:_drawBracket()

  local you = Career.athleteDef(c)
  local font = Assets.fonts.normal
  local label
  local look = self.selected or (not t.over and Tournament.opponent(t))   -- who the panel compares you with
  if t.over and look then self:_drawPreview(you, look) end
  if t.over then
    local last = t.won and "Champion!" or ("Out in " .. (t.lostRound == t.rounds and "the final" or "round " .. t.lostRound))
    if not look then          -- nobody picked: how it ended
      Draw.panel(TT.previewX - 6, TT.previewY - 6, TT.previewW + 12, TT.previewH + 12)
      Draw.text(last, TT.previewX, TT.previewY + 40, t.won and C.good or C.bad, Assets.fonts.big, "center", TT.previewW)
      if self.last then
        Draw.text(string.format("%s vs %s  %s", you.name, self.last.opp.name, self.last.score), TT.previewX,
          TT.previewY + 70, C.textDim, Assets.fonts.small, "center", TT.previewW)
      end
      if not t.won then
        Draw.text(t.champion.name .. " won the title", TT.previewX, TT.previewY + 90, C.textDim, Assets.fonts.small,
          "center", TT.previewW)
        Draw.text("Train up and enter again any time.", TT.previewX, TT.previewY + 120, C.text, Assets.fonts.small,
          "center", TT.previewW)
      end
    end
    label = "Continue"
  else
    self:_drawPreview(you, look)
    Draw.text(Tournament.roundName(t.rounds, t.round), TT.previewX, TT.buttonY - 16, ACCENT, font, "center", TT.previewW)
    if self.last then
      Draw.text(string.format("Won %s vs %s", self.last.score, self.last.opp.name), 0, TT.headerY + 4, C.good,
        Assets.fonts.small, "right", W - 16)
    end
    label = "Play match"
  end
  local b = self.button
  Draw.color(C.panel); love.graphics.rectangle("fill", b.x, b.y, b.w, b.h)
  Draw.color(ACCENT, self.hot and 1 or 0.6 + 0.3 * math.sin(self.time * 3))
  love.graphics.rectangle("line", b.x + 0.5, b.y + 0.5, b.w - 1, b.h - 1)
  Draw.text(label, b.x, b.y + 6, self.hot and C.text or ACCENT, font, "center", b.w)
  if self:_canWithdraw() then
    local w = self.withdrawButton
    Draw.text("Withdraw", w.x, w.y + 3, self.hotWithdraw and C.text or C.textDim, Assets.fonts.small, "center", w.w)
    if self.hotWithdraw then
      Draw.color(C.textDim)
      love.graphics.rectangle("line", w.x + 0.5, w.y + 0.5, w.w - 1, w.h - 1)
    end
  end
end

return Scene
