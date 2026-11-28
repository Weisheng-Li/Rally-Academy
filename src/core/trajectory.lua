-- Shuttlecock flight physics and shot solvers. Pure Lua (no love.*).
--
-- A shot flies in the vertical plane along its ground direction:
--   s = horizontal distance from the contact point, z = height.
-- Forces: gravity + quadratic drag (the feathers):  a = -g*z_hat - (g / vt^2) * |v| * v
--
-- Shots are defined by the number a coach would use ("spec"):
--   { kind = "apex",  apex = 6.0 }            peak height (clears, lifts)
--   { kind = "net",   clearance = 0.25 }      height over the tape (drops, net shots)
--   { kind = "speed", speed = 45 }            launch speed, low solution (smash, drive)
-- The solver finds the launch angle + speed that lands exactly at the target distance.
local T = {}

local G = 9.81

-- Default settings used by the game. Chosen from tools/bench results (config E):
-- rk2 at 1/60 s is ~6.7x faster than the prototype (euler 1/240 + bisection) and more
-- accurate (worst landing error 2.8 cm vs 27 cm; probabilities within 1.3 pp).
T.config = {
  vt = 6.8,              -- terminal speed of a feather shuttle (m/s)
  netHeight = 1.55,
  method = "rk2",        -- "euler" (semi-implicit) | "rk2" (midpoint) | "rk4"
  dt = 1 / 60,
  solver = "illinois",   -- "bisect" | "illinois" (regula falsi, Illinois variant)
  warmStart = true,      -- reuse the previous inner speed as a starting guess
  bisectInner = 20, bisectOuter = 16,   -- fixed iteration counts for "bisect"
  maxSpeed = 120,
  landTol = 0.005,       -- solver tolerance on landing distance (m)
  targetTol = 0.005,     -- solver tolerance on apex / net height (m)
}

T.stats = { flights = 0, steps = 0 }

function T.resetStats() T.stats.flights, T.stats.steps = 0, 0 end

local sqrt, atan2 = math.sqrt, math.atan2

---------------------------------------------------------------------------- flight

