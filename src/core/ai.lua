-- Opponent decision policy. Pure Lua (no love.*).
--
-- brain (src/data/athletes.lua): noise, riskAversion, recovery "none" | "center",
-- anticipation 0-3 = how much the AI knows when it picks where to recover after hitting.
-- 1-3 all predict the opponent's contact on the shot just played (where, when) and score
-- recovery spots by where the AI will really be at that moment (still in its post-hit
-- pause, part of the way there, carrying momentum), against the opponent's possible replies:
--   0  no reading: stay where you hit ("none") or go back to the centre
--   1  geometry only: any of the opponent's 6 targets, equally likely
--   2  the opponent's real options from that contact (their stats, how late they'll be,
--      their momentum: "can't go cross when late" or "can't reach the back from that low"
--      fall out), weighted by what would hurt most
--   3  as 2, also weighing the targets this opponent has picked from that depth this match
local Court = require("src.core.court")
local Athlete = require("src.core.athlete")
local Shots = require("src.core.shots")
local Traj = require("src.core.trajectory")

local AI = {}

local function other(key) return key == "near" and "far" or "near" end

-- How much a hitter values putting the receiver in each state.
local function pressure(a)
  if a.state == "winner" then return 1.0 end
  if a.state == "stretched" then return 0.3 + 0.5 * a.stretch end
  if a.state == "ontime" then return 0.2 end
  return 0.0
end
AI.pressure = pressure

AI.SOFTMAX_T = 0.1      -- how sharply anticipation 2+ expects the opponent to pick the best reply
AI.HABIT_WEIGHT = 2     -- anticipation 3: weight x (1 + this x times picked)
AI.CENTER_PULL = 0.002  -- cost per m^2 away from the centre

-- Recovery candidates: a grid around the centre of the half.
AI.GRID_X = { -1.4, -1.0, -0.6, -0.3, 0, 0.3, 0.6, 1.0, 1.4 }
AI.GRID_Y = { -1.2, -0.8, -0.4, 0, 0.4, 0.8 }

-- Where `hitter` really is at time tc after its hit, heading for `spot` after `pause` s.
local function stateAt(hitter, spot, pause, tc)
  local dx, dy = spot.x - hitter.pos.x, spot.y - hitter.pos.y
  local dist = math.sqrt(dx * dx + dy * dy)
  local moved = math.min(dist, hitter:distanceIn(dx, dy, tc - pause, true))
  local pos = dist > 1e-6 and { x = hitter.pos.x + dx / dist * moved, y = hitter.pos.y + dy / dist * moved }
              or { x = hitter.pos.x, y = hitter.pos.y }
  local m = hitter.momentum
  local s = math.sqrt(m.x * m.x + m.y * m.y)
  local k = s > 0 and math.max(0, s - hitter:fadeRate() * tc) / s or 0
  return pos, math.max(0, pause - tc), { x = m.x * k, y = m.y * k }
end

-- Our best reply success from a predicted contact (rr from Rally.receive), memoised per
-- player for the match on a coarse key (depth, timing, height, incoming shot, side, momentum).
function AI.replyQuality(player, rr, incoming)
  local pt, a = rr.pt, rr.a2
  local m = math.sqrt(rr.momentum.x ^ 2 + rr.momentum.y ^ 2)
  local depth = Court.depthOf(pt)
  local side = pt.x > 0.5 and 1 or (pt.x < -0.5 and -1 or 0)
  local key = string.format("%s|%s|%d|%d|%s|%d|%d", depth, a.state, math.floor((a.stretch or 0) * 4 + 0.5),
    math.floor(rr.hh * 10 + 0.5), incoming or "", side, math.floor(math.min(m, 3) / 0.4))
  player._replyCache = player._replyCache or {}
  local c = player._replyCache[key]
  if c then return c end
  local ctx = { stats = player.stats, from = { x = pt.x, y = pt.y }, h0 = rr.hh, contact = a, incoming = incoming,
                momentum = m, maxSpeed = player:maxLaunchSpeed() }
  local best = 0
  for _, z in ipairs(Court.ZONES) do
    local ev = Shots.evaluate(ctx, Court.zonePos(z, -player.side), Shots.typeFor(depth, z.depth))
    if ev.available and ev.success > best then best = ev.success end
  end
  player._replyCache[key] = best
  return best
end

