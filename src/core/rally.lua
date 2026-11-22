-- One rally: serve -> shots back and forth -> point. Pure Lua (no love.*).
--
-- Phases:
--   "pre"    short pause before the serve
--   "decide" frozen at contact; waiting for commit(optionIndex, recoverySpot)
--            (AI hitters commit immediately, so only human hitters stay here)
--   "flight" shuttle in the air, athletes moving
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
  self.shuttle = { pos = V.copy(s.pos), h = 1.0 }
  return self
end

function Rally:_emit(ev) self.events[#self.events + 1] = ev end

function Rally:_recoveryPause(hitter, decision)
  return hitter:recoveryPause() + (decision.timing == "late" and Shots.data.latePause or 0)
end

function Rally:_buildOptions(d)
  local hitter = self.players[d.hitterKey]
  local recv = self.players[other(d.hitterKey)]
  local options = {}

  local function add(id, label, pos, shotId)
    local ev = Shots.evaluate(hitter.stats, d.from, pos, shotId, d.timing, d.kind == "serve")
    local o = { id = id, label = label, pos = pos, shotId = shotId, eval = ev }
    if d.timing == "late" and ev.def.attacking then
      o.disabled = "Too late for a " .. ev.def.name:lower()
    end
    o.receiverSlack = ev.flight - recv:timeToReach(pos)
    o.receiverState = Shots.reachState(o.receiverSlack)
    o.recoveryRadius = hitter:speed() * math.max(0, ev.flight - self:_recoveryPause(hitter, d))
    options[#options + 1] = o
  end

  if d.kind == "serve" then
    local rs = recv.side
    local rx = (-self.serveX > 0) and 1 or -1
    add("short_serve", "Short", { x = rx * 1.0, y = rs * 2.3 }, "short_serve")
    add("long_serve", "Long", { x = rx * 1.0, y = rs * 6.1 }, "long_serve")
  else
    for _, z in ipairs(Court.ZONES) do
      add(z.id, z.label, Court.zonePos(z, recv.side), Shots.typeFor(d.depth, z.depth))
    end
  end
  return options
end

function Rally:_beginDecision(key, kind, timing, slack)
  local hitter = self.players[key]
  local d = { hitterKey = key, kind = kind, timing = timing or "ontime", slack = slack }
  d.from = V.copy(hitter.pos)
  d.depth = Court.depthOf(d.from)
  d.contactH = (kind == "serve") and 1.0 or Shots.contactHeight(d.depth, d.timing)
  d.options = self:_buildOptions(d)
  self.decision = d
  self.phase = "decide"
  self.shuttle = { pos = V.copy(d.from), h = d.contactH }

  if not self.human[key] then
    local i, spot = AI.choose(self, d, self.rng, self.aiProfile)
    self:commit(i, spot)
  end
end

function Rally:isHumanDecision()
  return self.phase == "decide" and self.decision and self.human[self.decision.hitterKey] or false
end

-- Clamp a requested recovery spot to the reachable circle and the hitter's half.
function Rally:clampRecovery(option, spot)
  local d = self.decision
  local hitter = self.players[d.hitterKey]
  local c = d.from
  local dist = V.dist(c, spot)
  local p = spot
  if dist > option.recoveryRadius and dist > 0 then
    p = V.lerp(c, spot, option.recoveryRadius / dist)
  end
  return Court.clampToHalf(p, hitter.side)
end

function Rally:commit(index, spot)
  local d = self.decision
  local o = d and d.options[index]
  if not o or o.disabled then return false end

  local hitter = self.players[d.hitterKey]
  local recvKey = other(d.hitterKey)
  local recv = self.players[recvKey]
  spot = self:clampRecovery(o, spot or Court.basePos(hitter.side))

  local ev = o.eval
  local jitter = (d.kind == "serve") and 0 or 0.15
  local land = { x = o.pos.x + (self.rng() * 2 - 1) * jitter, y = o.pos.y + (self.rng() * 2 - 1) * jitter }
  local flight = ev.flight
  local startDelay = recv:startDelay()
  local slack = flight - recv:timeToReach(land)

  local info = { hitterKey = d.hitterKey, receiverKey = recvKey, shotName = ev.name, success = ev.success }
  local endPos, endH, dur, apex = land, 0, flight, ev.def.apex

  if self.rng() > ev.success then
    info.outcome = "error"
    local depth = Court.depthOf(land)
    if depth == "front" or o.shotId == "smash" then
      info.errorKind = "net"
      local f = math.abs(d.from.y) / (math.abs(d.from.y) + math.abs(land.y))
      endPos = { x = d.from.x + (land.x - d.from.x) * f, y = hitter.side * 0.08 }
      endH, dur, apex = 1.0, flight * f, apex * 0.3
    else
      info.errorKind = "out"
      endPos = V.copy(land)
      if depth == "back" then
        endPos.y = recv.side * (Court.LENGTH + 0.6)
      else
        endPos.x = (land.x >= 0 and 1 or -1) * (Court.HALF_WIDTH_SINGLES + 0.5)
      end
    end
    recv:moveTo(land, startDelay)
  elseif slack < Shots.data.slackReach then
    info.outcome = "winner"
    recv:moveTo(land, startDelay)
  else
    info.outcome = "return"
    info.timing = Shots.timingFromSlack(slack)
    info.slack = slack
    endH = Shots.contactHeight(Court.depthOf(land), info.timing)
    -- Late-but-reachable: lunge (faster than normal) so they arrive exactly on time.
    local avail = math.max(0.05, flight - startDelay)
    recv:moveTo(land, startDelay, math.max(recv:speed(), V.dist(recv.pos, land) / avail))
  end

  hitter:moveTo(spot, self:_recoveryPause(hitter, d))

  self.flightInfo = info
  self.path = { from = V.copy(d.from), h0 = d.contactH, to = endPos, h1 = endH, apex = apex, dur = dur, t = 0 }
  self.phase = "flight"
  self.decision = nil
  self.shotCount = self.shotCount + 1
  self:_emit({ type = "hit", key = d.hitterKey, who = hitter.name, shot = ev.name, success = ev.success })
  return true
end

function Rally:pathPoint(path, t)
  local p = V.lerp(path.from, path.to, t)
  return { pos = p, h = path.h0 + (path.h1 - path.h0) * t + path.apex * 4 * t * (1 - t) }
end

function Rally:_resolveFlight()
  local f = self.flightInfo
  if f.outcome == "return" then
    self:_beginDecision(f.receiverKey, "rally", f.timing, f.slack)
    return
  end
  local winner = (f.outcome == "winner") and f.hitterKey or f.receiverKey
  local reason = (f.outcome == "winner") and "winner" or f.errorKind
  self.result = { winner = winner, reason = reason, pos = V.copy(self.path.to), shots = self.shotCount }
  self.phase = "point"
  self.timer = 1.4
  self:_emit({ type = "point", winner = winner, reason = reason, pos = self.result.pos })
end

function Rally:update(dt)
  if self.phase == "decide" or self.phase == "done" then return end
  for _, p in pairs(self.players) do p:update(dt) end

  if self.phase == "pre" then
    self.timer = self.timer - dt
    if self.timer <= 0 then self:_beginDecision(self.server, "serve") end
  elseif self.phase == "flight" then
    local path = self.path
    path.t = path.t + dt
    self.shuttle = self:pathPoint(path, math.min(1, path.t / path.dur))
    if path.t >= path.dur then self:_resolveFlight() end
  elseif self.phase == "point" then
    self.shuttle.h = math.max(0, self.shuttle.h - 3 * dt)   -- net errors drop to the floor
    self.timer = self.timer - dt
    if self.timer <= 0 then self.phase = "done" end
  end
end

return Rally
