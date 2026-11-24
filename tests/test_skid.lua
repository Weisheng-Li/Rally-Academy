-- After landing the shuttle bounces / skids (core/skid.lua).
local Skid = require("src.core.skid")
local Traj = require("src.core.trajectory")

local P = { x = 0, y = -5 }
local SMASH = { x = 0, y = -16, z = -5 }     -- fast and flat
local CLEAR = { x = 0, y = -1.5, z = -6.5 }  -- near terminal speed, almost vertical

return {
  ["a hard flat landing skids much farther than a floaty one"] = function(t)
    local smash, clear = Skid.simulate(P, SMASH), Skid.simulate(P, CLEAR)
    t:ok(smash.distance > 1.0, string.format("smash should skid > 1 m (got %.2f)", smash.distance))
    t:ok(clear.distance < 0.3, string.format("clear should barely move (got %.2f)", clear.distance))
  end,

  ["skids along the landing direction and ends at rest on the floor"] = function(t)
    local s = Skid.simulate(P, { x = 6, y = -8, z = -4 })
    local last = s.points[#s.points]
    t:near(last.h, 0, 1e-9, "on the floor")
    t:ok(last.x > P.x and last.y < P.y, "moved along the incoming direction")
    t:near((last.x - P.x) / (P.y - last.y), 6 / 8, 1e-6, "straight along it")
    t:ok(#s.points * s.dt < 1.4, "done before the point pause ends")
  end,

  ["the cork bounces, never goes below the floor"] = function(t)
    local s = Skid.simulate(P, SMASH)
    local top = 0
    for _, p in ipairs(s.points) do
      t:ok(p.h >= 0, "below the floor")
      top = math.max(top, p.h)
    end
    t:ok(top > 0.01 and top < 0.5, string.format("small hop (got %.3f m)", top))
  end,

  ["landing velocity read from a real smash path"] = function(t)
    local r = Traj.fly(2.6, 44.3, -7.8, nil, { record = true })
    local pts = {}
    for i = 1, #r.points, 2 do pts[#pts + 1] = { x = 0, y = -r.points[i], h = math.max(0, r.points[i + 1]) } end
    local v = Skid.landingVelocity(pts, Traj.config.dt)
    t:ok(v.y < -5 and v.z < 0, string.format("forward and down (vy %.1f, vz %.1f)", v.y, v.z))
  end,
}
