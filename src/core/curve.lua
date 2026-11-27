-- Level curves: { [level] = value, ... } with values linearly interpolated between the listed
-- levels and held flat outside them. Pure Lua (no love.*).
local Curve = {}

function Curve.at(t, level)
  local lo, hi
  for k in pairs(t) do
    if k <= level and (not lo or k > lo) then lo = k end
    if k >= level and (not hi or k < hi) then hi = k end
  end
  if not lo then return t[hi] end
  if not hi then return t[lo] end
  if lo == hi then return t[lo] end
  return t[lo] + (t[hi] - t[lo]) * (level - lo) / (hi - lo)
end

return Curve
