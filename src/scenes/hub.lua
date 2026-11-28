-- Career hub: the academy, three rooms side by side (court | lobby | gym, src/view/
-- training_view.lua + lobby_view.lua). You look into one room at a time: the door tabs at the
-- screen edges show the next room, and the view follows him when he walks through a door
-- while you are watching him. He runs on the training sim from the career; empty plan slots
-- are free time (he wanders and does his own thing).
--   Lobby             the whiteboard opens the program drawer (plan the day: drag a program
--                     onto a slot that hasn't started, a slot onto another to swap, off the
--                     plan to empty it); the front desk enters this league's tournament.
--   Plan (top left)   today's frame with 4 slots; outside the lobby a click takes you to the
--                     whiteboard.
--   Stats (top right) progress on the stats the running block trains (none in free time);
--                     the whole picture is on the athlete card.
--   Athlete / Menu    the full-screen athlete page (src/view/athlete_view.lua) / back to the title.
-- Click the world to coach him (he speeds up). Time runs at one fixed pace for everyone (no speed
-- keys or pause: faster time would just be a shortcut); --speed N is a dev-only flag.
-- Keys: Esc closes an overlay, left / right arrows look into the next room.
local Layout = require("src.config.layout")
local Progress = require("src.data.progress")
local Camera = require("src.view.camera")
local Draw = require("src.view.draw")
local Assets = require("src.view.assets")
local Emblem = require("src.view.emblem")
local Training = require("src.core.training")
local Career = require("src.core.career")
local Tournament = require("src.core.tournament")
local Athletes = require("src.data.athletes")
local View = require("src.view.training_view")
local Lobby = require("src.view.lobby_view")
local AthleteView = require("src.view.athlete_view")
local Avatar = require("src.view.avatar")

local TL, HB = Layout.training, Layout.hub
local C, TC = Layout.colors, Layout.training.colors
local TD = Training.data
local CD = Career.data
local WORKING = 1.05
local DRAG_START = 3          -- px the mouse must move before a press becomes a drag
local CAT_COLOR = { court = { 0.16, 0.55, 0.43 }, gym = { 0.88, 0.58, 0.22 } }

local Hub = {}
Hub.__index = Hub

local function inside(r, x, y) return r and x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h end

function Hub.new(app, params)
  local self = setmetatable({ app = app }, Hub)
  self.career = app.career
  self.sim = self.career.sim
  self.cam = Camera.new(TL.camera)
  self.view = View.new(self.cam)
  self.speed = app.dev.speed or 1     -- dev only (--speed N): players can't change the pace
  self.shown, self.flash = {}, {}
  self.tab = 1
  self.athleteView = AthleteView.new(self.career)      -- full-screen athlete page (Athlete button)
  self.mx, self.my = app.mouse.x, app.mouse.y
  if app.dev.clock and not app.dev.clockUsed then   -- dev: start the day at --clock HH:MM
    app.dev.clockUsed = true
    Training.jumpTo(self.sim, Training.minutes(app.dev.clock))
  end
  -- the room you are looking at; follow = the view goes along when he changes room
  self.room = params.room or app.dev.room or self.sim.location
  self.follow = self.room == self.sim.location
  self.fade = 0
  self.overlay = nil              -- "drawer" | "athlete"
  if params.open == "drawer" or params.open == "athlete" then self.overlay = params.open end
  local track = params.open and params.open:match("^athlete:(%a+)$")   -- dev: a stat's level track
  if track then self.overlay = "athlete"; self.athleteView.pick = track end
  if params.open == "drag" then   -- dev: a card mid-drag over slot 3
    self.overlay = "drawer"
    self.drag = { kind = "program", id = "clear_smash", moved = true }
  end
  if self.overlay == "drawer" then self.room = "lobby"; self.follow = self.sim.location == "lobby" end
  local wins = params.open and params.open:match("^bracket:(%d+)$")   -- dev: bracket:N = you won N already
  if params.open == "desk" or params.open == "bracket" or wins then app:switch("tournament", { wins = tonumber(wins) }) end
  if params.open == "promotion" then
    app:switch("promotion", { from = math.max(1, self.career.level - 1), to = self.career.level })
  end
  return self
end

