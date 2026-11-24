-- One rally: serve -> shots back and forth -> point. Pure Lua (no love.*).
--
-- Phases:
--   "pre"    short pause before the serve
--   "decide" frozen at contact; waiting for commit(optionIndex, recoverySpot)
--            (AI hitters commit immediately, so only human hitters stay here)
--   "flight" shuttle in the air along its physics path, athletes moving
--   "point"  shuttle is down, short pause
--   "done"   rally finished; read rally.result
local V = require("src.core.vec")
local Court = require("src.core.court")
local Shots = require("src.core.shots")
local AI = require("src.core.ai")

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
  self.serveX = sx
  self.shuttle = { pos = V.copy(s.pos), h = Shots.data.serveHeight }
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
                incoming = d.incoming, momentum = hitter:momentumSize(), maxSpeed = hitter:maxLaunchSpeed() }
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
      add(z.id, z.label, Court.zonePos(z, recv.side), Shots.typeFor(d.depth, z.depth), nil)
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
  d.depth = Court.depthOf(d.from)
  d.incoming = nxt.incoming
  d.options = self:_buildOptions(d)
  self.decision = d
  self.phase = "decide"
  self.shuttle = { pos = V.copy(d.from), h = d.h0 }

  if not self.human[key] then
    local i, spot = AI.choose(self, d, self.rng, self.aiProfile)
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
    local a = recv:arrival(landing, res.time, Shots.data.earlySlack)
    if a.state == "winner" then
      info.outcome = "winner"
      recv:moveTo(a.bodyDest, a.delay)
      recv.pose = { state = "stretched" }
    else
      -- where (and when) the shuttle is at the receiver's contact height
      local depth = Court.depthOf(landing)
      local pt, tc, hh = Shots.contactOnPath(res.path, res.dt, Shots.contactHeight(depth, a))
      local a2 = recv:arrival(pt, tc, Shots.data.earlySlack)
      if a2.state == "winner" then
        -- too slow for a high contact: let it drop to the lowest reachable contact
        pt, tc, hh = Shots.contactOnPath(res.path, res.dt, Shots.contactHeight(depth, { state = "stretched", stretch = 1 }))
        a2 = recv:arrival(pt, tc, Shots.data.earlySlack)
      end
      if a2.state == "winner" then
        info.outcome = "winner"
        recv:moveTo(a2.bodyDest, a2.delay)
        recv.pose = { state = "stretched" }
      else
        info.outcome = "return"
        hh = Shots.contactHeight(Court.depthOf(pt), a2)
        if a2.state ~= "stretched" then
          a2.bodyDest = recv:hittingSpot(pt)       -- stand beside/behind the actual contact
        end
        endTime = tc
        local delay = a2.delay
        local bx, by = a2.bodyDest.x - recv.pos.x, a2.bodyDest.y - recv.pos.y
        local bd = math.sqrt(bx * bx + by * by)
        local speedMul = recv:speedMulTo(a2.bodyDest, math.max(0.05, tc - delay))
        -- momentum carried into the shot from this run (applied at contact)
        local mom = recv:momentumFromRun(bx, by, bd, recv:speed() * speedMul, a2.stretch, math.max(0, a2.slack))
        info.next = { contact = a2, from = pt, h0 = hh, incoming = o.shotId, momentum = mom }
        recv:moveTo(a2.bodyDest, delay, speedMul)
        recv.pose = { state = a2.state, x = pt.x, y = pt.y, h = hh }
      end
    end
  end

  hitter.pose = nil
  hitter:moveTo(spot, self:_recoveryPause(hitter, d))

  self.flightInfo = info
  self.path = { points = res.path, dt = res.dt, endTime = math.max(0.05, endTime), t = 0, landing = landing }
  self.phase = "flight"
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
    self:_beginDecision(f.receiverKey, "rally", f.next)
    return
  end
  local winner = (f.outcome == "winner") and f.hitterKey or f.receiverKey
  local pos = f.outcome == "net" and self.shuttle.pos or self.path.landing
  self:_endPoint(winner, f.outcome, pos)
end

function Rally:update(dt)
  if self.phase == "decide" or self.phase == "done" then return end
  for _, p in pairs(self.players) do p:update(dt) end

  if self.phase == "pre" then
    self.timer = self.timer - dt
    if self.timer <= 0 then self:_beginDecision(self.server, "serve") end
  elseif self.phase == "flight" then
    local P = self.path
    P.t = P.t + dt
    self.shuttle = sampleAt(P.points, P.dt, math.min(P.t, P.endTime))
    if P.t >= P.endTime then self:_resolveFlight() end
  elseif self.phase == "point" then
    self.shuttle.h = math.max(0, self.shuttle.h - 3 * dt)   -- net errors drop to the floor
    self.timer = self.timer - dt
    if self.timer <= 0 then self.phase = "done" end
  end
end

return Rally
