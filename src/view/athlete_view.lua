-- Athlete page (full screen, from the hub's Athlete button), on the game's 640 x 360 pixel
-- canvas like everything else. Stats as what they do on court, kept light: pictures only
-- for the stat you are looking at:
--   left   compact rows, body then shots: level, one reading, reps bar
--   right  the picked stat: practice courts now vs next level (shots) or the reading now vs
--          next (body), the next unlock, the 10-level track, reps and what trains it
-- Readings come from the real curves (power -> smash km/h, footwork -> m/s, legs -> lunge;
-- stamina is a placeholder); shots are 20 practice shots flown by the real shot model.
-- No overall rating anywhere: you find out how good you are by playing.
local Layout = require("src.config.layout")
local Draw = require("src.view.draw")
local Assets = require("src.view.assets")
local Emblem = require("src.view.emblem")
local Avatar = require("src.view.avatar")
local Curve = require("src.core.curve")
local Training = require("src.core.training")
local Career = require("src.core.career")
local Athletes = require("src.data.athletes")
local Stats = require("src.data.stats")
local Progress = require("src.data.progress")

local AV = {}
AV.__index = AV

local A = Layout.hub.athlete
local C = Layout.colors
local ACCENT = Layout.hub.accent
local TD = Training.data
local BG = { 0.07, 0.08, 0.11 }
local ROW = { 0.12, 0.14, 0.19 }
local ROW_HOT = { 0.17, 0.20, 0.27 }
local FAINT = { 0.42, 0.45, 0.52 }
local COURT = { 0.12, 0.43, 0.34 }
local HW, SW, LEN = 3.05, 2.59, 6.7

local BODY = { "power", "speed", "legs", "stamina" }
local SHOTS = { "clear", "lift", "drop", "net", "drive", "smash" }
local isShot = {}
for _, k in ipairs(SHOTS) do isShot[k] = true end
local function label(k) local n = Progress.name(k); return n:sub(1, 1):upper() .. n:sub(2) end
local function inside(r, x, y) return r and x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h end

-- deterministic rng so the clouds stay put between frames and visits
local function lcg(seed)
  local s = seed
  return function() s = (s * 16807) % 2147483647; return s / 2147483647 end
end

function AV.new(career)
  return setmetatable({ career = career, cache = {}, pick = "power" }, AV)
end

---------------------------------------------------------------------------- readings
-- The body reading at a level: value, note.
local function bodyReading(k, lv)
  if k == "power" then
    return string.format("%d km/h", math.floor(Curve.at(Stats.power, lv) * 3.6 + 0.5)), "top smash speed"
  elseif k == "speed" then
    local fs = Curve.at(Stats.firstStep, lv)
    return string.format("%.1f m/s", Curve.at(Stats.speed, lv)),
      fs < 0.1 and "no split-step yet" or string.format("split-step push-off %.1f m/s", fs)
  elseif k == "legs" then
    local r = Curve.at(Stats.reach, lv)
    return r < 0.05 and "no lunge" or string.format("lunge +%d cm", math.floor(r * 100 + 0.5)),
      string.format("%.1f s back up after a full lunge", Curve.at(Stats.stretchPause, lv))
  elseif k == "stamina" then
    return string.format("~%d shots", math.floor(Curve.at(Progress.staminaShots, lv) + 0.5)), "of hard rallying before tiring"
  end
end

-- Practice shots of a technique at a level (cached): his stats with that skill set to lv.
function AV:practice(k, lv, n)
  local key = k .. lv .. ":" .. n
  if not self.cache[key] then
    local st = Career.stats(self.career)
    st[Training.data.shots[k].shot] = lv
    -- same draws at every level (seeded by the shot only): a better level only shakes less
    local p = Training.practice(st, k, n, lcg(1000 + #k * 131))
    if not p.available then
      -- not strong enough to play it at all: the Power level that makes it playable
      for pw = st.power + 1, 10 do
        local st2 = {}
        for s, v in pairs(st) do st2[s] = v end
        st2.power = pw
        if Training.practice(st2, k, 1, lcg(1)).available then p.needPower = pw; break end
      end
    end
    self.cache[key] = p
  end
  return self.cache[key]
end

-- One-line reading for a row: body value, or how many practice shots land in.
function AV:short(k, lv)
  if not isShot[k] then return (bodyReading(k, lv)), C.text end
  local p = self:practice(k, lv, Progress.practice.card)
  if not p.available then return p.needPower and ("needs Power Lv" .. p.needPower) or "can't play it", C.bad end
  return string.format("%d/%d in", p.inCount, p.n), C.text
end

-- When the next level comes on today's plan: text, colour.
function AV:eta(k)
  local sk = self.career.sim.skills[k]
  local need = Training.repsFor(sk.level) - sk.progress
  local per = self.daily[k]
  if not per or per < 0.5 then return "not in today's plan", FAINT end
  local d = need / per
  local days = math.floor(d + 0.5)
  local when = d < 0.6 and "later today" or (days <= 1 and "about a day" or string.format("about %d days", days))
  return string.format("Lv%d %s", sk.level + 1, when), C.good
end

---------------------------------------------------------------------------- drawing helpers
local function bar(x, y, w, frac, h)
  Draw.color(C.textDim, 0.22)
  love.graphics.rectangle("fill", x, y, w, h or 2)
  Draw.color(C.near)
  love.graphics.rectangle("fill", x, y, math.floor(w * math.max(0, math.min(1, frac))), h or 2)
end

-- The whole court from above, sideways: his half on the left, net in the middle. Practice
-- result p: hitting spot (blue), aim ring (yellow), landings (white in / red out). Returns h.
local function drawCourt(x, y, w, p)
  local pad = 0.7
  local sc = w / (LEN * 2 + pad * 2)
  local h = math.floor((HW * 2 + pad * 2) * sc)
  local function X(wy) return math.floor(x + (LEN - wy + pad) * sc) + 0.5 end
  local function Y(wx) return math.floor(y + (HW - wx + pad) * sc) + 0.5 end
  love.graphics.setColor(0.08, 0.13, 0.11)
  love.graphics.rectangle("fill", x, y, w, h)
  Draw.color(COURT)
  love.graphics.rectangle("fill", X(LEN), Y(HW), LEN * 2 * sc, HW * 2 * sc)
  love.graphics.setColor(0.87, 0.91, 0.89, 0.5)
  love.graphics.setLineWidth(1)
  local function L(x1, y1, x2, y2) love.graphics.line(X(y1), Y(x1), X(y2), Y(x2)) end
  L(-HW, LEN, HW, LEN); L(-HW, -LEN, HW, -LEN); L(HW, -LEN, HW, LEN); L(-HW, -LEN, -HW, LEN)
  L(SW, -LEN, SW, LEN); L(-SW, -LEN, -SW, LEN); L(0, 1.98, 0, LEN); L(0, -1.98, 0, -LEN)
  for _, s in ipairs({ 1, -1 }) do L(-HW, 1.98 * s, HW, 1.98 * s); L(-HW, (LEN - 0.76) * s, HW, (LEN - 0.76) * s) end
  love.graphics.setColor(1, 1, 1, 0.9)
  love.graphics.rectangle("fill", X(0) - 1, Y(HW + 0.3), 2, (HW * 2 + 0.6) * sc)
  if not p then return h end
  local fx, fy, tx, ty = X(p.from.y), Y(p.from.x), X(p.aim.y), Y(p.aim.x)
  Draw.color(C.near, 0.5)
  love.graphics.line(fx, fy, tx, ty)
  Draw.color(ACCENT)
  love.graphics.circle("line", tx, ty, math.max(2, math.floor(0.6 * sc)))
  for _, q in ipairs(p.points) do
    local qx, qy = math.floor(X(q.y)), math.floor(Y(q.x))
    if qx >= x and qx < x + w and qy >= y and qy < y + h then
      Draw.color(q.outcome == "in" and C.text or C.bad)
      love.graphics.rectangle("fill", qx, qy, 2, 2)
    end
  end
  Draw.color(C.near)
  love.graphics.rectangle("fill", math.floor(fx) - 2, math.floor(fy) - 2, 4, 4)
  return h
end

-- Back arrow icon (also the hub's Menu button).
function AV.drawArrow(x, y, w, h, col)
  Draw.color(col)
  local cx, cy = math.floor(x + w / 2), math.floor(y + h / 2)
  love.graphics.polygon("fill", cx - 5, cy, cx - 1, cy - 4, cx - 1, cy + 4)
  love.graphics.rectangle("fill", cx - 1, cy - 1, 6, 2)
end

function AV.iconButton(r, hot, drawIcon)
  Draw.color(hot and ROW_HOT or C.panel)
  love.graphics.rectangle("fill", r.x, r.y, r.w, r.h)
  Draw.color(hot and ACCENT or C.panelEdge, hot and 1 or 0.6)
  love.graphics.rectangle("line", r.x + 0.5, r.y + 0.5, r.w - 1, r.h - 1)
  drawIcon(hot and ACCENT or C.text)
end

-- Programs that train a stat (from the programs' drills and exercises).
local function trainedBy(k)
  local out = {}
  for _, p in ipairs(Career.data.programs) do
    local hit = false
    if p.kind == "drill" then
      for _, f in ipairs(p.focus or {}) do if f == k then hit = true end end
      if TD.drill.physical[k] then hit = true end
    elseif p.kind == "gym" then
      for _, ex in ipairs(p.focus or {}) do if TD.exercises[ex].gains[k] then hit = true end end
    end
    if hit then out[#out + 1] = p.label end
  end
  return out
end

-- Value at a level on a stat's track (narrow: just the number, the unit is shown above).
function AV:trackValue(k, lv, narrow)
  if isShot[k] then
    local p = self:practice(k, lv, Progress.practice.track)
    if not p.available then return p.needPower and ("Pow " .. p.needPower) or "--" end
    return string.format("%d%%", math.floor(p.inCount / p.n * 100 + 0.5))
  end
  local v = (bodyReading(k, lv))
  if narrow then v = v:match("^[~+]?[%d.]+") or v:gsub("^lunge ", "") end
  return v
end

-- Ten level nodes on a line from x0, each nodeW wide; values under them, unlocks optional.
function AV:drawNodes(k, x0, y, nodeW, withUnlocks)
  local lv = self.career.sim.skills[k].level
  local small = Assets.fonts.small
  for l = 1, 9 do
    Draw.color(l < lv and C.near or { 0.20, 0.23, 0.30 })
    love.graphics.rectangle("fill", math.floor(x0 + (l - 0.5) * nodeW), y - 1, math.floor(nodeW), 2)
  end
  for l = 1, 10 do
    local cx = math.floor(x0 + (l - 0.5) * nodeW)
    local done, cur, nxt = l < lv, l == lv, l == lv + 1
    local r = 7
    Draw.color(cur and C.near or (done and { 0.12, 0.20, 0.32 } or BG))
    love.graphics.polygon("fill", cx, y - r, cx + r, y, cx, y + r, cx - r, y)
    Draw.color((cur or done) and C.near or (nxt and ACCENT or { 0.28, 0.31, 0.38 }))
    love.graphics.polygon("line", cx, y - r, cx + r, y, cx, y + r, cx - r, y)
    Draw.sign(tostring(l), cx - r, y - r, r * 2, r * 2, cur and BG or (nxt and ACCENT or (done and C.text or FAINT)), small)
    Draw.text(self:trackValue(k, l, nodeW < 50), cx - nodeW / 2, y + 11, (cur or done) and C.text or C.textDim, small, "center", nodeW)
    local u = withUnlocks and Progress.unlocks[k] and Progress.unlocks[k][l]
    if u then
      Draw.color((cur or done) and C.textDim or ACCENT)
      love.graphics.setFont(small)
      love.graphics.printf(u, math.floor(cx - nodeW / 2 + 1), y + 22, math.floor(nodeW - 2), "center")
    end
  end
end

-- Reps to the next level: bar + numbers + when (in a box of width w).
function AV:repsBlock(k, x, y, w)
  local sk = self.career.sim.skills[k]
  local need = Training.repsFor(sk.level)
  Draw.text(string.format("%d / %d reps to Lv%d", math.floor(sk.progress), need, sk.level + 1), x, y, C.text, Assets.fonts.normal)
  bar(x, y + 14, w, sk.progress / need, 4)
  local t, col = self:eta(k)
  Draw.text(t == "not in today's plan" and "nothing in today's plan trains this" or ("today's plan: " .. t), x, y + 22, col,
    Assets.fonts.small)
end

function AV:trainedBlock(k, x, y, w)
  Draw.text("TRAINED BY", x, y, C.textDim, Assets.fonts.small)
  for i, name in ipairs(trainedBy(k)) do
    local col, row = math.floor((i - 1) / 3), (i - 1) % 3
    Draw.text(name, x + col * (w / 2), y + 11 + row * 10, C.text, Assets.fonts.small)
  end
end

---------------------------------------------------------------------------- rows
-- Row rects, in the order of BODY then SHOTS.
function AV:rows()
  local out = {}
    local S = A.split
    local y = S.y
    for gi, group in ipairs({ BODY, SHOTS }) do
      y = y + 12
      for _, k in ipairs(group) do
        out[#out + 1] = { k = k, x = S.x, y = y, w = S.w, h = S.rowH }
        y = y + S.rowH + S.rowGap
      end
      if gi == 1 then y = y + 6 end
    end
  return out
end

-- One row: name and level, the short reading, a thin reps bar.
function AV:drawRow(r, hot, picked)
  local k = r.k
  local sk = self.career.sim.skills[k]
  local small, normal = Assets.fonts.small, Assets.fonts.normal
  Draw.color((hot or picked) and ROW_HOT or ROW)
  love.graphics.rectangle("fill", r.x, r.y, r.w, r.h)
  if picked then
    Draw.color(ACCENT)
    love.graphics.rectangle("fill", r.x, r.y, 2, r.h)
  elseif hot then
    Draw.color(ACCENT, 0.7)
    love.graphics.rectangle("line", r.x + 0.5, r.y + 0.5, r.w - 1, r.h - 1)
  end
  Draw.text(label(k), r.x + 6, r.y + 3, C.text, normal)
  Draw.text("Lv" .. sk.level, r.x + 66, r.y + 4, ACCENT, small)
  local v, vc = self:short(k, sk.level)
  Draw.text(v, r.x, r.y + 4, vc, small, "right", r.w - 6)
  bar(r.x + 6, r.y + r.h - 5, r.w - 12, sk.progress / Training.repsFor(sk.level))
end

---------------------------------------------------------------------------- pages
function AV:drawHeader(title)
  local c = self.career
  if title then
    Draw.text(title, A.headX, A.headY - 2, C.text, Assets.fonts.big)
    return
  end
  Avatar.draw({ name = c.name, you = true }, A.headX + 8, A.headY + 8, 9, 1, C.near)
  Draw.text(c.name, A.headX + 22, A.headY - 2, C.text, Assets.fonts.big)
  local x = A.headX + 30 + Assets.fonts.big:getWidth(c.name)
  Emblem.draw(Emblem.tierFor(c.level, c.champion), x + 6, A.headY + 9, 6)
  Draw.text(string.format("%s  -  Day %d", c.champion and "World Champion" or Athletes.levels[c.level].title, c.sim.day),
    x + 16, A.headY + 6, C.textDim, Assets.fonts.small)
end

-- Rows down the left, the picked stat's detail on the right.
function AV:drawSplit(mx, my)
  self:drawHeader()
  local S = A.split
  local rows = self:rows()
  Draw.text("BODY", S.x, S.y, C.textDim, Assets.fonts.small)
  Draw.text("SHOTS", S.x, rows[#BODY + 1].y - 12, C.textDim, Assets.fonts.small)
  for _, r in ipairs(rows) do self:drawRow(r, inside(r, mx, my), r.k == self.pick) end
  -- detail pane
  local k = self.pick
  local lv = self.career.sim.skills[k].level
  local px, pw = S.paneX, Layout.width - S.paneX - 8
  local y = S.y
  Draw.color(ROW)
  love.graphics.rectangle("fill", px, y, pw, Layout.height - y - 8)
  local x = px + 10
  Draw.text(label(k), x, y + 6, C.text, Assets.fonts.big)
  Draw.text("Lv" .. lv, x + Assets.fonts.big:getWidth(label(k)) + 8, y + 15, ACCENT, Assets.fonts.small)
  Draw.text(isShot[k] and Progress.about.shot or Progress.about[k], x, y + 30, C.textDim, Assets.fonts.small, "left", pw - 20)
  local cy = y + 54
  if isShot[k] then
    for i, l in ipairs({ lv, math.min(10, lv + 1) }) do
      local p = self:practice(k, l, Progress.practice.track)
      local cx = x + (i - 1) * ((pw - 20) / 2 + 2)
      local cw = math.floor((pw - 20) / 2 - 4)
      Draw.text(i == 1 and ("now  Lv" .. l) or ("next  Lv" .. l), cx, cy, i == 1 and C.near or ACCENT, Assets.fonts.small)
      local ch = drawCourt(cx, cy + 11, cw, p)
      Draw.text(p.available and string.format("%d / %d land in", p.inCount, p.n) or self:short(k, l), cx, cy + 13 + ch,
        p.available and C.text or C.bad, Assets.fonts.small)
      if i == 2 then cy = cy + 26 + ch end
    end
  else
    local v0, n0 = bodyReading(k, lv)
    local v1 = bodyReading(k, math.min(10, lv + 1))
    Draw.text("now", x, cy, C.near, Assets.fonts.small)
    Draw.text(v0, x, cy + 10, C.text, Assets.fonts.big)
    Draw.text(n0, x, cy + 33, C.textDim, Assets.fonts.small)
    Draw.text("next", x + 200, cy, ACCENT, Assets.fonts.small)
    Draw.text(v1, x + 200, cy + 10, C.textDim, Assets.fonts.big)
    cy = cy + 50
  end
  -- next unlock, the level line, reps, what trains it
  local nextU
  for l = lv + 1, 10 do
    local u = Progress.unlocks[k] and Progress.unlocks[k][l]
    if u then nextU = "Lv" .. l .. ": " .. u; break end
  end
  if nextU then Draw.text(nextU, x, cy, ACCENT, Assets.fonts.small) end
  self:drawNodes(k, x, cy + 22, (pw - 20) / 10, false)
  self:repsBlock(k, x, cy + 50, pw - 20)
  self:trainedBlock(k, x, cy + 86, pw - 20)
end

---------------------------------------------------------------------------- frame
function AV:draw(mx, my)
  self.daily = Career.dailyReps(self.career)
  Draw.color(BG)
  love.graphics.rectangle("fill", 0, 0, Layout.width, Layout.height)
  self:drawSplit(mx, my)
  local b = A.back
  AV.iconButton(b, inside(b, mx, my), function(col) AV.drawArrow(b.x, b.y, b.w, b.h, col) end)
end

-- Something under the mouse that does something (hand cursor)?
function AV:hot(mx, my)
  if inside(A.back, mx, my) then return true end
  for _, r in ipairs(self:rows()) do if inside(r, mx, my) then return true end end
  return false
end

-- Click: pick a stat, or close (returns "close").
function AV:click(x, y)
  if inside(A.back, x, y) then return self:escape() end
  for _, r in ipairs(self:rows()) do
    if inside(r, x, y) then
      self.pick = r.k
      return nil
    end
  end
end

-- Back arrow / Esc: close (returns "close").
function AV:escape() return "close" end

return AV
