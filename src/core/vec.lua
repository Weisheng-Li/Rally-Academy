-- Tiny 2D vector helpers on plain {x, y} tables. Pure Lua (no love.*).
local V = {}

function V.new(x, y) return { x = x, y = y } end
function V.copy(a) return { x = a.x, y = a.y } end

function V.dist(a, b)
  local dx, dy = b.x - a.x, b.y - a.y
  return math.sqrt(dx * dx + dy * dy)
end

function V.lerp(a, b, t)
  return { x = a.x + (b.x - a.x) * t, y = a.y + (b.y - a.y) * t }
end

-- Move a toward b by at most maxDist. Returns new point and whether b was reached.
function V.moveToward(a, b, maxDist)
  local d = V.dist(a, b)
  if d <= maxDist or d == 0 then return { x = b.x, y = b.y }, true end
  return V.lerp(a, b, maxDist / d), false
end

return V
