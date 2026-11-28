-- The academy lobby, between the court and the gym (doors at the screen edges). The hub's
-- room: the front desk (tournaments) with the receptionist, the whiteboard with today's plan,
-- a small pro shop (slatwall of rackets and shoes, a wood cabinet with racket bags, a
-- stringing machine), the WC and a waiting sofa. Same camera and floor metres as the court
-- and gym; spots and sizes in layout.training.lobby / lobbyLook, colours in training.colors.
-- Drawn by TrainingView:draw (it adds the athlete); the hub uses deskRect / boardRect to make
-- the desk and the board clickable.
local Layout = require("src.config.layout")
local Draw = require("src.view.draw")
local Assets = require("src.view.assets")
local Figure = require("src.view.figure")
local Court = require("src.core.court")
local Emblem = require("src.view.emblem")

local Lobby = {}

local TL = Layout.training
local LS, LK, TC = TL.lobby, TL.lobbyLook, TL.colors
local C = Layout.colors
local HL_ACCENT = Layout.hub.accent     -- hover highlight (same yellow as the hub's)
local KIND_COLOR = { drill = { 0.16, 0.55, 0.43 }, gym = { 0.88, 0.58, 0.22 }, free = { 0.40, 0.62, 0.95 },
                     warmup = { 0.55, 0.60, 0.70 }, cooldown = { 0.55, 0.60, 0.70 }, idle = { 0.82, 0.82, 0.84 } }

local function proj(cam, x, y, h) return cam:project(x, y, h or 0) end

-- Convex hull of screen points { {x, y}, ... } (monotone chain), as a flat x, y list.
local function hull(pts)
  table.sort(pts, function(a, b) return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2]) end)
  local function cross(o, a, b) return (a[1] - o[1]) * (b[2] - o[2]) - (a[2] - o[2]) * (b[1] - o[1]) end
  local lower, upper = {}, {}
  for _, p in ipairs(pts) do
    while #lower >= 2 and cross(lower[#lower - 1], lower[#lower], p) <= 0 do table.remove(lower) end
    lower[#lower + 1] = p
  end
  for i = #pts, 1, -1 do
    local p = pts[i]
    while #upper >= 2 and cross(upper[#upper - 1], upper[#upper], p) <= 0 do table.remove(upper) end
    upper[#upper + 1] = p
  end
  table.remove(lower); table.remove(upper)
  local out = {}
  for _, p in ipairs(lower) do out[#out + 1] = p[1]; out[#out + 1] = p[2] end
  for _, p in ipairs(upper) do out[#out + 1] = p[1]; out[#out + 1] = p[2] end
  return out
end

-- Outline of a box on the floor (centre x/y, half sizes, height), following its silhouette.
local function boxOutline(cam, x, y, hx, hy, h)
  local pts = {}
  for _, sx in ipairs({ -1, 1 }) do
    for _, sy in ipairs({ -1, 1 }) do
      for _, z in ipairs({ 0, h }) do
        local px, py = proj(cam, x + sx * hx, y + sy * hy, z)
        pts[#pts + 1] = { px, py }
      end
    end
  end
  return hull(pts)
end

-- Screen rect around world points { x, y, h }.
local function bounds(cam, pts)
  local x1, y1, x2, y2 = math.huge, math.huge, -math.huge, -math.huge
  for _, p in ipairs(pts) do
    local sx, sy = proj(cam, p[1], p[2], p[3])
    x1, y1, x2, y2 = math.min(x1, sx), math.min(y1, sy), math.max(x2, sx), math.max(y2, sy)
  end
  return { x = x1, y = y1, w = x2 - x1, h = y2 - y1 }
end

-- The front desk counter and the receptionist behind it (click: tournament).
function Lobby.deskRect(cam)
  local D, R = LS.desk, LS.receptionist
  return bounds(cam, { { D.x - D.hx, D.y + D.hy, 0 }, { D.x + D.hx, D.y + D.hy, 0 },
                       { D.x - D.hx, D.y - D.hy, D.h }, { D.x + D.hx, D.y - D.hy, D.h },
                       { R.x - 0.4, R.y, 1.85 }, { R.x + 0.4, R.y, 1.85 } })
end

-- Screen point just above the receptionist's head (the front desk's speech bubble points here).
function Lobby.receptionistHead(cam)
  local R = LS.receptionist
  return proj(cam, R.x, R.y, 1.9)
end

-- The plan whiteboard on the back wall (click: plan the day).
function Lobby.boardRect(cam)
  local B = LS.board
  return bounds(cam, { { B.x1, LS.wallY, B.z1 }, { B.x2, LS.wallY, B.z2 + 0.25 } })
end

-- A rectangle on the back wall: x1..x2, heights z1..z2.
local function wallRect(cam, x1, x2, z1, z2)
  local ax, ay = proj(cam, x1, LS.wallY, z2)
  local bx, by = proj(cam, x2, LS.wallY, z1)
  return ax, ay, bx - ax, by - ay
end

---------------------------------------------------------------------------- floor + wall
local function drawFloorAndWall(view, cam)
  local TV = require("src.view.training_view")
  local HD, L = Court.HALF_WIDTH_DOUBLES, Court.LENGTH
  local wy = LS.wallY
  local a1, a2 = proj(cam, -HD - 8, wy, 0)
  local b1, b2 = proj(cam, HD + 8, wy, 0)
  local c1, c2 = proj(cam, HD + 8, L + 2, 0)
  local d1, d2 = proj(cam, -HD - 8, L + 2, 0)
  Draw.color(TC.lobbyFloor)
  love.graphics.polygon("fill", a1, a2, b1, b2, c1, c2, d1, d2)
  local row = 0
  for y = wy, L + 2, LK.plank do
    row = row + 1
    if row % 2 == 0 then
      Draw.color(TC.lobbyFloorLight)
      love.graphics.polygon("fill", TV.floorRect(cam, 0, y + LK.plank / 2, HD + 8, LK.plank / 2))
    end
    Draw.color(TC.lobbyFloorLine)
    local p1, p2 = proj(cam, -HD - 8, y, 0)
    local q1, q2 = proj(cam, HD + 8, y, 0)
    love.graphics.line(p1, p2, q1, q2)
    for x = -HD - 8 + (row % 3) * LK.plankLen / 3, HD + 8, LK.plankLen do
      local s1, s2 = proj(cam, x, y, 0)
      local t1, t2 = proj(cam, x, y + LK.plank, 0)
      love.graphics.line(s1, s2, t1, t2)
    end
  end
  -- wall, crown trim, baseboard
  Draw.color(TC.lobbyWall)
  love.graphics.rectangle("fill", 0, 0, Layout.width, a2)
  local _, topY = proj(cam, 0, wy, LK.wallTop)
  Draw.color(TC.wallTrim)
  love.graphics.rectangle("fill", 0, topY - 5, Layout.width, 5)
  Draw.color(TC.slatLine)
  love.graphics.rectangle("fill", 0, a2 - 3, Layout.width, 3)
  -- track spotlights along the top
  for _, x in ipairs({ -6.6, -3.9, -1.3, 1.3, 3.9, 6.6 }) do
    local sx, sy = proj(cam, x, wy, LK.wallTop)
    Draw.color(TC.dark)
    love.graphics.rectangle("fill", sx - 3, sy - 3, 6, 5)
    love.graphics.setColor(1, 0.97, 0.85, 0.18)
    love.graphics.polygon("fill", sx - 3, sy + 2, sx + 3, sy + 2, sx + 14, sy + 34, sx - 14, sy + 34)
  end
  -- entrance mat at the street door (bottom of the screen)
  local M = LS.mat
  Draw.color(TC.entryMat)
  love.graphics.polygon("fill", TV.floorRect(cam, M.x, M.y, 0.9, 0.35))
end

---------------------------------------------------------------------------- pro shop wall
local function drawRacketOnWall(cam, x, col)
  local hx, hy = proj(cam, x, LS.wallY, 1.95)
  local bx, by = proj(cam, x, LS.wallY, 1.3)
  local k = Figure.scale(cam, x, LS.wallY)
  local rx, ry = 0.12 * k, 0.2 * k * cam.hs / 0.5
  Draw.color(TC.dark)
  love.graphics.setLineWidth(2)
  love.graphics.line(bx, by, hx, hy + ry)                  -- shaft + handle
  love.graphics.setLineWidth(1)
  love.graphics.setColor(1, 1, 1, 0.55)
  love.graphics.ellipse("fill", hx, hy, rx, ry)            -- strings
  Draw.color(col)
  love.graphics.setLineWidth(2)
  love.graphics.ellipse("line", hx, hy, rx, ry)
  love.graphics.setLineWidth(1)
  love.graphics.rectangle("fill", bx - 1, by - 5, 3, 6)    -- grip
  Draw.color(TC.metal)
  love.graphics.circle("fill", hx, hy - ry - 2, 1)          -- wall hook
end

local function drawShopWall(cam)
  local W = LS.shopWall
  local x, y, w, h = wallRect(cam, W.x1, W.x2, 0, 2.6)
  Draw.color(TC.slat)
  love.graphics.rectangle("fill", x, y, w, h)
  Draw.color(TC.slatLine)
  for z = 0.15, 2.6, 0.15 do
    local _, ly = proj(cam, 0, LS.wallY, z)
    love.graphics.line(x, ly, x + w, ly)
  end
  -- sign
  local sx, sy, sw, sh = wallRect(cam, LK.shopSign.x1, LK.shopSign.x2, 2.2, 2.72)
  sx, sy, sw, sh = math.floor(sx), math.floor(sy), math.floor(sw), math.floor(sh)
  Draw.color(TC.shopSign)
  love.graphics.rectangle("fill", sx, sy, sw, sh)
  Draw.sign("PRO SHOP", sx, sy, sw, sh, C.text, Assets.fonts.normal)
  for i, rx in ipairs(LK.rackets) do drawRacketOnWall(cam, rx, TC.racketFrames[(i - 1) % #TC.racketFrames + 1]) end
  -- shoe shelves (left of the cabinet): little shelves with a pair on each
  local n = 0
  for _, z in ipairs({ 0.55, 0.95 }) do
    for _, sxm in ipairs(LK.shoes) do
      n = n + 1
      local px, py = proj(cam, sxm, LS.wallY, z)
      local qx = proj(cam, sxm + 0.45, LS.wallY, z)
      Draw.color(TC.metal)
      love.graphics.line(px, py, qx, py)
      Draw.color(TC.shoes[(n - 1) % #TC.shoes + 1])
      local sw2 = (qx - px) * 0.42
      love.graphics.rectangle("fill", px + 1, py - 4, sw2, 4, 2, 2)
      love.graphics.rectangle("fill", px + sw2 + 2, py - 4, sw2, 4, 2, 2)
    end
  end
end

---------------------------------------------------------------------------- WC, board, desk sign
local function drawWC(cam)
  local D = LS.wcDoor
  local x, y, w, h = wallRect(cam, D.x1, D.x2, 0, D.h)
  Draw.color(TC.doorFrame)
  love.graphics.rectangle("fill", x - 2, y - 2, w + 4, h + 2)
  Draw.color(TC.door)
  love.graphics.rectangle("fill", x, y, w, h)
  Draw.color(TC.doorFrame)
  love.graphics.rectangle("line", x + 3.5, y + 3.5, w - 7, h * 0.4)
  love.graphics.rectangle("line", x + 3.5, y + h * 0.5, w - 7, h * 0.45)
  Draw.color(TC.metal)
  love.graphics.rectangle("fill", x + w - 6, y + h * 0.52, 3, 2)
  -- WC plate over the door
  local px, py = math.floor(x + w / 2 - 10), math.floor(y - 15)
  Draw.color(TC.desk)
  love.graphics.rectangle("fill", px, py, 20, 11)
  Draw.sign("WC", px, py, 20, 11, C.text, Assets.fonts.small)
end

local function drawBoard(cam, s, hot)
  local B = LS.board
  local x, y, w, h = wallRect(cam, B.x1, B.x2, B.z1, B.z2)
  Draw.sign("TODAY'S PLAN", x, y - 13, w, 11, TC.desk, Assets.fonts.small)
  -- hovered (the hub sets view.hover): the frame lights up and the surface brightens
  Draw.color(hot and HL_ACCENT or TC.boardFrame)
  love.graphics.rectangle("fill", x - 2, y - 2, w + 4, h + 4)
  Draw.color(hot and { 1, 1, 1 } or TC.board)
  love.graphics.rectangle("fill", x, y, w, h)
  -- the day as coloured bars, the running block marked
  local blocks = s.schedule
  local cur
  for _, b in ipairs(blocks) do if s.clock >= b.start and s.clock < b.stop then cur = b end end
  local rh = (h - 4) / #blocks
  for i, b in ipairs(blocks) do
    local by = y + 2 + (i - 1) * rh
    Draw.color(KIND_COLOR[b.kind] or KIND_COLOR.idle)
    love.graphics.rectangle("fill", x + 6, by + 0.5, (w - 10) * (b.kind == "idle" and 0.35 or 0.85), math.max(1, rh - 1.5))
    if b == cur then
      Draw.color(C.bad)
      love.graphics.polygon("fill", x + 1, by, x + 1, by + rh - 1, x + 4, by + (rh - 1) / 2)
    end
  end
  -- marker pen on the ledge
  Draw.color(TC.boardFrame)
  love.graphics.rectangle("fill", x + 4, y + h + 2, w - 8, 2)
  Draw.color(C.bad)
  love.graphics.rectangle("fill", x + w - 16, y + h, 7, 2)
end

local function drawDeskWall(cam)
  local sx, sy, sw, sh = wallRect(cam, LS.deskSign.x1, LS.deskSign.x2, 2.2, 2.72)
  sx, sy, sw, sh = math.floor(sx), math.floor(sy), math.floor(sw), math.floor(sh)
  Draw.color(TC.desk)
  love.graphics.rectangle("fill", sx, sy, sw, sh)
  Draw.sign("FRONT DESK", sx, sy, sw, sh, C.text, Assets.fonts.normal)
end

---------------------------------------------------------------------------- furniture
function Lobby.draw(view, s, items, here)
  local TV = require("src.view.training_view")
  local cam = view.cam
  local box, shade = TV.box, TV.shade
  local a = s.activity
  drawFloorAndWall(view, cam)
  drawShopWall(cam)
  drawWC(cam)
  drawBoard(cam, s, view.hover == "board")
  drawDeskWall(cam)

  -- wood cabinet with drawers, racket bags on top
  local K = LS.cabinet
  items[#items + 1] = { y = K.y, draw = function()
    box(cam, K.x, K.y, K.hx, K.hy, K.h, TC.cabinetTop, TC.cabinet)
    Draw.color(TC.cabinetLine)
    for _, z in ipairs({ 0.3, 0.58 }) do
      local x1, y1 = proj(cam, K.x - K.hx + 0.05, K.y + K.hy, z)
      local x2 = proj(cam, K.x + K.hx - 0.05, K.y + K.hy, z)
      love.graphics.line(x1, y1, x2, y1)
    end
    for _, dx in ipairs({ -0.6, 0, 0.6 }) do
      local hx, hy = proj(cam, K.x + dx, K.y + K.hy, 0.45)
      love.graphics.rectangle("fill", hx - 3, hy - 1, 6, 1.5)
      hx, hy = proj(cam, K.x + dx, K.y + K.hy, 0.72)
      love.graphics.rectangle("fill", hx - 3, hy - 1, 6, 1.5)
    end
    for i, dx in ipairs({ -0.75, 0, 0.75 }) do
      local col = TC.bags[i]
      box(cam, K.x + dx, K.y, 0.3, 0.13, K.h + 0.3, shade(col, 1.15), col, K.h)
      local x1, y1 = proj(cam, K.x + dx - 0.3, K.y + 0.13, K.h + 0.12)
      local x2 = proj(cam, K.x + dx + 0.3, K.y + 0.13, K.h + 0.12)
      love.graphics.setColor(1, 1, 1, 0.6)
      love.graphics.line(x1, y1, x2, y1)
    end
  end }

  -- stringing machine: dark floor pad, red pedestal, turntable with a racket on it
  local S = LS.stringer
  items[#items + 1] = { y = S.y, draw = function()
    Draw.color(TC.entryMat)
    love.graphics.polygon("fill", TV.floorRect(cam, S.x, S.y, 0.45, 0.35))
    box(cam, S.x, S.y, 0.22, 0.16, 0.06, shade(TC.stringer, 0.8), shade(TC.stringer, 0.6))
    box(cam, S.x, S.y, 0.05, 0.05, 0.9, TC.stringer, shade(TC.stringer, 0.7))
    box(cam, S.x, S.y, 0.42, 0.1, 0.96, shade(TC.stringer, 1.1), TC.stringer, 0.9)
    local hx, hy = proj(cam, S.x - 0.1, S.y, 0.99)
    local k = Figure.scale(cam, S.x, S.y)
    love.graphics.setColor(1, 1, 1, 0.7)
    love.graphics.ellipse("line", hx, hy, 0.2 * k, 0.06 * k)
    Draw.color(TC.dark)
    local ex = proj(cam, S.x + 0.4, S.y, 0.99)
    love.graphics.line(hx + 0.2 * k, hy, ex, hy)
  end }

  -- waiting sofa, end-on: long along y, backrest on its left (he sits facing right, as in his
  -- side-on sitting pose), armrests at both ends. Drawn back to front: backrest, far arm,
  -- cushion, near arm.
  local F, FL = LS.sofa, LK.sofa
  items[#items + 1] = { y = F.y - FL.hy, draw = function()
    local bx = F.x - FL.hx + FL.backT / 2
    box(cam, bx, F.y, FL.backT / 2, FL.hy, FL.back, TC.sofaTop, TC.sofa)
    box(cam, F.x + FL.backT / 2, F.y - FL.hy + FL.armT / 2, FL.hx - FL.backT / 2, FL.armT / 2, FL.arm,
      TC.sofaTop, TC.sofa)
    box(cam, F.x + FL.backT / 2, F.y, FL.hx - FL.backT / 2, FL.hy - FL.armT, FL.seat, TC.sofaSeat, TC.sofa)
  end }
  -- the near armrest goes in front of him
  items[#items + 1] = { y = F.y + FL.hy, draw = function()
    box(cam, F.x + FL.backT / 2, F.y + FL.hy - FL.armT / 2, FL.hx - FL.backT / 2, FL.armT / 2, FL.arm,
      TC.sofaTop, TC.sofa)
  end }

  -- plant by the desk
  local P = LS.plant
  items[#items + 1] = { y = P.y, draw = function()
    box(cam, P.x, P.y, 0.18, 0.18, 0.4, TC.potTop, TC.pot)
    local x, y = proj(cam, P.x, P.y, 0.4)
    local kk = Figure.scale(cam, P.x, P.y)
    for i, l in ipairs({ { 0, -0.4, 0.2 }, { -0.15, -0.28, 0.15 }, { 0.15, -0.3, 0.15 }, { 0.02, -0.62, 0.14 } }) do
      Draw.color(i % 2 == 0 and TC.leafDark or TC.leaf)
      love.graphics.circle("fill", x + l[1] * kk, y + l[2] * kk, l[3] * kk)
    end
  end }

  -- water fountain
  local W = LS.fountain
  items[#items + 1] = { y = W.y, draw = function()
    box(cam, W.x, W.y, 0.22, 0.18, 0.95, shade(TC.metal, 0.95), shade(TC.metal, 0.65))
    local x, y = proj(cam, W.x, W.y, 0.95)
    Draw.color(TC.water, 0.8)
    love.graphics.rectangle("fill", x - 4, y - 11, 8, 11)
  end }

  -- receptionist behind the counter (looks at her screen, up when he chats), then the counter
  local R, D = LS.receptionist, LS.desk
  local chatting = here and a.name == "deskchat" and view.arrived
  items[#items + 1] = { y = R.y, draw = function()
    local look = (view.hover == "desk" and { x = 0, y = 1 })          -- looks at you
      or (chatting and { x = view.pos.x - R.x, y = view.pos.y - R.y })
      or ((view.time % 9) < 6 and { x = 1, y = 0.3 } or { x = 0, y = 1 })
    local l = math.sqrt(look.x * look.x + look.y * look.y)
    local st = TV.standing({ x = R.x, y = R.y }, { x = look.x / l, y = look.y / l })
    st.lean = 0.03 * math.sin(view.time * 0.7)
    local f = Figure.stance(cam, st, -1)
    view:drawBody(f, 0, TC.receptionShirt, { racket = false })
    if chatting and s.feederBubble then
      TV.bubble(s.feederBubble.text, f.head.x, f.head.y - f.head.r - 2, s.feederBubble.t * 3)
    end
  end }
  items[#items + 1] = { y = D.y, draw = function()
    box(cam, D.x, D.y, D.hx, D.hy, D.h, TC.deskTop, TC.desk)
    -- green band along the front
    local x1, y1 = proj(cam, D.x - D.hx, D.y + D.hy, 0.62)
    local x2, y2 = proj(cam, D.x + D.hx, D.y + D.hy, 0.78)
    Draw.color(TC.deskPanel)
    love.graphics.rectangle("fill", x1, y2, x2 - x1, y1 - y2)
    -- this league's emblem on the front (its tournament is signed up for here)
    if view.emblemTier then
      local ex, ey = proj(cam, D.x, D.y + D.hy, 0.7)
      Emblem.draw(view.emblemTier, ex, ey, 8)
    end
    -- monitor and a bell on the counter
    box(cam, D.x + 0.7, D.y - 0.15, 0.2, 0.03, D.h + 0.32, TC.dark, TC.dark, D.h + 0.08)
    local bx, by = proj(cam, D.x - 0.6, D.y + 0.1, D.h)
    Draw.color(TC.trophy)
    love.graphics.arc("fill", bx, by, 3, math.pi, 2 * math.pi)
    if view.hover == "desk" then           -- hovered: the counter's own outline lights up
      Draw.color(HL_ACCENT)
      love.graphics.setLineWidth(1)
      love.graphics.polygon("line", boxOutline(cam, D.x, D.y, D.hx, D.hy, D.h))
    end
  end }
end

return Lobby
