-- One rally: serve -> shots back and forth -> point. Pure Lua (no love.*).
--
-- Phases:
--   "pre"    short pause before the serve
--   "decide" frozen at contact; waiting for commit(optionIndex, recoverySpot)
--            (AI hitters commit immediately, so only human hitters stay here)
--   "toss"   serves only: the shuttle is tossed from the chest onto the racket
--            (Shots.tossAt); nobody moves until contact
--   "flight" shuttle in the air along its physics path, athletes moving
--   "point"  shuttle is down (bouncing / skidding along the floor), short pause
--   "done"   rally finished; read rally.result
local V = require("src.core.vec")
local Court = require("src.core.court")
local Shots = require("src.core.shots")
local AI = require("src.core.ai")
local Skid = require("src.core.skid")

local Rally = {}
Rally.__index = Rally

local function other(key) return key == "near" and "far" or "near" end
Rally.other = other

local ONTIME = { state = "ontime", stretch = 0, slack = 0 }

-- o: { players = {near=Athlete, far=Athlete}, server = "near"|"far", serverScore = n,
--      human = {near=true}, rng = function() -> [0,1), events = {} }
function Rally.new(o)
  local self = setmetatable({}, Rally)
  self.players = o.players
  self.server = o.server
  self.human = o.human or {}
  self.rng = o.rng or math.random
  self.events = o.events or {}
  self.aiProfile = o.aiProfile
  self.shotCount = 0
  self.phase = "pre"
  self.timer = o.preDelay or 0.8

  local s, r = self.players[self.server], self.players[other(self.server)]
  local rightX = (s.side == 1) and 0.7 or -0.7          -- each player's own right-hand court
  local sx = (o.serverScore % 2 == 0) and rightX or -rightX
  s:placeAt({ x = sx, y = s.side * 2.3 })
  r:placeAt({ x = -sx, y = r.side * 3.0 })                -- diagonal service court
  s:resetHeart(); r:resetHeart()                          -- partly recovered since last rally
  self.serveX = sx
  self.serveGeo = Shots.serveGeometry(s.pos, s.side)
  local c = self.serveGeo.start          -- held at the chest
  self.shuttle = { pos = { x = c.x, y = c.y }, h = c.h }
  s.pose = { state = "serve", toss = 0 }    -- racket back, ready to toss
  return self
end

