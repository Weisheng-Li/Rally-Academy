-- Monte Carlo shot evaluation on top of trajectory.lua. Pure Lua (no love.*).
--
-- 1. Solve the intended shot (contact -> target) for its spec.
-- 2. Apply N fixed "hand shake" samples (launch angle, ground direction, speed) and
--    classify each: net / long / wide / in.
--
-- Two ways to do step 2 (see tools/bench for speed + accuracy):
--   "full"       fly every sample through the physics (most exact, slowest)
--   "surrogate"  fly 6 probe shots around the intended one, fit a small quadratic
--                formula for landing distance / net height / flight time, then evaluate
--                the samples on that formula (no flights per sample)
-- Samples come from a fixed set so numbers are stable: "random" (pseudo-random) or
-- "halton" (quasi-random: spreads points evenly, less sampling noise for the same N).
local Traj = require("src.core.trajectory")
local Court = require("src.core.court")

local SM = {}

-- Defaults used by the game. Chosen from tools/bench results (method M6):
-- 2.8x faster than flying 150 random samples, and ~4x more accurate (mean success error
-- 0.39 pp vs 1.48 pp against 4096-sample ground truth).
SM.defaults = { method = "surrogate", sampleKind = "halton", sampleCount = 1024, probeStep = 1.5 }

---------------------------------------------------------------------------- samples