---------------------------------------------------------------------------- layout rects
function Hub:_planRows()
  local P = HB.plan
  local rows, y = {}, P.y + 16
  for i, b in ipairs(self.sim.schedule) do
    local h = b.slot and P.slotH or P.rowH
    rows[i] = { block = b, slot = b.slot, x = P.x + 3, y = y, w = P.w - 6, h = h - 2 }
    y = y + h
  end
  self.planH = y - P.y + 3
  return rows
end

-- The dragged chip (a program held near its left end), with the mouse at x, y.
function Hub:_chipRect(x, y)
  local P = HB.plan
  return { x = x - 8, y = y - math.floor((P.slotH - 2) / 2), w = P.w - 6, h = P.slotH - 2 }
end

local function overlap(a, b)
  local ox = math.min(a.x + a.w, b.x + b.w) - math.max(a.x, b.x)
  local oy = math.min(a.y + a.h, b.y + b.h) - math.max(a.y, b.y)
  return (ox > 0 and oy > 0) and ox * oy or 0
end

-- The slot a drop would land in: the one the chip covers most, and only once it covers at
-- least HB.plan.snap of the chip (a corner brushing a slot doesn't grab it).
function Hub:_dropSlot(x, y)
  local chip = self:_chipRect(x, y)
  local best, bestA = nil, 0
  for _, r in ipairs(self:_planRows()) do
    if r.slot then
      local a = overlap(chip, r)
      if a > bestA then best, bestA = r.slot, a end
    end
  end
  if best and bestA >= HB.plan.snap * chip.w * chip.h then return best end
end

-- Is the chip clear of the plan panel (dropping it there empties a dragged slot)?
function Hub:_chipOffPlan(x, y)
  return overlap(self:_chipRect(x, y), { x = HB.plan.x, y = HB.plan.y, w = HB.plan.w, h = self.planH or 0 }) == 0
end

function Hub:_slotAt(x, y)
  for _, r in ipairs(self:_planRows()) do
    if r.slot and inside(r, x, y) then return r.slot, r end
  end
end

function Hub:_drawerRect() local D = HB.drawer; return { x = D.x, y = D.y, w = D.w, h = D.h } end

function Hub:_tabs()
  local D = HB.drawer
  local tabs, x = {}, D.x + 8
  for i, cat in ipairs(CD.categories) do
    local w = Assets.fonts.small:getWidth(cat.label) + 14
    tabs[i] = { x = x, y = D.y + 22, w = w, h = D.tabH, cat = cat }
    x = x + w + 4
  end
  return tabs
end

function Hub:_cards()
  local D = HB.drawer
  local cat = CD.categories[self.tab].id
  local cards, n = {}, 0
  for _, p in ipairs(CD.programs) do
    if p.cat == cat then
      local col, row = n % 3, math.floor(n / 3)
      cards[#cards + 1] = { x = D.x + 8 + col * (D.cardW + D.gap), y = D.y + 44 + row * (D.cardH + D.gap),
                            w = D.cardW, h = D.cardH, program = p }
      n = n + 1
    end
  end
  return cards
end

function Hub:_closeRect() local D = HB.drawer; return { x = D.x + D.w - 16, y = D.y + 4, w = 12, h = 12 } end

function Hub:_buttons()
  local A, M = HB.card, HB.menu
  local b = {
    athlete = { x = A.x, y = A.y, w = A.w, h = A.h },
    menu = { x = M.x, y = M.y, w = M.w, h = M.h },
  }
  if self.room == "lobby" then
    b.desk, b.board = Lobby.deskRect(self.cam), Lobby.boardRect(self.cam)
  end
  return b
end

-- Door tabs at the screen edges, one per neighbouring room: { room, side = -1 left / 1 right, rect }.
function Hub:_doors()
  local D = HB.doors
  local out = {}
  for _, r in ipairs(Training.neighbours(self.room)) do
    local door = TL.doors[self.room][r]
    local side = door.x < 0 and -1 or 1
    out[#out + 1] = { room = r, side = side,
                      x = side < 0 and 0 or Layout.width - D.w, y = D.y, w = D.w, h = D.h }
  end
  return out
end

-- Look into another room (a short fade). Following him again once you are where he is.
function Hub:_goRoom(room)
  if room == self.room then return end
  self.room = room
  self.fade = HB.fade
  self.follow = room == self.sim.location
end

function Hub:_here() return self.sim.location == self.room end

-- Hand cursor over anything that does something when clicked.
local HAND
function Hub:_updateCursor()
  local mx, my = self.mx, self.my
  local hot = self.hover ~= nil
  if self.overlay == "athlete" then hot = self.athleteView:hot(mx, my) end
  if not self.overlay and not self.drag then
    for _, d in ipairs(self:_doors()) do hot = hot or inside(d, mx, my) end
    local B = self:_buttons()
    hot = hot or inside(B.athlete, mx, my) or inside(B.menu, mx, my)
    hot = hot or (not self:_here() and inside(self:_topRect(), mx, my))
  end
  HAND = HAND or love.mouse.getSystemCursor("hand")
  love.mouse.setCursor(hot and HAND or nil)
end

---------------------------------------------------------------------------- update
function Hub:update(dt)
  local mx, my = self.app.mouse.x, self.app.mouse.y
  self.mx, self.my = mx, my
  if self.press and not self.drag then
    if math.abs(mx - self.press.x) + math.abs(my - self.press.y) >= DRAG_START and self.press.dragKind then
      self.drag = { kind = self.press.dragKind, id = self.press.id, from = self.press.slot, moved = true }
    end
  end
  if self.toast then self.toast.t = self.toast.t - dt; if self.toast.t <= 0 then self.toast = nil end end
  self.fade = math.max(0, self.fade - dt)
  self.hover = self:_lobbyHover()
  self.view.hover = self.hover
  self:_updateCursor()
  self.view.emblemTier = Emblem.tierFor(self.career.level, self.career.champion)
  local every = self.app.dev.coach
  if every then
    self.coachT = (self.coachT or 0) + dt
    if self.coachT >= every then self.coachT = 0; Training.coach(self.sim) end
  end
  local sim = self.sim
  local step = dt * self.speed
  local n = math.max(1, math.ceil(step / 0.05))
  for _ = 1, n do
    Training.update(sim, step / n)
    self.view:update(sim, step / n * sim.pace)
    for _, e in ipairs(sim.events) do
      if e.type == "rep" or e.type == "levelup" then self.flash[e.skill] = e.type == "levelup" and 2.0 or 0.6 end
    end
    sim.events = {}
  end
  -- the view goes along with him through doors; he walking into the room you watch picks him up
  if self.follow and sim.location ~= self.room then self:_goRoom(sim.location); self.follow = true
  elseif sim.location == self.room then self.follow = true end
  for k, v in pairs(self.flash) do self.flash[k] = v - dt; if self.flash[k] <= 0 then self.flash[k] = nil end end
  for name, sk in pairs(sim.skills) do
    local target = sk.level + sk.progress / Training.repsFor(sk.level)
    local cur = self.shown[name] or target
    self.shown[name] = cur + (target - cur) * math.min(1, dt * 8)
    if target < cur then self.shown[name] = target end
  end
end

function Hub:_say(text) self.toast = { text = text, t = 2.2 } end

---------------------------------------------------------------------------- input
function Hub:mousepressed(x, y, button)
  if button ~= 1 then return end
  if self.overlay == "athlete" then
    if self.athleteView:click(x, y) == "close" then self.overlay = nil end
    return
  end
  local B = self:_buttons()
  if self.overlay == "drawer" then
    if inside(self:_closeRect(), x, y) then self.overlay = nil; return end
    for i, tab in ipairs(self:_tabs()) do if inside(tab, x, y) then self.tab = i; return end end
    for _, card in ipairs(self:_cards()) do
      if inside(card, x, y) then self.press = { x = x, y = y, dragKind = "program", id = card.program.id }; return end
    end
  end
  if not self.overlay then
    for _, d in ipairs(self:_doors()) do
      if inside(d, x, y) then self:_goRoom(d.room); return end
    end
    if inside(self:_topRect(), x, y) and not self:_here() then self:_goRoom(self.sim.location); return end
  end
  local slot = self:_slotAt(x, y)
  if slot and self.room ~= "lobby" then
    -- the plan is set at the lobby whiteboard: take the view there
    self:_goRoom("lobby")
    self.overlay = "drawer"
    return
  end
  if slot then
    local filled = self.career.plan[slot]
    self.press = { x = x, y = y, slot = slot, dragKind = filled and not Career.slotLocked(self.career, slot) and "slot" or nil,
                   id = filled }
    return
  end
  if self.overlay == "drawer" and inside(self:_drawerRect(), x, y) then return end
  if inside(B.athlete, x, y) then self.overlay = "athlete"; return end
  if inside(B.menu, x, y) then self.app:switch("title"); return end
  if inside({ x = HB.plan.x, y = HB.plan.y, w = HB.plan.w, h = self.planH or 0 }, x, y) then return end
  if self.overlay == "drawer" then self.overlay = nil; return end
  if self.hover == "desk" then self:_enter(); return end
  if self.hover == "board" then self.overlay = "drawer"; return end
  -- coaching: only where he is, and not in the lobby (nothing to push him at there)
  if self:_here() and self.room ~= "lobby" then Training.coach(self.sim) end
end

function Hub:mousereleased(x, y, button)
  if button ~= 1 then return end
  local press, drag = self.press, self.drag
  self.press, self.drag = nil, nil
  local c = self.career
  if drag then
    local target = self:_dropSlot(x, y)
    if drag.kind == "program" then
      if target then
        if Career.setSlot(c, target, drag.id) then self:_say(Career.program(drag.id).label .. " in slot " .. target)
        else self:_say("That slot has already started") end
      end
    elseif drag.kind == "slot" then
      if target and target ~= drag.from then
        if not Career.swapSlots(c, drag.from, target) then self:_say("That slot has already started") end
      elseif not target and self:_chipOffPlan(x, y) then
        Career.setSlot(c, drag.from, false)
        self:_say("Slot " .. drag.from .. " is free time now")
      end
    end
    return
  end
  if press and press.slot then
    -- a click on a slot (no drag): open the drawer
    if Career.slotLocked(c, press.slot) then self:_say("That slot has already started")
    else self.overlay = "drawer" end
  end
end

function Hub:_enter()
  self.app:switch("tournament", {})
end

function Hub:keypressed(key)
  if (key == "left" or key == "right") and not self.overlay then
    for _, d in ipairs(self:_doors()) do
      if (d.side < 0) == (key == "left") then self:_goRoom(d.room) end
    end
  end
  if key == "escape" then
    if self.overlay == "athlete" then
      if self.athleteView:escape() == "close" then self.overlay = nil end
    elseif self.overlay then self.overlay = nil else self.app:switch("title") end
  end
end

---------------------------------------------------------------------------- drawing: plan
local function dashedRect(r, col, alpha)
  Draw.color(col, alpha)
  love.graphics.setLineWidth(1)
  local x1, y1, x2, y2 = math.floor(r.x) + 0.5, math.floor(r.y) + 0.5, math.floor(r.x + r.w) - 0.5, math.floor(r.y + r.h) - 0.5
  for x = x1, x2 - 2, 4 do love.graphics.line(x, y1, math.min(x + 2, x2), y1); love.graphics.line(x, y2, math.min(x + 2, x2), y2) end
  for y = y1, y2 - 2, 4 do love.graphics.line(x1, y, x1, math.min(y + 2, y2)); love.graphics.line(x2, y, x2, math.min(y + 2, y2)) end
end

-- Row states are shown, not explained: a done block is crossed out and dimmed, the running
-- block is lit with a NOW tag and its progress, and while you drag a program the open slots
-- pulse as drop targets (locked ones stay put).
function Hub:_drawPlan()
  local P = HB.plan
  local sim, c = self.sim, self.career
  local rows = self:_planRows()
  local font = Assets.fonts.small
  Draw.panel(P.x, P.y, P.w, self.planH)
  Draw.text(string.format("TODAY  -  DAY %d", sim.day), P.x + 5, P.y + 4, C.textDim, font)
  local cur = Training.block(sim)
  local target = self.drag and self:_dropSlot(self.mx, self.my)
  local pulse = 0.55 + 0.45 * math.sin(love.timer.getTime() * 6)
  local preview = self:_dropPreview()        -- the drop shown in place, before you let go
  for _, r in ipairs(rows) do
    local b = r.block
    local now, past = cur == b, sim.clock >= b.stop
    local time = Training.clockText(b.start)
    local previewed = r.slot and preview and preview[r.slot] ~= nil
    local id = r.slot and c.plan[r.slot]
    if previewed then id = preview[r.slot] end      -- may be false: a swap empties it
    local program = r.slot and Career.program(id)
    local dragging = not previewed and self.drag and self.drag.kind == "slot" and self.drag.from == r.slot
    local tx = r.slot and r.x + 5 or r.x + 2
    local lx = r.slot and r.x + 36 or r.x + 33
    local ty = r.y + math.floor((r.h - 8) / 2) - 1
    local label, labelCol = b.label, C.text
    if now then
      -- running: lit row, accent bar, NOW, progress along the bottom
      Draw.color(HB.accent, 0.16)
      love.graphics.rectangle("fill", r.x, r.y, r.w, r.h)
      Draw.color(HB.accent)
      love.graphics.rectangle("fill", r.x, r.y, 2, r.h)
      local u = (sim.clock - b.start) / (b.stop - b.start)
      love.graphics.rectangle("fill", r.x, r.y + r.h - 1, math.floor(r.w * u), 1)
      Draw.text("NOW", r.x, ty, HB.accent, font, "right", r.w - 3)
      if r.slot and not program then label = "Free time" end
    elseif r.slot and program and not dragging then
      local cc = CAT_COLOR[program.cat]
      Draw.color(past and { 0.13, 0.15, 0.19 } or { 0.20, 0.25, 0.33 })
      love.graphics.rectangle("fill", r.x, r.y, r.w, r.h)
      Draw.color(cc, past and 0.35 or 1)
      love.graphics.rectangle("fill", r.x, r.y, 2, r.h)
      label = program.label
    elseif r.slot and not past then
      -- open empty slot: dashed; a drop target while dragging
      local hot = target == r.slot or (not self.drag and inside(r, self.mx, self.my))
      local col = (hot or self.drag) and HB.accent or C.textDim
      dashedRect(r, col, hot and 1 or (self.drag and pulse or 0.6))
      label, labelCol = hot and self.drag and "drop here" or "+ add", col
    elseif r.slot then
      label = "Free time"
    end
    if previewed then
      Draw.color(HB.accent)
      love.graphics.rectangle("line", r.x + 0.5, r.y + 0.5, r.w - 1, r.h - 1)
    elseif r.slot and program and not now and not past and not dragging and self.drag then
      -- a filled open slot also takes a drop (replaces it)
      Draw.color(HB.accent, target == r.slot and 1 or pulse * 0.6)
      love.graphics.rectangle("line", r.x + 0.5, r.y + 0.5, r.w - 1, r.h - 1)
    end
    if past then labelCol = { 0.45, 0.47, 0.53 } end
    if not now and not r.slot and not past then labelCol = C.textDim end
    Draw.text(time, tx, ty, past and labelCol or C.textDim, font)
    Draw.text(label, lx, ty, labelCol, font)
    if past then
      -- crossed out: done for today
      local w = lx + font:getWidth(label) - tx + 2
      Draw.color(labelCol)
      love.graphics.rectangle("fill", tx - 1, ty + 5, w, 1)
    end
  end
end

---------------------------------------------------------------------------- drawing: drawer
local function drawCard(r, p, alpha)
  local cc = CAT_COLOR[p.cat]
  Draw.color({ 0.18, 0.22, 0.30 }, alpha)
  love.graphics.rectangle("fill", r.x, r.y, r.w, r.h)
  Draw.color(cc, alpha)
  love.graphics.rectangle("fill", r.x, r.y, 3, r.h)
  -- the tab already says court / gym: the card is just the name and what it trains
  Draw.text(p.short or p.label, r.x + 7, r.y + 5, C.text, Assets.fonts.normal)
  Draw.text(p.trains, r.x + 7, r.y + 19, C.textDim, Assets.fonts.small)
end

function Hub:_drawDrawer()
  local D = HB.drawer
  Draw.panel(D.x, D.y, D.w, D.h)
  Draw.text("Programs", D.x + 8, D.y + 6, C.text, Assets.fonts.normal)
  local cr = self:_closeRect()
  Draw.text("x", cr.x, cr.y, inside(cr, self.mx, self.my) and C.text or C.textDim, Assets.fonts.normal, "center", cr.w)
  for i, tab in ipairs(self:_tabs()) do
    local on = i == self.tab
    Draw.color(on and CAT_COLOR[tab.cat.id] or { 0.18, 0.21, 0.27 })
    love.graphics.rectangle("fill", tab.x, tab.y, tab.w, tab.h)
    Draw.text(tab.cat.label, tab.x, tab.y + 4, on and C.text or C.textDim, Assets.fonts.small, "center", tab.w)
  end
  for _, card in ipairs(self:_cards()) do
    local lifted = self.drag and self.drag.kind == "program" and self.drag.id == card.program.id
    drawCard(card, card.program, lifted and 0.35 or 1)
    if not self.drag and inside(card, self.mx, self.my) then
      Draw.color(HB.accent)
      love.graphics.rectangle("line", card.x + 0.5, card.y + 0.5, card.w - 1, card.h - 1)
    end
  end
end

-- While dragging over a slot that would take the drop: what the plan would look like after it
-- (slot -> program id or false). nil when the drop wouldn't change anything here.
function Hub:_dropPreview()
  local d = self.drag
  if not d then return nil end
  local c = self.career
  local target = self:_dropSlot(self.mx, self.my)
  if not target or Career.slotLocked(c, target) then return nil end
  if d.kind == "program" then return { [target] = d.id } end
  if d.kind == "slot" and target ~= d.from then
    return { [target] = c.plan[d.from], [d.from] = c.plan[target] }
  end
end

-- The dragged program: a chip the size of a plan slot, held near its left end. Over a slot
-- that takes it, the slot itself shows the result instead (Hub:_dropPreview), so it hides.
function Hub:_drawDragged()
  local d = self.drag
  if not d or self:_dropPreview() then return end
  local p = Career.program(d.id)
  if not p then return end
  local r = self:_chipRect(self.mx, self.my)
  Draw.color({ 0, 0, 0 }, 0.35)
  love.graphics.rectangle("fill", r.x + 2, r.y + 3, r.w, r.h)
  Draw.color({ 0.20, 0.25, 0.33 })
  love.graphics.rectangle("fill", r.x, r.y, r.w, r.h)
  Draw.color(CAT_COLOR[p.cat])
  love.graphics.rectangle("fill", r.x, r.y, 2, r.h)
  Draw.text(p.label, r.x + 6, r.y + math.floor((r.h - 8) / 2) - 1, C.text, Assets.fonts.small)
  Draw.color(HB.accent)
  love.graphics.rectangle("line", r.x + 0.5, r.y + 0.5, r.w - 1, r.h - 1)
end

---------------------------------------------------------------------------- drawing: stats, top, desk
-- Stats the block running now trains (in the usual stat order), or nil (free time, lunch,
-- cool-down: nothing to show). Drills: their shots plus what every drill rep adds to the
-- legs (T.drill.physical); gym and warm-up: what their exercises add.
function Hub:_trainedStats()
  local b = Training.block(self.sim)
  if not b then return nil end
  local set = {}
  if b.kind == "drill" then
    for _, shot in ipairs(b.focus or {}) do set[shot] = true end
    for stat in pairs(TD.drill.physical) do set[stat] = true end
  elseif b.kind == "gym" or b.kind == "warmup" then
    for _, ex in ipairs(b.kind == "warmup" and { "jog" } or b.focus or {}) do
      for stat in pairs(TD.exercises[ex].gains) do set[stat] = true end
    end
  else
    return nil
  end
  local list = {}
  for _, g in ipairs({ TD.skills.technique, TD.skills.physical }) do
    for _, k in ipairs(g) do if set[k] then list[#list + 1] = k end end
  end
  return list, b
end

-- Progress on what he is training right now (the whole picture is on the athlete card).
function Hub:_drawStats()
  local list, b = self:_trainedStats()
  if not list then return end
  local S = HB.stats
  local sim = self.sim
  local h = 18 + #list * S.rowH + 4
  Draw.panel(S.x, S.y, S.w, h)
  Draw.text(b.label:upper(), S.x + 5, S.y + 4, C.textDim, Assets.fonts.small)
  local y = S.y + 18
  for _, name in ipairs(list) do
    local sk = sim.skills[name]
    local shown = self.shown[name] or sk.level
    local frac = shown - math.floor(shown)
    local fl = self.flash[name]
    if fl then
      Draw.color(fl > 0.6 and TC.levelup or C.good, math.min(0.35, fl * 0.5))
      love.graphics.rectangle("fill", S.x + 2, y - 1, S.w - 4, S.rowH)
    end
    Draw.text(Progress.name(name), S.x + 5, y, C.text, Assets.fonts.small)
    Draw.text(tostring(sk.level), S.x + 44, y, TC.levelup, Assets.fonts.small, "right", 12)
    local bx, bw = S.x + 60, S.w - 98
    Draw.color(C.textDim, 0.25)
    love.graphics.rectangle("fill", bx, y + 2, bw, 5)
    Draw.color(fl and C.good or C.recovery)
    love.graphics.rectangle("fill", bx, y + 2, bw * frac, 5)
    Draw.text(string.format("%d/%d", math.floor(sk.progress), Training.repsFor(sk.level)), S.x + S.w - 36, y,
      C.textDim, Assets.fonts.small, "right", 32)
    y = y + S.rowH
  end
end

function Hub:_topExtra()
  local sim = self.sim
  if not self:_here() then
    return string.format("In the %s  -  click to go there", TL.roomNames[sim.location]:lower()), HB.accent
  end
  if sim.pace > WORKING then return "Working harder!", TC.coach end
end

function Hub:_topRect()
  local N = HB.top
  return { x = (Layout.width - N.w) / 2, y = N.y, w = N.w, h = self:_topExtra() and 42 or 32 }
end

function Hub:_drawTop()
  local N = HB.top
  local sim, c = self.sim, self.career
  local a = sim.activity
  local r = self:_topRect()
  local x = r.x
  local extra, extraCol = self:_topExtra()
  Draw.panel(x, N.y, N.w, r.h)
  if not self:_here() and not self.overlay and inside(r, self.mx, self.my) then
    Draw.color(HB.accent); love.graphics.rectangle("line", x + 0.5, N.y + 0.5, N.w - 1, r.h - 1)
  end
  Emblem.draw(Emblem.tierFor(c.level, c.champion), x + 13, N.y + 14, 9)
  Draw.text(string.format("%s  -  %s", c.name, c.champion and "World Champion" or Athletes.levels[c.level].title),
    x + 26, N.y + 4, C.text, Assets.fonts.small)
  Draw.text(Training.clockText(sim.clock), x, N.y + 3, C.text, Assets.fonts.normal, "right", N.w - 6)
  local label = a.label
  if a.repsTarget then
    label = string.format("%s  -  %s %d/%d", a.label, a.unit or "rep", math.min(a.reps + 1, a.repsTarget), a.repsTarget)
    if a.reps >= a.repsTarget then label = a.label .. "  -  set done" end
  end
  Draw.text(label, x + 26, N.y + 17, C.text, Assets.fonts.small)
  if extra then Draw.text(extra, x, N.y + 29, extraCol, Assets.fonts.small, "center", N.w) end
end

local function smallButton(r, label, hot, col)
  Draw.color(C.panel)
  love.graphics.rectangle("fill", r.x, r.y, r.w, r.h)
  Draw.color(hot and HB.accent or (col or C.panelEdge), hot and 1 or 0.7)
  love.graphics.rectangle("line", r.x + 0.5, r.y + 0.5, r.w - 1, r.h - 1)
  Draw.text(label, r.x, r.y + math.floor((r.h - 8) / 2) - 1, hot and HB.accent or C.text, Assets.fonts.small, "center", r.w)
end

function Hub:_drawButtons()
  local B = self:_buttons()
  -- icons: your headshot opens the athlete page, the arrow goes back to the title
  local a, m = B.athlete, B.menu
  AthleteView.iconButton(a, inside(a, self.mx, self.my) and not self.overlay, function(col)
    Avatar.draw({ name = self.career.name, you = true }, a.x + a.w / 2, a.y + a.h / 2, 7, 1, col)
  end)
  AthleteView.iconButton(m, inside(m, self.mx, self.my) and not self.overlay, function(col)
    AthleteView.drawArrow(m.x, m.y, m.w, m.h, col)
  end)
end

-- Door tabs at the screen edges: a doorway with the next room's name and an arrow.
function Hub:_drawDoors()
  for _, d in ipairs(self:_doors()) do
    local hot = not self.overlay and inside(d, self.mx, self.my)
    Draw.color(C.panel)
    love.graphics.rectangle("fill", d.x, d.y, d.w, d.h)
    Draw.color(hot and HB.accent or C.panelEdge, hot and 1 or 0.5)
    love.graphics.rectangle("line", d.x + 0.5, d.y + 0.5, d.w - 1, d.h - 1)
    local col = hot and HB.accent or C.text
    Draw.text(d.side < 0 and "<" or ">", d.x, d.y + 4, col, Assets.fonts.normal, "center", d.w)
    local name = TL.roomNames[d.room]:upper()
    for i = 1, #name do
      Draw.text(name:sub(i, i), d.x, d.y + 16 + (i - 1) * 9, col, Assets.fonts.small, "center", d.w)
    end
    if self.sim.location == d.room then              -- he is in there
      Draw.color(C.near)
      love.graphics.circle("fill", d.x + d.w / 2, d.y + d.h - 6, 2.5)
    end
  end
end

-- Lobby: outline the desk / board under the mouse; over the desk, this league's tournament.
-- Lobby hover: the board / counter light up themselves (lobby_view reads view.hover). Over the
-- desk the receptionist turns to you and offers this league's tournament in a speech bubble.
function Hub:_deskBubble()
  local W, H = HB.deskCard.w, HB.deskCard.h
  local hx, hy = Lobby.receptionistHead(self.cam)
  local x = math.floor(math.max(4, math.min(Layout.width - W - 4, hx - W / 2)))
  return { x = x, y = math.floor(hy - H - 8), w = W, h = H, tipX = math.floor(hx), tipY = math.floor(hy - 2) }
end

function Hub:_lobbyHover()
  if self.room ~= "lobby" or self.overlay or self.drag then return nil end
  local B = self:_buttons()
  if self.hover == "desk" and inside(self:_deskBubble(), self.mx, self.my) then return "desk" end
  if inside(B.board, self.mx, self.my) then return "board" end
  if inside(B.desk, self.mx, self.my) then return "desk" end
end

function Hub:_drawLobbyHover()
  if self.hover ~= "desk" then return end
  local c = self.career
  local ev = Career.event(c)
  local b = self:_deskBubble()
  -- speech bubble (white like the others in the world), tail down to her head
  love.graphics.setColor(1, 1, 1)
  love.graphics.rectangle("fill", b.x, b.y, b.w, b.h, 3, 3)
  love.graphics.polygon("fill", b.tipX - 4, b.y + b.h, b.tipX + 4, b.y + b.h, b.tipX, b.tipY)
  Emblem.draw(c.level, b.x + 14, b.y + 15, 9)
  local ink = { 0.10, 0.10, 0.12 }
  Draw.sign(ev.name, b.x + 27, b.y + 3, b.w - 31, 11, ink, Assets.fonts.small)
  Draw.sign(string.format("%d players - starts now", ev.size), b.x + 27, b.y + 14, b.w - 31, 11, { 0.35, 0.36, 0.40 },
    Assets.fonts.small)
  local e = { x = b.x + b.w / 2 - 28, y = b.y + b.h - 15, w = 56, h = 12 }
  Draw.color(HB.accent)
  love.graphics.rectangle("fill", e.x, e.y, e.w, e.h, 2, 2)
  Draw.sign("Enter", e.x, e.y, e.w, e.h, ink, Assets.fonts.small)
end


function Hub:draw()
  local sim = self.sim
  self.view:draw(sim, self.room)
  if self.fade > 0 then              -- changing room: the world dips to black, the panels stay
    love.graphics.setColor(0, 0, 0, self.fade / HB.fade)
    love.graphics.rectangle("fill", 0, 0, Layout.width, Layout.height)
  end
  self:_drawLobbyHover()
  if sim.activity.kind == "home" or sim.activity.kind == "arrive" then
    local a = sim.activity
    local u = a.kind == "home" and math.min(1, a.t / 2) or math.max(0, 1 - a.t / 1.2)
    love.graphics.setColor(0, 0, 0, u * 0.9)
    love.graphics.rectangle("fill", 0, 0, Layout.width, Layout.height)
    if a.kind == "home" and a.t > 1 then
      Draw.text(string.format("Day %d done", sim.day), 0, 160, C.text, Assets.fonts.big, "center", Layout.width)
    end
  end
  self:_drawPlan()
  self:_drawStats()
  self:_drawTop()
  self:_drawDoors()
  self:_drawButtons()
  if self.overlay == "drawer" then self:_drawDrawer() end
  self:_drawDragged()
  if self.toast then
    Draw.text(self.toast.text, 0, HB.hintY - 14, HB.accent, Assets.fonts.small, "center", Layout.width)
  end
  -- the one thing you can't see on screen: clicking him coaches him
  if self:_here() and self.room ~= "lobby" then
    Draw.text("Click to coach", 0, HB.hintY, C.textDim, Assets.fonts.small, "center", Layout.width)
  end
  if self.overlay == "athlete" then self.athleteView:draw(self.mx, self.my) end
end

return Hub
