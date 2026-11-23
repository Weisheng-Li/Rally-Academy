-- Shot evaluation for the game: stats + situation -> physics shot model -> success %,
-- breakdown factors, preview path and landing spread. Also executes the one real hit.
-- Pure Lua (no love.*).
local Data = require("src.data.shots")
local Traj = require("src.core.trajectory")
local SM = require("src.core.shot_model")
local Bal = require("src.data.balance")

local Shots = { data = Data }

local function lerp(a, b, t) return a + (b - a) * t end

function Shots.typeFor(fromDepth, toDepth) return Data.matrix[fromDepth][toDepth] end

-- contact = { state = "early"|"ontime"|"stretched", stretch = 0..1 }
function Shots.contactHeight(depth, contact)
  local t = Data.contactHeight[depth]
  if contact.state == "early" then return t.early end
  if contact.state == "stretched" then return lerp(t.ontime, t.stretched, contact.stretch) end
  return t.ontime
end

function Shots.techniqueMul(level)
  local m = Data.techniqueMul
  return m.step ^ (m.pivot - level)
end

function Shots.timingMul(contact)
  local m = Data.timingMul
  if contact.state == "early" then return m.early end
  if contact.state == "stretched" then return lerp(1, m.stretchedMax, contact.stretch) end
  return m.ontime
end

