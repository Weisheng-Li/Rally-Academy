-- Trajectory + Monte Carlo benchmark: speed AND accuracy of each algorithm choice.
--
--   Part 1  Trajectory solver/integrator configs vs a reference (RK4, dt 1/4000, tight tolerances)
--   Part 2  Monte Carlo methods vs "ground truth" probabilities
--           (fine integrator, 4096 quasi-random samples, every sample flown)
--
-- Run from the repo root:   lovec tools/bench
-- Writes tools/bench/results.md and prints the same report.
package.path = "./?.lua;" .. package.path

local Traj = require("src.core.trajectory")
local SM = require("src.core.shot_model")
local CASES = require("tools.bench.cases")

local TARGETS_PER_DECISION = 6
local WOBBLES = {
  { name = "skilled", w = { angle = math.rad(1.0), dir = math.rad(1.5), speed = 0.04 } },
  { name = "rookie",  w = { angle = math.rad(2.5), dir = math.rad(3.5), speed = 0.10 } },
}

local function cfgWith(over)
  local c = {}
  for k, v in pairs(Traj.config) do c[k] = v end
  for k, v in pairs(over) do c[k] = v end
  return c
end

local REF = cfgWith({ method = "rk4", dt = 1 / 4000, solver = "illinois", warmStart = false,
                      landTol = 1e-6, targetTol = 1e-6 })
local TRUTH_CFG = cfgWith({ method = "rk2", dt = 1 / 480, landTol = 1e-5, targetTol = 1e-5 })
local TRUTH_OPTS = { method = "full", sampleKind = "halton", sampleCount = 4096, earlyStop = false }

local TRAJ_CONFIGS = {
  { name = "A prototype: euler 1/240 + bisection",  cfg = cfgWith({ method = "euler", dt = 1 / 240, solver = "bisect", warmStart = false }) },
  { name = "B euler 1/240 + illinois",               cfg = cfgWith({ method = "euler", dt = 1 / 240, solver = "illinois", warmStart = false }) },
  { name = "C euler 1/240 + illinois + warm start",  cfg = cfgWith({ method = "euler", dt = 1 / 240, solver = "illinois", warmStart = true }) },
  { name = "D rk2 1/120 + illinois + warm start",    cfg = cfgWith({ method = "rk2", dt = 1 / 120 }) },
  { name = "E rk2 1/60 + illinois + warm start",     cfg = cfgWith({ method = "rk2", dt = 1 / 60 }) },
  { name = "F rk2 1/30 + illinois + warm start",     cfg = cfgWith({ method = "rk2", dt = 1 / 30 }) },
}

local MC_METHODS = {
  { name = "M1 full, random 150 (previous)", opts = { method = "full", sampleKind = "random", sampleCount = 150 } },
  { name = "M2 full, halton 150",            opts = { method = "full", sampleKind = "halton", sampleCount = 150 } },
  { name = "M3 full, halton 64",             opts = { method = "full", sampleKind = "halton", sampleCount = 64 } },
  { name = "M4 surrogate, halton 64",        opts = { method = "surrogate", sampleKind = "halton", sampleCount = 64 } },
  { name = "M5 surrogate, halton 256",       opts = { method = "surrogate", sampleKind = "halton", sampleCount = 256 } },
  { name = "M6 surrogate, halton 1024",      opts = { method = "surrogate", sampleKind = "halton", sampleCount = 1024 } },
}

local now = (love and love.timer) and love.timer.getTime or os.clock

local function geometry(c)
  local dx, dy = c.to.x - c.from.x, c.to.y - c.from.y
  local dist = math.sqrt(dx * dx + dy * dy)
  return dist, -c.from.y / (dy / dist)
end

local function timeIt(fn, minTime)
  fn() -- warm up JIT
  local n, t0 = 0, now()
  repeat fn(); n = n + 1 until now() - t0 >= minTime
  return (now() - t0) / n
end