-- Best recovery spot for anticipation 1-3, or nil if the opponent can't return the shot.
function AI.readSpot(rally, d, o, brain)
  local ant = brain.anticipation or 0
  local hitter = rally.players[d.hitterKey]
  local oppKey = other(d.hitterKey)
  local opp = rally.players[oppKey]
  local ev = o.eval
  if not (ev and ev.path and #ev.path > 2) then return nil end

  -- the opponent's contact on the intended path (no wobble), from where they are now
  local landing = ev.path[#ev.path]
  local r = rally.receive(opp, ev.path, Traj.config.dt, landing, ev.flight)
  if r.outcome ~= "return" then return nil end

  -- their options from there (their stats, their late/cross limits, their momentum)
  local nd = { hitterKey = oppKey, kind = "rally", contact = r.a2, from = r.pt, h0 = r.hh,
               incoming = o.shotId, momentum = math.sqrt(r.momentum.x ^ 2 + r.momentum.y ^ 2) }
  nd.depth = Court.depthOf(nd.from)
  local opts = rally:_buildOptions(nd)
  local oppBrain = (not rally.human[oppKey] and opp.brain) or {}
  local oppRisk = oppBrain.riskAversion or 0.9
  local habit = ant >= 3 and opp.habits and opp.habits[nd.depth] or nil

  local probe = Athlete.new({ stats = hitter.stats }, hitter.side)
  probe.hr, probe.hrFloor = hitter.hr, hitter.hrFloor      -- as tired as we are now
  local E = Shots.data.earlySlack
  local base = Court.basePos(hitter.side)
  local pause = o.recoverPause
  local best, bestCost
  for _, gx in ipairs(AI.GRID_X) do
    for _, gy in ipairs(AI.GRID_Y) do
      local spot = Court.clampToHalf({ x = base.x + gx, y = base.y + gy }, hitter.side)
      probe.pos, probe.delay, probe.momentum = stateAt(hitter, spot, pause, r.tc)
      local ws, dmg, total, cost = {}, {}, 0, 0
      for i, op in ipairs(opts) do
        -- level 1 knows only the court geometry: every target, equally likely, all good shots
        local usable = ant <= 1 or not op.disabled
        local path = op.eval.path
        if usable and path and #path > 2 then
          local flight = op.eval.flight
          -- how we'd really meet it: at our contact height on its path (a clear is hit ~2 m up,
          -- well before it lands), and how good our best reply is from there
          local rr = rally.receive(probe, path, Traj.config.dt, path[#path], flight)
          dmg[i] = rr.outcome == "winner" and 1 or (1 - AI.replyQuality(hitter, rr, op.shotId))
          local w = 1
          if ant >= 2 then
            -- their choice, the way they judge it (AI.choose: pressure where we'd land)
            local p = op.eval.success
            local naive = probe:arrival(op.pos, flight, E)
            w = math.exp((p * pressure(naive) - (1 - p) * oppRisk) / AI.SOFTMAX_T)
            if habit then w = w * (1 + AI.HABIT_WEIGHT * (habit[op.id] or 0)) end
          end
          ws[i] = w
          total = total + w
        end
      end
      if total > 0 then
        for i, w in pairs(ws) do
          local p = ant >= 2 and opts[i].eval.success or 1
          cost = cost + w / total * p * dmg[i]    -- they land it and we lose the exchange
        end
        cost = cost + AI.CENTER_PULL * (gx * gx + gy * gy)   -- prefer the centre unless the read is clear
        if not bestCost or cost < bestCost then best, bestCost = spot, cost end
      end
    end
  end
  return best
end

-- Where to recover after playing option o.
function AI.recoverySpot(rally, d, o, brain)
  local hitter = rally.players[d.hitterKey]
  if (brain.anticipation or 0) >= 1 then
    local s = AI.readSpot(rally, d, o, brain)
    if s then return s end
  elseif brain.recovery == "none" then
    return { x = hitter.pos.x, y = hitter.pos.y }
  end
  return Court.basePos(hitter.side)
end

-- Returns option index (or nil if nothing is playable) and recovery spot.
function AI.choose(rally, decision, rng, brain)
  brain = brain or {}
  local riskAversion = brain.riskAversion or 0.9
  local noise = brain.noise or 0.25

  local bestIndex, bestScore
  for i, o in ipairs(decision.options) do
    if not o.disabled then
      local p = o.eval.success
      local score
      if decision.kind == "serve" then
        score = p + rng() * 0.1
      else
        score = p * pressure(o.receiver) - (1 - p) * riskAversion + rng() * noise
      end
      if not bestScore or score > bestScore then bestIndex, bestScore = i, score end
    end
  end
  if not bestIndex then return nil, Court.basePos(rally.players[decision.hitterKey].side) end
  return bestIndex, AI.recoverySpot(rally, decision, decision.options[bestIndex], brain)
end

return AI