-- Convert a recorded (s, z) flight to world points {x, y, h} along a ground direction.
function Shots.worldPath(from, dx, dy, pts)
  local out = {}
  for i = 1, #pts, 2 do
    out[#out + 1] = { x = from.x + dx * pts[i], y = from.y + dy * pts[i], h = math.max(0, pts[i + 1]) }
  end
  return out
end

local function isSided(from) return math.abs(from.x) > 0.5 end

-- ctx: { stats, from = ground pos, h0, contact = {state, stretch}, incoming = shotId|nil,
--        offBalance = 0..1, maxSpeed, court = landing area (optional) }
function Shots.evaluate(ctx, target, shotId)
  local def = Data.types[shotId]
  local stats = ctx.stats
  local lvl = stats[def.skill] or 5
  local factors = {}
  local function factor(label, value, effect) factors[#factors + 1] = { label = label, value = value, effect = effect } end

  local tech = Shots.techniqueMul(lvl)
  factor(string.format("%s technique Lv%d", Data.skillNames[def.skill], lvl), string.format("wobble x%.2f", tech),
    tech < 1 and "good" or (tech > 1 and "bad" or nil))
  local tm = Shots.timingMul(ctx.contact)
  if ctx.contact.state == "early" then
    factor("Early contact (high)", string.format("wobble x%.2f", tm), "good")
  elseif ctx.contact.state == "stretched" then
    factor(string.format("Stretched %d%% (lunge)", math.floor(ctx.contact.stretch * 100 + 0.5)),
      string.format("wobble x%.2f", tm), "bad")
  end
  local inc = (ctx.incoming and Data.incomingMul[ctx.incoming]) or 1
  if inc ~= 1 then
    factor("Returning a " .. Data.types[ctx.incoming].name:lower(), string.format("wobble x%.2f", inc), "bad")
  end
  local ob = ctx.offBalance or 0
  local obMul = 1 + Bal.wobbleAdd * ob
  if ob >= 0.05 then
    factor(string.format("Off balance %d%%", math.floor(ob * 100 + 0.5)), string.format("wobble x%.2f", obMul), "bad")
  end

  local from = ctx.from
  local dx, dy = target.x - from.x, target.y - from.y
  local dist = math.sqrt(dx * dx + dy * dy)
  local ux, uy = dx / dist, dy / dist
  local netS = -from.y / uy
  local h0 = ctx.h0

  local name = def.name
  local cross = false
  if not def.serve and isSided(from) then
    cross = (from.x > 0) ~= (target.x > 0)
    name = (cross and "Cross " or "Straight ") .. def.name:lower()
  end

  -- Late (stretched) or badly off balance: only straight and defensive shots are easy.
  local late = not def.serve and (ctx.contact.state == "stretched" or ob >= Bal.restrictAt)
  local lateMul = 1
  local lateReason
  if late and shotId == "smash" then
    lateReason = "Too late / off balance to smash"
  elseif late and cross then
    if lvl < Bal.crossMinTechnique then
      lateReason = string.format("Too late for a cross shot (needs %s Lv%d)", Data.skillNames[def.skill],
        Bal.crossMinTechnique)
    else
      lateMul = Bal.lateCrossWobble
      factor("Late cross shot", string.format("wobble x%.2f", lateMul), "bad")
    end
  end

  local mul = tech * tm * inc * obMul * lateMul
  local bw = Data.baseWobble
  local wobble = { angle = bw.angle * mul, dir = bw.dir * mul, speed = bw.speed * mul }

  local base = { shotId = shotId, def = def, name = name, cross = cross, factors = factors,
                 wobble = wobble, wobbleMul = mul, distance = dist }
  local function unavailable(reason)
    base.available = false
    base.reason = reason
    base.success = 0
    return base
  end

  if lateReason then return unavailable(lateReason) end
  if def.minContact and h0 < def.minContact then
    return unavailable(string.format("Too low to smash (contact %.1f m)", h0))
  end

  local maxV = ctx.maxSpeed
  local sol
  if def.usesPower then
    local v = maxV
    while v >= 25 do
      sol = Traj.solve(h0, dist, netS, { kind = "speed", speed = v })
      if sol and sol.clears then break end
      sol = nil
      v = v - Data.smashSpeedStep
    end
    if not sol then return unavailable("Can't smash over the net from here") end
    factor(string.format("Power Lv%d", stats.power),
      v < maxV and string.format("%d of %d m/s (net)", v, maxV) or string.format("%d m/s", v), nil)
  else
    sol = Traj.solve(h0, dist, netS, def.spec)
    if not sol then return unavailable("No way to play this from here") end
    if not sol.clears then return unavailable("Can't clear the net from here") end
    if sol.speed > maxV + 1e-6 then
      return unavailable(string.format("Needs %.0f m/s, Power Lv%d gives %d", sol.speed, stats.power, maxV))
    end
  end

  local r = SM.evaluate(from, h0, target, def.spec, wobble, nil,
    { solution = sol, court = ctx.court, keepLandings = true })

  local rec = Traj.fly(h0, sol.speed * math.cos(sol.angle), sol.speed * math.sin(sol.angle), netS, { record = true })

  base.available = true
  base.success = r.success
  base.pNet, base.pLong, base.pWide, base.pShort = r.pNet, r.pLong, r.pWide, r.pShort
  base.solution = sol
  base.flight = sol.time
  base.overNet = (sol.netH or 0) - Traj.config.netHeight
  base.speed = sol.speed
  base.landings = r.landings
  base.classify = r.classify
  base.dir = { x = ux, y = uy }
  base.path = Shots.worldPath(from, ux, uy, rec.points)
  return base
end

---------------------------------------------------------------------------- the real hit

local function normal(rng)
  local u1, u2 = math.max(1e-12, rng()), rng()
  return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
end

-- Fly one real shot with a fresh random wobble.
-- Returns { outcome = "in"|"net"|"long"|"wide"|"short", landing, time, path, dt }
function Shots.execute(ctx, ev, rng)
  local sol, w = ev.solution, ev.wobble
  local angle = sol.angle + normal(rng) * w.angle
  local speed = sol.speed * (1 + normal(rng) * w.speed)
  local phi = normal(rng) * w.dir
  local c, s = math.cos(phi), math.sin(phi)
  local wx, wy = ev.dir.x * c - ev.dir.y * s, ev.dir.x * s + ev.dir.y * c
  local from = ctx.from
  local netS = -from.y / wy
  local r = Traj.fly(ctx.h0, speed * math.cos(angle), speed * math.sin(angle), netS,
    { record = true, stopAtNet = true })
  local path = Shots.worldPath(from, wx, wy, r.points)
  local res = { path = path, dt = Traj.config.dt, time = r.time }
  if r.hitNet then
    res.outcome = "net"
    local last = path[#path]
    res.landing = { x = last.x, y = last.y }
    return res
  end
  res.landing = { x = from.x + wx * r.land, y = from.y + wy * r.land }
  res.outcome = ev.classify(res.landing.x, res.landing.y)
  return res
end

-- Point on a recorded path where the falling shuttle comes down to height h.
-- Returns ground point, time, actual height.
function Shots.contactOnPath(path, dt, h)
  local peak = 1
  for i = 2, #path do if path[i].h > path[peak].h then peak = i end end
  for i = math.max(2, peak), #path do
    if path[i].h <= h then
      local a, b = path[i - 1], path[i]
      local f = (a.h - h) / math.max(1e-6, a.h - b.h)
      f = math.max(0, math.min(1, f))
      return { x = a.x + (b.x - a.x) * f, y = a.y + (b.y - a.y) * f }, (i - 2 + f) * dt, h
    end
  end
  local last = path[#path]
  return { x = last.x, y = last.y }, (#path - 1) * dt, last.h
end

return Shots