-- Inverse of the standard normal CDF (Acklam's rational approximation, |error| < 1.2e-9).
local function invNorm(p)
  local a = { -3.969683028665376e+01, 2.209460984245205e+02, -2.759285104469687e+02,
              1.383577518672690e+02, -3.066479806614716e+01, 2.506628277459239e+00 }
  local b = { -5.447609879822406e+01, 1.615858368580409e+02, -1.556989798598866e+02,
              6.680131188771972e+01, -1.328068155288572e+01 }
  local c = { -7.784894002430293e-03, -3.223964580411365e-01, -2.400758277161838e+00,
              -2.549732539343734e+00, 4.374664141464968e+00, 2.938163982698783e+00 }
  local d = { 7.784695709041462e-03, 3.224671290700398e-01, 2.445134137142996e+00, 3.754408661907416e+00 }
  local lo, hi = 0.02425, 1 - 0.02425
  if p < lo then
    local q = math.sqrt(-2 * math.log(p))
    return (((((c[1] * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5]) * q + c[6]) /
           ((((d[1] * q + d[2]) * q + d[3]) * q + d[4]) * q + 1)
  elseif p <= hi then
    local q = p - 0.5
    local r = q * q
    return (((((a[1] * r + a[2]) * r + a[3]) * r + a[4]) * r + a[5]) * r + a[6]) * q /
           (((((b[1] * r + b[2]) * r + b[3]) * r + b[4]) * r + b[5]) * r + 1)
  else
    local q = math.sqrt(-2 * math.log(1 - p))
    return -(((((c[1] * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5]) * q + c[6]) /
            ((((d[1] * q + d[2]) * q + d[3]) * q + d[4]) * q + 1)
  end
end

local function halton(i, base)
  local f, r = 1, 0
  while i > 0 do
    f = f / base
    r = r + f * (i % base)
    i = math.floor(i / base)
  end
  return r
end

local function makeSamples(kind, n)
  local out = {}
  if kind == "halton" then
    for i = 1, n do
      out[i] = { a = invNorm(halton(i, 2)), d = invNorm(halton(i, 3)), s = invNorm(halton(i, 5)) }
    end
  else
    local state = 20261122
    local function rand()
      state = (state * 16807) % 2147483647          -- Park-Miller: exact in doubles
      return state / 2147483647
    end
    local function normal()
      local u1, u2 = rand(), rand()
      return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
    end
    for i = 1, n do out[i] = { a = normal(), d = normal(), s = normal() } end
  end
  return out
end

local cache = {}
function SM.samples(kind, n)
  local key = kind .. n
  if not cache[key] then cache[key] = makeSamples(kind, n) end
  return cache[key]
end

---------------------------------------------------------------------------- geometry

local HALF_W, LEN = Court.HALF_WIDTH_SINGLES, Court.LENGTH

-- Default landing area: the receiver's whole singles half.
SM.FULL_HALF = { xMin = -HALF_W, xMax = HALF_W, yMin = 0, yMax = LEN }

-- Distance along a ground ray until it leaves the receiver's half (singles lines).
local function exitDistance(cx, cy, ux, uy, recvSide)
  local sBase = (recvSide * LEN - cy) / uy
  local sSide = math.huge
  if ux > 1e-9 then sSide = (HALF_W - cx) / ux elseif ux < -1e-9 then sSide = (-HALF_W - cx) / ux end
  if sSide < sBase then return sSide, "wide" end
  return sBase, "long"
end

---------------------------------------------------------------------------- surrogate

-- Quadratic fit of q(u, v) from values at (0,0), (+-1,0), (0,+-1), (1,1).
local function fitQuad(q0, qp0, qm0, q0p, q0m, qpp)
  local qa, qs = (qp0 - qm0) / 2, (q0p - q0m) / 2
  local qaa, qss = qp0 - 2 * q0 + qm0, q0p - 2 * q0 + q0m
  local qas = qpp - q0 - qa - qs - 0.5 * qaa - 0.5 * qss
  return { q0, qa, qs, 0.5 * qaa, 0.5 * qss, qas }
end

local function evalQuad(c, u, v)
  return c[1] + c[2] * u + c[3] * v + c[4] * u * u + c[5] * v * v + c[6] * u * v
end

local PROBES = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 } }

local function buildSurrogate(sol, h0, netS, wobble, step, cfg)
  local ha, hs = step * wobble.angle, step * wobble.speed
  local L, N, Tm = { sol.land }, { sol.netH or -1 }, { sol.time }
  for i, p in ipairs(PROBES) do
    local angle = sol.angle + p[1] * ha
    local speed = sol.speed * (1 + p[2] * hs)
    local r = Traj.fly(h0, speed * math.cos(angle), speed * math.sin(angle), netS, nil, cfg)
    L[i + 1], N[i + 1], Tm[i + 1] = r.land, r.netH or -1, r.time
  end
  return {
    land = fitQuad(L[1], L[2], L[3], L[4], L[5], L[6]),
    net = fitQuad(N[1], N[2], N[3], N[4], N[5], N[6]),
    time = fitQuad(Tm[1], Tm[2], Tm[3], Tm[4], Tm[5], Tm[6]),
    slope = sol.netSlope or 0,
    step = step,
  }
end

---------------------------------------------------------------------------- evaluate

-- contact/target: world {x, y}; h0: contact height; spec: trajectory spec;
-- wobble: { angle = rad, dir = rad, speed = fraction } standard deviations.
-- opts: { method, sampleKind, sampleCount, samples, earlyStop, keepLandings, probeStep }
function SM.evaluate(contact, h0, target, spec, wobble, cfg, opts)
  opts = opts or {}
  cfg = cfg or Traj.config
  local method = opts.method or SM.defaults.method
  local samples = opts.samples or SM.samples(opts.sampleKind or SM.defaults.sampleKind,
    opts.sampleCount or SM.defaults.sampleCount)
  local earlyStop = opts.earlyStop ~= false
  local netHeight = cfg.netHeight

  local dx, dy = target.x - contact.x, target.y - contact.y
  local dist = math.sqrt(dx * dx + dy * dy)
  local ux, uy = dx / dist, dy / dist
  local recvSide = target.y < 0 and -1 or 1
  local netS = -contact.y / uy

  local sol = opts.solution or Traj.solve(h0, dist, netS, spec, cfg)
  if not sol then return { available = false, reason = "no trajectory" } end
  if not sol.clears then return { available = false, reason = "can't clear the net", solution = sol } end

  -- Allowed landing area on the receiver's side (|y| measured from the net).
  local court = opts.court or SM.FULL_HALF
  local function classify(px, py)
    local ay = py * recvSide
    if ay > court.yMax then return "long" end
    if ay < court.yMin then return "short" end     -- before wide: a short serve that drifts across is called short
    if px < court.xMin or px > court.xMax then return "wide" end
    return "in"
  end

  local sur
  if method == "surrogate" then
    sur = buildSurrogate(sol, h0, netS, wobble, opts.probeStep or SM.defaults.probeStep, cfg)
  end

  local counts = { net = 0, long = 0, wide = 0, short = 0, ["in"] = 0 }
  local landings = opts.keepLandings and {} or nil
  local cos, sin = math.cos, math.sin

  for _, smp in ipairs(samples) do
    local phi = smp.d * wobble.dir
    local c, s = cos(phi), sin(phi)
    local wx, wy = ux * c - uy * s, ux * s + uy * c
    local nS = -contact.y / wy
    local exitS, exitKind = exitDistance(contact.x, contact.y, wx, wy, recvSide)
    local land, time, isNet

    if sur then
      local u, v = smp.a / sur.step, smp.s / sur.step
      land = evalQuad(sur.land, u, v)
      local nh = evalQuad(sur.net, u, v) + sur.slope * (nS - netS)
      isNet = nh < netHeight or land < nS
      time = evalQuad(sur.time, u, v)
    else
      local angle = sol.angle + smp.a * wobble.angle
      local speed = sol.speed * (1 + smp.s * wobble.speed)
      local r = Traj.fly(h0, speed * cos(angle), speed * sin(angle), nS,
        earlyStop and { stopAtNet = true, stopBeyond = exitS } or nil, cfg)
      isNet = r.hitNet
      land = r.beyond and math.huge or r.land
      time = r.time
    end

    if isNet then
      counts.net = counts.net + 1
    elseif land == math.huge then
      counts[exitKind] = counts[exitKind] + 1
    else
      local px, py = contact.x + wx * land, contact.y + wy * land
      local kind = classify(px, py)
      counts[kind] = counts[kind] + 1
      if landings and kind == "in" then
        landings[#landings + 1] = { x = px, y = py, time = time }
      end
    end
  end

  local n = #samples
  return {
    available = true,
    success = counts["in"] / n,
    pNet = counts.net / n, pLong = counts.long / n, pWide = counts.wide / n, pShort = counts.short / n,
    solution = sol, distance = dist, landings = landings, netS = netS, dir = { x = ux, y = uy },
    classify = classify,
  }
end

return SM
