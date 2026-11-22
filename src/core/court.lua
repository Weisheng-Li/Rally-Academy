-- Court geometry in meters. Pure Lua (no love.*).
-- World coordinates: x = across (screen left is negative), y = along the court.
-- y > 0 is the near half (side = +1), y < 0 is the far half (side = -1), net at y = 0.
local Court = {
  LENGTH = 6.7,              -- net to baseline
  HALF_WIDTH_DOUBLES = 3.05,
  HALF_WIDTH_SINGLES = 2.59,
  SHORT_SERVICE = 1.98,
  LONG_SERVICE_DOUBLES = 5.94,
  NET_HEIGHT = 1.55,
  NET_DEPTH = 0.76,          -- net cloth hangs from the tape down this far
  ZONE_X = 1.85,
  DEPTH_Y = { front = 1.5, mid = 3.6, back = 5.8 },
  BASE_Y = 3.6,
}

-- Zones named from the screen's point of view (left = negative x).
Court.ZONES = {
  { id = "back_left",   label = "Back left",   depth = "back",  lr = -1 },
  { id = "back_right",  label = "Back right",  depth = "back",  lr = 1 },
  { id = "mid_left",    label = "Mid left",    depth = "mid",   lr = -1 },
  { id = "mid_right",   label = "Mid right",   depth = "mid",   lr = 1 },
  { id = "front_left",  label = "Front left",  depth = "front", lr = -1 },
  { id = "front_right", label = "Front right", depth = "front", lr = 1 },
}

function Court.zonePos(zone, side)
  return { x = zone.lr * Court.ZONE_X, y = side * Court.DEPTH_Y[zone.depth] }
end

function Court.depthOf(pos)
  local d = math.abs(pos.y)
  if d < 2.5 then return "front" end
  if d < 4.7 then return "mid" end
  return "back"
end

function Court.basePos(side)
  return { x = 0, y = side * Court.BASE_Y }
end

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

-- Keep a standing spot inside one half (singles width, a little room behind the baseline).
function Court.clampToHalf(pos, side)
  local x = clamp(pos.x, -Court.HALF_WIDTH_SINGLES, Court.HALF_WIDTH_SINGLES)
  local ay = clamp(pos.y * side, 0.4, Court.LENGTH + 0.3)
  return { x = x, y = side * ay }
end

return Court