-- Fly a shot. netS = ground distance to the net (or nil).
-- opts.stopAtNet: stop early if it fails to clear the net.
-- opts.stopBeyond: stop early once s passes this distance while still airborne (= out).
-- opts.record: collect {s, z} points for drawing.
-- Returns { land, time, apex, netH, netSlope, descent, hitNet, beyond, points }.
function T.fly(h0, vx, vz, netS, opts, cfg)
  cfg = cfg or T.config
  local k = G / (cfg.vt * cfg.vt)
  local dt = cfg.dt
  local method = cfg.method
  local netHeight = cfg.netHeight
  local stopAtNet = opts and opts.stopAtNet
  local stopBeyond = opts and opts.stopBeyond
  local pts = opts and opts.record and { 0, h0 } or nil

  local s, z, t = 0, h0, 0
  local apex, netH, netSlope = h0, nil, nil
  local steps = 0
  T.stats.flights = T.stats.flights + 1

  while t < 15 do
    local ps, pz, pvx, pvz = s, z, vx, vz
    if method == "rk2" then
      local v = sqrt(vx * vx + vz * vz)
      local ax, az = -k * v * vx, -G - k * v * vz
      local mvx, mvz = vx + ax * dt * 0.5, vz + az * dt * 0.5
      local mv = sqrt(mvx * mvx + mvz * mvz)
      s, z = s + mvx * dt, z + mvz * dt
      vx, vz = vx - k * mv * mvx * dt, vz + (-G - k * mv * mvz) * dt
    elseif method == "rk4" then
      local function acc(ux, uz)
        local v = sqrt(ux * ux + uz * uz)
        return -k * v * ux, -G - k * v * uz
      end
      local a1x, a1z = acc(vx, vz)
      local v2x, v2z = vx + a1x * dt / 2, vz + a1z * dt / 2
      local a2x, a2z = acc(v2x, v2z)
      local v3x, v3z = vx + a2x * dt / 2, vz + a2z * dt / 2
      local a3x, a3z = acc(v3x, v3z)
      local v4x, v4z = vx + a3x * dt, vz + a3z * dt
      local a4x, a4z = acc(v4x, v4z)
      s = s + (vx + 2 * v2x + 2 * v3x + v4x) * dt / 6
      z = z + (vz + 2 * v2z + 2 * v3z + v4z) * dt / 6
      vx = vx + (a1x + 2 * a2x + 2 * a3x + a4x) * dt / 6
      vz = vz + (a1z + 2 * a2z + 2 * a3z + a4z) * dt / 6
    else -- semi-implicit Euler
      local v = sqrt(vx * vx + vz * vz)
      vx, vz = vx - k * v * vx * dt, vz + (-G - k * v * vz) * dt
      s, z = s + vx * dt, z + vz * dt
    end
    t = t + dt
    steps = steps + 1

    if pts then pts[#pts + 1] = s; pts[#pts + 1] = z end

    -- apex: refine between steps when vertical speed changes sign
    if pvz > 0 and vz <= 0 then
      local peak = pz + pvz * pvz / (2 * G)
      if peak > apex then apex = peak end
    end
    if z > apex then apex = z end

    if netS and not netH and ps < netS and s >= netS then
      netH = pz + (z - pz) * (netS - ps) / (s - ps)
      netSlope = (z - pz) / (s - ps)        -- dz/ds where it crosses the net
      if stopAtNet and netH < netHeight then
        T.stats.steps = T.stats.steps + steps
        return { hitNet = true, netH = netH, land = netS, time = t, apex = apex, points = pts }
      end
    end

    if z <= 0 then
      local f = pz / (pz - z)
      local land = ps + (s - ps) * f
      local fvx, fvz = pvx + (vx - pvx) * f, pvz + (vz - pvz) * f
      T.stats.steps = T.stats.steps + steps
      local r = { land = land, time = t - dt + dt * f, apex = apex, netH = netH, netSlope = netSlope,
                  descent = atan2(-fvz, fvx), points = pts }
      if netS and (not netH or netH < netHeight) then r.hitNet = true end
      return r
    end

    if stopBeyond and s > stopBeyond then
      T.stats.steps = T.stats.steps + steps
      return { beyond = true, land = s, time = t, apex = apex, netH = netH, points = pts }
    end
  end
  T.stats.steps = T.stats.steps + steps
  return { land = s, time = t, apex = apex, netH = netH, timeout = true, points = pts }
end

---------------------------------------------------------------------------- root finding

-- Find x in [a, b] with f(x) = 0. f returns value, exact (false = could not evaluate,
-- value only carries the sign). Bisection whenever an endpoint is inexact.
local function root(f, a, fa, ea, b, fb, eb, tol, xtol, maxIter, illinois)
  if fa * fb > 0 then return nil end
  for _ = 1, maxIter do
    local c
    if illinois and ea and eb and fb ~= fa then
      c = (a * fb - b * fa) / (fb - fa)
    else
      c = (a + b) / 2
    end
    local fc, ec = f(c)
    if ec and math.abs(fc) < tol then return c end
    if fc * fb < 0 then
      a, fa, ea = b, fb, eb
    elseif illinois then
      fa = fa * 0.5
    end
    b, fb, eb = c, fc, ec
    if math.abs(b - a) < xtol then break end
  end
  if eb then return b end
  return nil
end

local function bisectFixed(f, a, b, iters)
  local fa = f(a)
  for _ = 1, iters do
    local m = (a + b) / 2
    local fm = f(m)
    if (fm > 0) == (fa > 0) then a, fa = m, fm else b = m end
  end
  return (a + b) / 2
end

---------------------------------------------------------------------------- solvers

local function launch(angle, speed) return speed * math.cos(angle), speed * math.sin(angle) end

-- Speed that lands at `dist` for a fixed angle (landing distance grows with speed).
local function speedFor(h0, angle, dist, netS, cfg, guess)
  local function f(v)
    local vx, vz = launch(angle, v)
    return T.fly(h0, vx, vz, nil, nil, cfg).land - dist, true
  end
  if cfg.solver == "bisect" then
    local v = bisectFixed(f, 0.5, cfg.maxSpeed, cfg.bisectInner)
    if math.abs(f(v)) > 0.05 then return nil end
    return v
  end
  local lo, hi = 0.5, cfg.maxSpeed
  local flo, fhi
  if guess and cfg.warmStart then
    -- bracket around the guess, expanding outward
    local fg = f(guess)
    if math.abs(fg) < cfg.landTol then return guess end
    local step = 1.15
    local other = fg < 0 and guess * step or guess / step
    local fo = f(other)
    local n = 0
    while fo * fg > 0 and n < 12 do
      guess, fg = other, fo
      step = step * 1.3
      other = fg < 0 and math.min(cfg.maxSpeed, guess * step) or math.max(0.5, guess / step)
      fo = f(other)
      n = n + 1
    end
    if fo * fg <= 0 then
      lo, flo, hi, fhi = guess, fg, other, fo
    end
  end
  if not flo then
    flo, fhi = f(lo), f(hi)
  end
  if flo * fhi > 0 then return nil end      -- can't reach that distance at this angle
  return root(f, lo, flo, true, hi, fhi, true, cfg.landTol, 1e-7, 60, true)
end

local function evalSolution(h0, angle, speed, netS, cfg)
  local vx, vz = launch(angle, speed)
  local r = T.fly(h0, vx, vz, netS, nil, cfg)
  r.angle, r.speed = angle, speed
  r.clears = not r.hitNet
  return r
end

-- Outer search over angle for "apex" and "net" specs.
local function solveTwoLevel(h0, dist, netS, spec, cfg)
  local target = spec.kind == "apex" and spec.apex or (cfg.netHeight + spec.clearance)
  local lastSpeed
  local function g(angle)
    local v = speedFor(h0, angle, dist, netS, cfg, lastSpeed)
    if not v then
      -- unreachable: too flat -> treat as too low, too steep -> too high
      return (angle < math.rad(30)) and -1 or 1, false
    end
    lastSpeed = v
    local vx, vz = launch(angle, v)
    local r = T.fly(h0, vx, vz, netS, nil, cfg)
    local val = (spec.kind == "apex") and r.apex or (r.netH or -1)
    return val - target, true
  end
  local a, b = math.rad(-40), math.rad(85)
  local angle
  if cfg.solver == "bisect" then
    angle = bisectFixed(g, a, b, cfg.bisectOuter)
  else
    local fa, ea = g(a)
    local fb, eb = g(b)
    angle = root(g, a, fa, ea, b, fb, eb, cfg.targetTol, 1e-7, 60, true)
    if not angle then return nil end
  end
  local v = speedFor(h0, angle, dist, netS, cfg, lastSpeed)
  if not v then return nil end
  return evalSolution(h0, angle, v, netS, cfg)
end

-- Fixed launch speed, low solution: smallest angle that reaches `dist`.
local function solveSpeed(h0, dist, netS, spec, cfg)
  local speed = math.min(spec.speed, cfg.maxSpeed)
  local function f(angle)
    local vx, vz = launch(angle, speed)
    return T.fly(h0, vx, vz, nil, nil, cfg).land - dist, true
  end
  local a, b = math.rad(-60), math.rad(30)
  local angle
  if cfg.solver == "bisect" then
    angle = bisectFixed(f, a, b, cfg.bisectOuter + 4)
    if math.abs(f(angle)) > 0.05 then return nil end
  else
    local fa, fb = f(a), f(b)
    angle = root(f, a, fa, true, b, fb, true, cfg.landTol, 1e-7, 60, true)
    if not angle then return nil end
  end
  return evalSolution(h0, angle, speed, netS, cfg)
end

-- Solve a shot. Returns a flight result with .angle, .speed, .clears, or nil if impossible.
function T.solve(h0, dist, netS, spec, cfg)
  cfg = cfg or T.config
  if spec.kind == "speed" then return solveSpeed(h0, dist, netS, spec, cfg) end
  return solveTwoLevel(h0, dist, netS, spec, cfg)
end

return T
