-- League emblem geometry (src/view/emblem.lua): the gem sits inside the frame's hole and
-- grows with the league.
local Emblem = require("src.view.emblem")

local function maxRadius(polys, part)
  local m = 0
  for _, p in ipairs(polys) do
    if p.part == part then
      for i = 1, #p.pts, 2 do m = math.max(m, math.sqrt(p.pts[i] ^ 2 + p.pts[i + 1] ^ 2)) end
    end
  end
  return m
end

return {
  ["every tier fits its radius and the gem stays inside the hole"] = function(t)
    local r = 40
    for tier = 1, 7 do
      local g = Emblem.geometry(tier, r)
      t:near(maxRadius(g, "frame"), r, 1e-6, "frame radius tier " .. tier)
      local hole = maxRadius(g, "hole")
      t:ok(hole < r, "hole inside frame tier " .. tier)
      t:ok(maxRadius(g, "gem") < hole, "gem inside hole tier " .. tier)
      for _, p in ipairs(g) do t:ok(#p.pts >= 6 and #p.pts % 2 == 0, "polygon has 3+ points") end
    end
  end,

  ["bronze is empty, then the gem grows"] = function(t)
    t:ok(maxRadius(Emblem.geometry(1, 40), "gem") == 0, "bronze has no gem")
    t:ok(maxRadius(Emblem.geometry(2, 40), "gem") < maxRadius(Emblem.geometry(3, 40), "gem"), "silver gem < gold gem")
    t:ok(Emblem.GEMS[7] == "diamond", "World Champion keeps the diamond")
  end,

  ["geometry never touches love"] = function(t)
    -- geometry() must work without love (draw() is the only part that paints)
    local saved = love
    love = nil
    local ok = pcall(Emblem.geometry, 6, 20)
    love = saved
    t:ok(ok, "geometry runs without love")
  end,
}
