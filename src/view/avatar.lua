-- Player portraits: a round badge with the player's head and shoulders. Everyone shares the
-- same face for now; the shirt colour tells them apart (you: your blue). Used by the
-- tournament bracket; drawn players get their own looks later.
local Layout = require("src.config.layout")
local Draw = require("src.view.draw")

local Avatar = {}

local C = Layout.colors
local SHIRTS = Layout.hall.colors.shirts
local SKIN = { 0.95, 0.80, 0.65 }
local BG = { 0.13, 0.15, 0.20 }

-- Shirt colour for a player: yours, or one picked from the name (same name, same colour).
function Avatar.color(p)
  if p.you then return C.near end
  local h = 0
  for i = 1, #p.name do h = (h * 31 + p.name:byte(i)) % 9973 end
  return SHIRTS[h % #SHIRTS + 1]
end

-- Badge of radius r at (x, y). alpha dims knocked-out players; ring = outline colour or nil.
function Avatar.draw(p, x, y, r, alpha, ring)
  alpha = alpha or 1
  Draw.color(BG, alpha)
  love.graphics.circle("fill", x, y, r)
  love.graphics.stencil(function() love.graphics.circle("fill", x, y, r) end, "replace", 1)
  love.graphics.setStencilTest("greater", 0)
  Draw.color(Avatar.color(p), alpha)
  love.graphics.ellipse("fill", x, y + r * 0.95, r * 0.8, r * 0.55)       -- shoulders
  Draw.color(SKIN, alpha)
  love.graphics.circle("fill", x, y - r * 0.12, r * 0.42)                 -- head
  love.graphics.setStencilTest()
  if ring then
    Draw.color(ring, alpha)
    love.graphics.setLineWidth(1)
    love.graphics.circle("line", x, y, r)
  end
end

-- An empty seat: a dashed ring (nobody there yet).
function Avatar.empty(x, y, r, col, alpha)
  Draw.color(col or C.textDim, alpha or 0.5)
  love.graphics.setLineWidth(1)
  local n = math.max(8, math.floor(r * 1.6))
  for i = 0, n - 1, 2 do
    local a1, a2 = i / n * 2 * math.pi, (i + 1) / n * 2 * math.pi
    love.graphics.line(x + math.cos(a1) * r, y + math.sin(a1) * r, x + math.cos(a2) * r, y + math.sin(a2) * r)
  end
end

return Avatar