function Rally:_emit(ev) self.events[#self.events + 1] = ev end

function Rally:_recoveryPause(hitter, d)
  return hitter:swingPause() + (d.contact.stretch or 0) * hitter:stretchPause()
end

---------------------------------------------------------------------------- options

function Rally:_buildOptions(d)
  local hitter = self.players[d.hitterKey]
  local recv = self.players[other(d.hitterKey)]
  local ctx = { stats = hitter.stats, from = d.from, h0 = d.h0, contact = d.contact,
                incoming = d.incoming, momentum = d.momentum or hitter:momentumSize(),
                maxSpeed = hitter:maxLaunchSpeed(), hr = hitter.hr, hrMul = hitter:hrWobbleMul() }
  -- AI opponents aim a little inside the standard targets (brain.aimMargin m toward the middle)
  local margin = (not self.human[d.hitterKey] and hitter.brain and hitter.brain.aimMargin) or 0
  local mid = Court.basePos(recv.side)
  local function aim(pos)
    if margin <= 0 then return pos end
    local dx, dy = mid.x - pos.x, mid.y - pos.y
    local len = math.sqrt(dx * dx + dy * dy)
    local k = math.min(1, margin / math.max(1e-6, len))
    return { x = pos.x + dx * k, y = pos.y + dy * k }
  end
  d.ctx = ctx
  local pause = self:_recoveryPause(hitter, d)
  local options = {}

  local function add(id, label, pos, shotId, court)
    ctx.court = court
    local ev = Shots.evaluate(ctx, pos, shotId)
    local o = { id = id, label = label, pos = pos, shotId = shotId, eval = ev, court = court,
                recoverPause = pause, recoverTime = ev.flight or 0 }
    if not ev.available then
      o.disabled = ev.reason
    else
      o.receiver = recv:arrival(pos, ev.flight, Shots.data.earlySlack)
    end
    options[#options + 1] = o
  end

  if d.kind == "serve" then
    local rs = recv.side
    local rx = (-self.serveX > 0) and 1 or -1
    local court = rx > 0 and { xMin = 0, xMax = Court.HALF_WIDTH_SINGLES, yMin = Court.SHORT_SERVICE, yMax = Court.LENGTH }
                         or { xMin = -Court.HALF_WIDTH_SINGLES, xMax = 0, yMin = Court.SHORT_SERVICE, yMax = Court.LENGTH }
    add("short_serve", "Short", { x = rx * 1.0, y = rs * 2.5 }, "short_serve", court)
    add("long_serve", "Long", { x = rx * 1.0, y = rs * 6.0 }, "long_serve", court)
  else
    for _, z in ipairs(Court.ZONES) do
      add(z.id, z.label, aim(Court.zonePos(z, recv.side)), Shots.typeFor(d.depth, z.depth), nil)
    end
  end
  return options
end

function Rally:_beginDecision(key, kind, nxt)
  nxt = nxt or {}
  local hitter = self.players[key]
  local d = { hitterKey = key, kind = kind }
  d.contact = nxt.contact or ONTIME
  d.from = nxt.from and V.copy(nxt.from) or V.copy(hitter.pos)
  d.h0 = nxt.h0 or Shots.data.serveHeight
  if kind == "serve" then            -- hit low on the racket head, in front of the server
    local c = self.serveGeo.contact
    d.from, d.h0 = { x = c.x, y = c.y }, c.h
  end
  d.depth = Court.depthOf(d.from)
  d.incoming = nxt.incoming
  d.options = self:_buildOptions(d)
  self.decision = d
  self.phase = "decide"
  if kind == "serve" then
    local c = self.serveGeo.start     -- still held at the chest
    self.shuttle = { pos = { x = c.x, y = c.y }, h = c.h }
  else
    self.shuttle = { pos = V.copy(d.from), h = d.h0 }
  end

  if not self.human[key] then
    local i, spot = AI.choose(self, d, self.rng, hitter.brain or self.aiProfile)
    if not self:commit(i, spot) then
      -- nothing playable: the shuttle drops
      self:_endPoint(other(key), "winner", d.from)
    end
  end
end

function Rally:isHumanDecision()
  return self.phase == "decide" and self.decision and self.human[self.decision.hitterKey] or false
end

-- Clamp a requested recovery spot to what the hitter can reach (direction-dependent) and their half.
function Rally:clampRecovery(option, spot)
  local hitter = self.players[self.decision.hitterKey]
  local c = hitter.pos
  local dx, dy = spot.x - c.x, spot.y - c.y
  local dist = math.sqrt(dx * dx + dy * dy)
  local p = spot
  if dist > 0 then
    local r = hitter:recoveryRadius(dx, dy, option.recoverTime, option.recoverPause)
    if dist > r then p = { x = c.x + dx / dist * r, y = c.y + dy / dist * r } end
  end
  return Court.clampToHalf(p, hitter.side)
end

---------------------------------------------------------------------------- the hit

-- How `recv` gets to a shuttle flying along `path` (points spaced dt) that would land at
-- `landing` after `time` s. Pure: moves nobody (commit applies it; the AI uses it to predict).
-- Returns { outcome = "winner"|"return", a = first arrival, a2, pt, tc, hh, speedMul, momentum }
function Rally.receive(recv, path, dt, landing, time)
  local E = Shots.data.earlySlack
  local a = recv:arrival(landing, time, E)
  if a.state == "winner" then return { outcome = "winner", a = a } end
  -- where (and when) the shuttle is at the receiver's contact height
  local depth = Court.depthOf(landing)
  local pt, tc, hh = Shots.contactOnPath(path, dt, Shots.contactHeight(depth, a, recv.stats))
  local a2 = recv:arrival(pt, tc, E)
  if a2.state == "winner" then
    -- too slow for a high contact: let it drop to the lowest reachable contact
    pt, tc, hh = Shots.contactOnPath(path, dt, Shots.contactHeight(depth, { state = "stretched", stretch = 1 }, recv.stats))
    a2 = recv:arrival(pt, tc, E)
  end
  if a2.state == "winner" then return { outcome = "winner", a = a2 } end
  hh = Shots.contactHeight(Court.depthOf(pt), a2, recv.stats)
  if a2.state ~= "stretched" then
    a2.bodyDest = recv:hittingSpot(pt)       -- stand beside/behind the actual contact
  end
  local bx, by = a2.bodyDest.x - recv.pos.x, a2.bodyDest.y - recv.pos.y
  local bd = math.sqrt(bx * bx + by * by)
  local speedMul = recv:speedMulTo(a2.bodyDest, math.max(0.05, tc - a2.delay))
  -- momentum carried into the shot from this run (applied at contact)
  local mom = recv:momentumFromRun(bx, by, bd, recv:speed() * speedMul, a2.stretch, math.max(0, a2.slack))
  return { outcome = "return", a = a2, a2 = a2, pt = pt, tc = tc, hh = hh, speedMul = speedMul, momentum = mom }
end

function Rally:commit(index, spot)
  local d = self.decision
  local o = d and index and d.options[index]
  if not o or o.disabled then return false end

  local hitter = self.players[d.hitterKey]
  local recvKey = other(d.hitterKey)
  local recv = self.players[recvKey]
  spot = self:clampRecovery(o, spot or Court.basePos(hitter.side))

  local ev = o.eval
  d.ctx.court = o.court
  local res = Shots.execute(d.ctx, ev, self.rng)
  local info = { hitterKey = d.hitterKey, receiverKey = recvKey, shotName = ev.name, shotId = o.shotId,
                 success = ev.success, outcome = res.outcome }
  local endTime = res.time
  local landing = res.landing

  if res.outcome == "net" then
    endTime = (#res.path - 1) * res.dt
  elseif res.outcome ~= "in" then
    local a = recv:arrival(landing, res.time, Shots.data.earlySlack)
    recv:moveTo(a.bodyDest, a.delay)
  else
    local r = Rally.receive(recv, res.path, res.dt, landing, res.time)
    local a2 = r.a
    if r.outcome == "winner" then
      info.outcome = "winner"
      recv:moveTo(a2.bodyDest, a2.delay)
      recv.pose = { state = "stretched" }
    else
      info.outcome = "return"
      endTime = r.tc
      info.next = { contact = a2, from = r.pt, h0 = r.hh, incoming = o.shotId, momentum = r.momentum }
      recv:moveTo(a2.bodyDest, a2.delay, r.speedMul)
      recv.pose = { state = a2.state, x = r.pt.x, y = r.pt.y, h = r.hh, stretch = a2.stretch }
    end
    -- habits: which target this player picks from each depth (anticipation 3 reads them)
    hitter.habits = hitter.habits or {}
    local hk = d.depth
    hitter.habits[hk] = hitter.habits[hk] or {}
    hitter.habits[hk][o.id] = (hitter.habits[hk][o.id] or 0) + 1
  end

  hitter:moveTo(spot, self:_recoveryPause(hitter, d), nil, true)   -- balanced again after the pause

  self.flightInfo = info
  self.path = { points = res.path, dt = res.dt, endTime = math.max(0.05, endTime), t = 0, landing = landing }
  if d.kind == "serve" then
    -- toss first: from the chest onto the racket, then the flight starts
    -- nobody starts moving until the contact: both moves wait out the toss as well
    self.phase = "toss"
    self.tossT = 0
    hitter.pose = { state = "serve", toss = 0 }
    local T = Shots.data.serveToss.time
    for _, p in pairs(self.players) do
      if p.dest then p.delay, p.delayTotal = p.delay + T, (p.delayTotal or 0) + T end
    end
  else
    hitter.pose = nil
    self.phase = "flight"
  end
  self.decision = nil
  self.shotCount = self.shotCount + 1

  self:_emit({ type = "hit", key = d.hitterKey, who = hitter.name, shot = ev.name, success = ev.success })
  return true
end

-- Shuttle state at time t along sampled points { {x,y,h}, ... } spaced dt apart.
local function sampleAt(pts, dt, t)
  local f = t / dt + 1
  local i = math.max(1, math.min(#pts - 1, math.floor(f)))
  local a, b = pts[i], pts[math.min(#pts, i + 1)]
  local u = math.max(0, math.min(1, f - i))
  return { pos = { x = a.x + (b.x - a.x) * u, y = a.y + (b.y - a.y) * u }, h = a.h + (b.h - a.h) * u }
end

function Rally:_endPoint(winner, reason, pos)
  self.result = { winner = winner, reason = reason, pos = V.copy(pos), shots = self.shotCount }
  self.phase = "point"
  self.timer = 1.4
  self:_emit({ type = "point", winner = winner, reason = reason, pos = self.result.pos })
end

function Rally:_resolveFlight()
  local f = self.flightInfo
  if f.outcome == "return" then
    local recv = self.players[f.receiverKey]
    recv.momentum = f.next.momentum or { x = 0, y = 0 }
    recv:lungeHeart(f.next.contact.stretch)               -- a deep lunge costs heart rate
    self:_beginDecision(f.receiverKey, "rally", f.next)
    return
  end
  local winner = (f.outcome == "winner") and f.hitterKey or f.receiverKey
  local pos = f.outcome == "net" and self.shuttle.pos or self.path.landing
  if f.outcome ~= "net" then
    -- it keeps going after it lands: bounce + skid (visual; the point is decided at `pos`)
    local s = Skid.simulate(pos, Skid.landingVelocity(self.path.points, self.path.dt))
    s.t = 0
    self.skid = s
  end
  self:_endPoint(winner, f.outcome, pos)
end

function Rally:update(dt)
  if self.phase == "decide" or self.phase == "done" then return end
  for _, p in pairs(self.players) do p:update(dt) end

  if self.phase == "toss" then
    -- the shuttle arcs from the chest onto the racket (moves are delayed past the contact)
    local T = Shots.data.serveToss.time
    self.tossT = self.tossT + dt
    local u = math.min(1, self.tossT / T)
    local server = self.players[self.server]
    self.shuttle = Shots.tossAt(self.serveGeo, u)
    if u < 1 then
      server.pose.toss = u
      return
    end
    server.pose = nil                  -- contact: the flight starts with the leftover time
    self.phase = "flight"
    local P = self.path
    P.t = self.tossT - T
    self.shuttle = sampleAt(P.points, P.dt, math.min(P.t, P.endTime))
    return
  end

  if self.phase == "pre" then
    self.timer = self.timer - dt
    if self.timer <= 0 then self:_beginDecision(self.server, "serve") end
  elseif self.phase == "flight" then
    local P = self.path
    P.t = P.t + dt
    self.shuttle = sampleAt(P.points, P.dt, math.min(P.t, P.endTime))
    if P.t >= P.endTime then self:_resolveFlight() end
  elseif self.phase == "point" then
    if self.skid then
      self.skid.t = self.skid.t + dt
      self.shuttle = sampleAt(self.skid.points, self.skid.dt, self.skid.t)
    else
      self.shuttle.h = math.max(0, self.shuttle.h - 3 * dt)   -- net errors drop to the floor
    end
    self.timer = self.timer - dt
    if self.timer <= 0 then self.phase = "done" end
  end
end

return Rally