local out = {}
local function emit(s) out[#out + 1] = s; print(s) end
local function pct(x) return x * 100 end

---------------------------------------------------------------------------- Part 1: trajectory
local geo, refSol = {}, {}
for i, c in ipairs(CASES) do
  local dist, netS = geometry(c)
  geo[i] = { dist = dist, netS = netS }
  refSol[i] = Traj.solve(c.h0, dist, netS, c.spec, REF)
end

local trajRows = {}
for _, conf in ipairs(TRAJ_CONFIGS) do
  local cfg = conf.cfg
  local acc = { land = 0, net = 0, apex = 0, time = 0, avail = 0 }
  for i, c in ipairs(CASES) do
    local sol = Traj.solve(c.h0, geo[i].dist, geo[i].netS, c.spec, cfg)
    if (sol and sol.clears or false) ~= (refSol[i] and refSol[i].clears or false) then acc.avail = acc.avail + 1 end
    if sol and refSol[i] then
      local truth = Traj.fly(c.h0, sol.speed * math.cos(sol.angle), sol.speed * math.sin(sol.angle), geo[i].netS, nil, REF)
      acc.land = math.max(acc.land, math.abs(truth.land - geo[i].dist))
      if truth.netH and sol.netH then acc.net = math.max(acc.net, math.abs(truth.netH - sol.netH)) end
      acc.apex = math.max(acc.apex, math.abs(truth.apex - sol.apex))
      acc.time = math.max(acc.time, math.abs(truth.time - sol.time))
    end
  end
  local t = timeIt(function()
    for i, c in ipairs(CASES) do Traj.solve(c.h0, geo[i].dist, geo[i].netS, c.spec, cfg) end
  end, 0.3) / #CASES
  Traj.resetStats()
  for i, c in ipairs(CASES) do Traj.solve(c.h0, geo[i].dist, geo[i].netS, c.spec, cfg) end
  trajRows[#trajRows + 1] = { name = conf.name, ms = t * 1000 * TARGETS_PER_DECISION,
                              flights = Traj.stats.flights / #CASES, acc = acc }
end

---------------------------------------------------------------------------- Part 2: Monte Carlo
local truth = {}
for wi, wob in ipairs(WOBBLES) do
  truth[wi] = {}
  for i, c in ipairs(CASES) do
    truth[wi][i] = SM.evaluate(c.from, c.h0, c.to, c.spec, wob.w, TRUTH_CFG, TRUTH_OPTS)
  end
end

local mcRows = {}
for _, m in ipairs(MC_METHODS) do
  local maxErr, sumErr, n = { 0, 0 }, 0, 0
  for wi, wob in ipairs(WOBBLES) do
    for i, c in ipairs(CASES) do
      local r, t = SM.evaluate(c.from, c.h0, c.to, c.spec, wob.w, Traj.config, m.opts), truth[wi][i]
      if r.available and t.available then
        local e = math.max(math.abs(r.success - t.success), math.abs(r.pNet - t.pNet),
          math.abs(r.pLong - t.pLong), math.abs(r.pWide - t.pWide))
        maxErr[wi] = math.max(maxErr[wi], e)
        sumErr = sumErr + math.abs(r.success - t.success)
        n = n + 1
      end
    end
  end
  local w = WOBBLES[2].w
  local ms = timeIt(function()
    for _, c in ipairs(CASES) do SM.evaluate(c.from, c.h0, c.to, c.spec, w, Traj.config, m.opts) end
  end, 0.4) / #CASES * 1000 * TARGETS_PER_DECISION
  Traj.resetStats()
  for _, c in ipairs(CASES) do SM.evaluate(c.from, c.h0, c.to, c.spec, w, Traj.config, m.opts) end
  mcRows[#mcRows + 1] = { name = m.name, ms = ms, flights = Traj.stats.flights / #CASES,
                          maxSkilled = maxErr[1], maxRookie = maxErr[2], mean = sumErr / n }
end

---------------------------------------------------------------------------- report
emit("# Trajectory + Monte Carlo benchmark")
emit("")
emit(string.format("Generated %s. Times are per decision (%d targets).", os.date("%Y-%m-%d %H:%M"), TARGETS_PER_DECISION))
emit("")
emit("## Part 1: trajectory solver (solve only)")
emit("")
emit("Accuracy = re-fly each solution with the reference integrator (RK4, dt 1/4000), worst case over all scenarios.")
emit("")
emit("| Config | Solve (ms) | Flights / solve | Landing err (cm) | Net height err (cm) | Apex err (cm) | Flight time err (ms) | Availability mismatches |")
emit("| --- | --- | --- | --- | --- | --- | --- | --- |")
for _, r in ipairs(trajRows) do
  local a = r.acc
  emit(string.format("| %s | %.2f | %.0f | %.1f | %.1f | %.1f | %.1f | %d |",
    r.name, r.ms, r.flights, a.land * 100, a.net * 100, a.apex * 100, a.time * 1000, a.avail))
end
emit("")
emit("## Part 2: Monte Carlo (solve + probabilities, trajectory config E)")
emit("")
emit("Ground truth = fine integrator (rk2 1/480), 4096 quasi-random samples, every sample flown.")
emit("Error = worst absolute difference in any of success / net / long / wide, in percentage points.")
emit("")
emit("| Method | Decision (ms) | Speedup vs M1 | Flights / target | Max err, skilled (pp) | Max err, rookie (pp) | Mean success err (pp) |")
emit("| --- | --- | --- | --- | --- | --- | --- |")
local base = mcRows[1].ms
for _, r in ipairs(mcRows) do
  emit(string.format("| %s | %.2f | %.1fx | %.0f | %.1f | %.1f | %.2f |",
    r.name, r.ms, base / r.ms, r.flights, pct(r.maxSkilled), pct(r.maxRookie), pct(r.mean)))
end
emit("")
emit("## Shot outputs (ground truth)")
emit("")
emit("| Scenario | Dist (m) | Angle | Speed (m/s) | Flight (s) | Over net (m) | Apex (m) | Descent | Skilled success % | Rookie net / long / wide % | Rookie success % |")
emit("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |")
for i, c in ipairs(CASES) do
  local sk, rk = truth[1][i], truth[2][i]
  if not sk.available then
    emit(string.format("| %s | %.1f | unavailable: %s | | | | | | | | |", c.name, geo[i].dist, sk.reason))
  else
    local s = sk.solution
    emit(string.format("| %s | %.1f | %+.1f deg | %.1f | %.2f | %+.2f | %.2f | %.0f deg | %.1f | %.1f / %.1f / %.1f | %.1f |",
      c.name, geo[i].dist, math.deg(s.angle), s.speed, s.time, (s.netH or 0) - TRUTH_CFG.netHeight, s.apex,
      math.deg(s.descent or 0), pct(sk.success), pct(rk.pNet), pct(rk.pLong), pct(rk.pWide), pct(rk.success)))
  end
end
emit("")
for _, wob in ipairs(WOBBLES) do
  emit(string.format("Wobble %s: angle %.1f deg, direction %.1f deg, speed %.0f%% (1 sigma).",
    wob.name, math.deg(wob.w.angle), math.deg(wob.w.dir), wob.w.speed * 100))
end

function love.load()
  local f = io.open("tools/bench/results.md", "w")
  if f then f:write(table.concat(out, "\n") .. "\n"); f:close() end
  love.event.quit()
end
