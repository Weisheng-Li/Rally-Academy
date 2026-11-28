-- League emblems: a bevelled hexagon frame in the league's material with a gem inside that
-- grows with the league (Bronze: empty, Silver/Gold: faceted gem, Platinum: star,
-- Emerald: emerald, Diamond and World Champion: diamond). Colours in layout.lua `emblems`.
--
-- Emblem.geometry is pure (no love.*) so tests can check it; Emblem.draw paints it.
local Layout = require("src.config.layout")

local Emblem = {}

local LIGHT = math.rad(-120)           -- light from the top left
local function lit(a) return math.cos(a - LIGHT) end

local function ring(R, n, rot)
  local pts = {}
  for i = 0, n - 1 do
    local t = math.rad(rot + i * 360 / n)
    pts[#pts + 1] = { R * math.cos(t), R * math.sin(t) }
  end
  return pts
end

local function flat(pts, s)
  local out = {}
  for _, p in ipairs(pts) do out[#out + 1] = p[1] * s; out[#out + 1] = p[2] * s end
  return out
end

-- Polygons for an emblem of outer radius r (px), centred on 0,0. Each polygon:
-- { pts = {x1,y1,...}, part = "frame" | "hole" | "gem" | "shine", shade = -1..1 }
-- tier: 1-6 (league), 7 = World Champion.
function Emblem.geometry(tier, r)
  local s = r / 46                    -- designed at r = 46
  local polys = {}
  local function add(pts, part, shade) polys[#polys + 1] = { pts = flat(pts, s), part = part, shade = shade } end
  local function facets(outer, center, amt)
    for i = 1, #outer do
      local a, b = outer[i], outer[i % #outer + 1]
      local mid = math.atan2((a[2] + b[2]) / 2 - center[2], (a[1] + b[1]) / 2 - center[1])
      add({ center, a, b }, "gem", lit(mid) * amt)
    end
  end
  local function band(outer, inner, part, amt)
    for i = 1, #outer do
      local j = i % #outer + 1
      local mid = math.atan2((outer[i][2] + outer[j][2]) / 2, (outer[i][1] + outer[j][1]) / 2)
      add({ outer[i], outer[j], inner[j], inner[i] }, part, lit(mid) * amt)
    end
  end
  band(ring(46, 6, -90), ring(34, 6, -90), "frame", 0.85)
  add(ring(34, 6, -90), "hole", 0)
  local gem = Emblem.GEMS[tier]
  if gem == "small" or gem == "large" then
    facets(ring(gem == "small" and 11 or 21, 6, -90), { 0, 0 }, 0.75)
  elseif gem == "star" then
    local pts = {}
    for i = 0, 9 do
      local rr, a = i % 2 == 1 and 9.5 or 23, math.rad(-90 + i * 36)
      pts[#pts + 1] = { rr * math.cos(a), rr * math.sin(a) }
    end
    facets(pts, { 0, 1 }, 0.8)
  elseif gem == "emerald" then
    local o, n = ring(24, 6, -90), ring(12, 6, -90)
    band(o, n, "gem", 0.8)
    add(n, "gem", 0.35)
    add({ { -5, -9 }, { 2, -11 }, { -2, -3 } }, "shine", 0)
  elseif gem == "diamond" then
    local L, R, TL, TR, B, ML, MR = { -23, -5 }, { 23, -5 }, { -12, -16 }, { 12, -16 }, { 0, 21 }, { -7, -5 }, { 7, -5 }
    add({ TL, TR, MR, ML }, "gem", 0.55)
    add({ L, TL, ML }, "gem", 0.3); add({ TR, R, MR }, "gem", 0.1)
    add({ L, ML, B }, "gem", 0.05); add({ ML, MR, B }, "gem", 0.35); add({ MR, R, B }, "gem", -0.3)
    add({ { -9, -13 }, { -3, -13 }, { -6, -8 } }, "shine", 0)
  end
  return polys
end

-- What sits inside the frame, by tier (1-6 leagues, 7 = World Champion).
Emblem.GEMS = { "none", "small", "large", "star", "emerald", "diamond", "diamond" }

local function shade(c, k)
  local t = math.min(1, math.abs(k)) * 0.55
  local to = k > 0 and 1 or 0
  return c[1] + (to - c[1]) * t, c[2] + (to - c[2]) * t, c[3] + (to - c[3]) * t
end

-- Draw at (x, y), outer radius r. alpha optional. tier 7 = World Champion.
function Emblem.draw(tier, x, y, r, alpha)
  local E = Layout.emblems
  local m = E.tiers[tier]
  alpha = alpha or 1
  love.graphics.push()
  love.graphics.translate(x, y)
  for _, p in ipairs(Emblem.geometry(tier, r)) do
    if p.part == "frame" then
      local cr, cg, cb = shade(m.frame, p.shade); love.graphics.setColor(cr, cg, cb, alpha)
    elseif p.part == "hole" then
      love.graphics.setColor(E.hole[1], E.hole[2], E.hole[3], alpha)
    elseif p.part == "gem" then
      local cr, cg, cb = shade(m.gem or m.frame, p.shade); love.graphics.setColor(cr, cg, cb, alpha)
    else
      love.graphics.setColor(1, 1, 1, 0.6 * alpha)
    end
    love.graphics.polygon("fill", p.pts)
  end
  love.graphics.pop()
end

-- League (1-6) -> tier, with the World Champion tier once he has won it all.
function Emblem.tierFor(level, champion) return champion and 7 or level end

return Emblem
