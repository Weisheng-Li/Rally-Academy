-- What the shuttle does after it lands: a small cork bounce, then a skid along the floor.
-- Pure Lua (no love.*). Visual only: the point is already decided where it first landed.
--
-- At first impact the cork rebounds a little (vertical restitution) and the floor grabs
-- part of the horizontal speed. Then the shuttle hops / slides:
--   in the air:   a = -g*z_hat - (g / vt^2) * |v| * v        (same drag as in flight)
--   on the floor: decelerates by friction*g plus feather drag until it stops.
-- A hard, flat smash keeps a lot of speed and skids far; a floaty clear lands almost
-- vertically near terminal speed and barely moves.
local Traj = require("src.core.trajectory")

local Skid = {}

Skid.config = {
  keep = 0.45,        -- share of horizontal speed left after the first impact
  bounce = 0.25,      -- vertical restitution of the cork
  minHop = 0.4,       -- m/s; slower rebounds just settle on the floor
  friction = 0.5,     -- sliding friction coefficient (feathers on a court mat)
  stopSpeed = 0.03,   -- m/s; at rest below this
  dt = 1 / 60,
  maxTime = 3.0,
}

local G = 9.81
local sqrt = math.sqrt

-- Landing velocity (m/s) from the last points of a flight path { {x,y,h}, ... } sampled at dt.
function Skid.landingVelocity(path, dt)
  local n = #path
  if n < 3 then return { x = 0, y = 0, z = 0 } end
  local a, b = path[n - 2], path[n - 1]   -- both still in the air (the last one is clamped to 0)
  return { x = (b.x - a.x) / dt, y = (b.y - a.y) / dt, z = (b.h - a.h) / dt }
end

-- Simulate from landing point p with incoming velocity v {x,y,z}.
-- Returns { points = { {x,y,h}, ... }, dt, distance } (points[1] is the landing point).
function Skid.simulate(p, v)
  local c = Skid.config
  local k = G / (Traj.config.vt * Traj.config.vt)
  local dt = c.dt
  local x, y, h = p.x, p.y, 0
  local vx, vy = v.x * c.keep, v.y * c.keep
  local vz = math.abs(v.z) * c.bounce
  if vz < c.minHop then vz = 0 end
  local pts = { { x = x, y = y, h = 0 } }
  local t = 0
  while t < c.maxTime do
    if h > 0 or vz > 0 then
      local s = sqrt(vx * vx + vy * vy + vz * vz)
      vx = vx - k * s * vx * dt
      vy = vy - k * s * vy * dt
      vz = vz - (G + k * s * vz) * dt
      x, y, h = x + vx * dt, y + vy * dt, h + vz * dt
      if h <= 0 then
        h = 0
        vz = math.abs(vz) * c.bounce
        if vz < c.minHop then vz = 0 end
      end
    else
      local s = sqrt(vx * vx + vy * vy)
      if s < c.stopSpeed then break end
      local dec = (c.friction * G + k * s * s) * dt
      local ns = math.max(0, s - dec)
      local avg = (s + ns) / 2
      x, y = x + vx / s * avg * dt, y + vy / s * avg * dt
      vx, vy = vx / s * ns, vy / s * ns
    end
    t = t + dt
    pts[#pts + 1] = { x = x, y = y, h = h }
  end
  local dx, dy = x - p.x, y - p.y
  return { points = pts, dt = dt, distance = sqrt(dx * dx + dy * dy) }
end

return Skid
