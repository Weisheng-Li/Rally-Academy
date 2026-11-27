-- An athlete on court: stats, position, movement and momentum. Pure Lua (no love.*).
--
-- Movement = run + reach. A move starts with the current momentum projected onto the move
-- direction (negative = carried the other way: decelerate through zero first), then
-- accelerates at a fixed rate up to top speed. Reach: racket 0.7 m, plus a lunge.
-- Momentum (a floor vector, m/s) is built by the run into each shot (Legs keep less of it)
-- and fades while the player regains balance (faster with Legs). See data/momentum.lua.
local V = require("src.core.vec")
local Body = require("src.core.body")
local M = require("src.data.momentum")
local S = require("src.data.stats")
local H = require("src.data.heart")
local Curve = require("src.core.curve")

local Athlete = {}
Athlete.__index = Athlete

Athlete.REACH = 0.7                                 -- m, racket reach without lunging (timing model)

function Athlete.new(def, side)
  local self = setmetatable({}, Athlete)
  self.name = def.name
  self.title = def.title
  self.stats = def.stats
  self.brain = def.brain           -- opponent AI only (data/athletes.lua)
  self.level = def.level           -- 1-6 when made from a level preset
  self.side = side                 -- +1 near, -1 far
  self.pos = { x = 0, y = side * 3.6 }
  self.dest = nil
  self.delay = 0                   -- seconds before starting to move (swing pause)
  self.speedMul = 1                -- scales top speed so the sprite arrives on time
  self.pose = nil                  -- { state, x, y, h } contact the racket is reaching for (nil = ready)
  self.momentum = { x = 0, y = 0 } -- m/s carried on the floor
  self.hr, self.hrFloor = H.start, H.start   -- heart rate (bpm) and its floor this rally
  self.hrStart, self.hrLoad, self.hrCarry = H.start, 0, 0   -- rally start, exertion, carried over
  return self
end

---------------------------------------------------------------------------- stat -> numbers
-- Curves in data/stats.lua (levels 1-10, linear in between). Missing stats count as Lv5.
local function lv(self, k) return self.stats[k] or 5 end
local function legs(self) return lv(self, "legs") end
function Athlete:baseSpeed() return Curve.at(S.speed, lv(self, "speed")) end          -- m/s top speed, fresh
-- tired legs (heart rate): slower top speed and push-off, so you arrive later and lunge more
function Athlete:speed() return self:baseSpeed() * self:legsFatigueMul() end           -- m/s top speed now
function Athlete:firstStep() return Curve.at(S.firstStep, lv(self, "speed")) * self:legsFatigueMul() end -- m/s push-off
function Athlete:lungeReach() return Curve.at(S.reach, lv(self, "reach")) end         -- m extra reach by lunging
function Athlete:maxLaunchSpeed() return Curve.at(S.power, lv(self, "power")) end     -- m/s
function Athlete:reaction() return Curve.at(S.reaction, lv(self, "reaction")) end     -- s before moving
function Athlete:momentumRetain() return M.retainBase - M.retainPerLegs * legs(self) end
function Athlete:fadeRate() return M.fadeBase + M.fadePerLegs * legs(self) end    -- m/s per s
function Athlete:swingPause() return Curve.at(S.swingPause, lv(self, "recovery")) end
function Athlete:stretchPause() return Curve.at(S.stretchPause, lv(self, "recovery")) end   -- extra s at full stretch

---------------------------------------------------------------------------- heart rate
-- See data/heart.lua. 0 below the onset, 1 at max heart rate.
function Athlete:fatigue()
  return math.max(0, math.min(1, ((self.hr or H.start) - H.onset) / (H.max - H.onset)))
end
function Athlete:legsFatigueMul() return 1 - H.slowAtMax * self:fatigue() end
function Athlete:hrWobbleMul() return 1 + H.wobbleAtMax * self:fatigue() ^ 1.5 end
local function staminaCost(self) return Curve.at(H.staminaCost, lv(self, "stamina")) end
local function staminaRecover(self) return Curve.at(H.staminaRecover, lv(self, "stamina")) end

-- New rally: you only partly recover. A hard last rally (lots of load) starts this one
-- higher; that extra fades over a few quieter points.
function Athlete:resetHeart()
  self.hrCarry = math.min(H.carryMax, (self.hrCarry or 0) * H.carryDecay + H.carryPerLoad * (self.hrLoad or 0))
  self.hrStart = math.min(H.max, H.start + self.hrCarry)
  self.hr, self.hrFloor, self.hrLoad = self.hrStart, self.hrStart, 0
end


-- A lunge at contact: stretch 0..1.
function Athlete:lungeHeart(stretch)
  self.hr = math.min(H.max, self.hr + H.lunge * (stretch or 0) * staminaCost(self))
end

-- One frame at `speed` m/s: sprinting raises it fast, jogging a little, standing lowers it.
function Athlete:heartStep(dt, speed)
  local u = math.min(1, speed / self:baseSpeed())
  local d = H.gain * u * u * staminaCost(self) - H.recover * (1 - u) * staminaRecover(self)
  self.hr = math.max(self.hrFloor, math.min(H.max, self.hr + d * dt))
  -- exertion: time spent above this rally's start raises your own floor
  local start = self.hrStart or H.start
  self.hrLoad = (self.hrLoad or 0) + math.max(0, self.hr - start) * dt
  self.hrFloor = math.min(H.max, start + H.loadFloor * self.hrLoad)
  self.hr = math.max(self.hr, self.hrFloor)
end

---------------------------------------------------------------------------- kinematics
-- Distance covered from rest-or-moving speed v (>= 0) in time t, accelerating to vmax.
local function distFrom(v, t, a, vmax)
  if t <= 0 then return 0 end
  local tAcc = (vmax - v) / a
  if t <= tAcc then return v * t + 0.5 * a * t * t end
  return v * tAcc + 0.5 * a * tAcc * tAcc + vmax * (t - tAcc)
end

-- Time to cover distance d starting at speed v (>= 0).
local function timeFrom(v, d, a, vmax)
  if d <= 0 then return 0 end
  local sAcc = (vmax * vmax - v * v) / (2 * a)
  if d <= sAcc then return (-v + math.sqrt(v * v + 2 * a * d)) / a end
  return (vmax - v) / a + (d - sAcc) / vmax
end

-- Starting velocity along unit direction (ux, uy): the current momentum projected on it,
-- plus the split-step push-off (Speed; zero for beginners). balanced = the move starts after
-- the recovery pause, centre of gravity back over the feet: no momentum, any direction alike.
function Athlete:startVelocity(ux, uy, balanced)
  local carried = balanced and 0 or (self.momentum.x * ux + self.momentum.y * uy)
  return math.min(self:speed(), carried + self:firstStep())
end

-- How far the athlete gets in direction (dx, dy) within time t (never negative).
function Athlete:distanceIn(dx, dy, t, balanced)
  local l = math.sqrt(dx * dx + dy * dy)
  if t <= 0 then return 0 end
  local v0 = (l > 1e-9) and self:startVelocity(dx / l, dy / l, balanced) or 0
  local a, vmax = M.accel, self:speed()
  if v0 >= 0 then return distFrom(v0, t, a, vmax) end
  -- carried the wrong way: decelerate to zero (losing ground), then run
  local tStop = -v0 / a
  if t <= tStop then return 0 end
  return math.max(0, distFrom(0, t - tStop, a, vmax) - v0 * v0 / (2 * a))
end

-- Time to cover distance d in direction (dx, dy).
function Athlete:timeToCover(dx, dy, d, mul)
  local l = math.sqrt(dx * dx + dy * dy)
  local v0 = (l > 1e-9) and self:startVelocity(dx / l, dy / l) or 0
  local a, vmax = M.accel * (mul or 1), self:speed() * (mul or 1)
  if v0 >= 0 then return timeFrom(v0, d, a, vmax) end
  local tStop = -v0 / a
  return tStop + timeFrom(0, d + v0 * v0 / (2 * a), a, vmax)
end

---------------------------------------------------------------------------- momentum
function Athlete:momentumSize()
  local m = self.momentum
  return math.sqrt(m.x * m.x + m.y * m.y)
end

-- "low" | "yellow" | "red"
function Athlete:momentumLevel()
  local s = self:momentumSize()
  if s >= M.red then return "red" end
  if s >= M.yellow then return "yellow" end
  return "low"
end

-- Momentum after running `runDist` m toward (dx, dy) at `runSpeed`, arriving with `stretch`
-- (0..1 lunge) and `slack` seconds to spare (it fades while waiting).
function Athlete:momentumFromRun(dx, dy, runDist, runSpeed, stretch, slack)
  local l = math.sqrt(dx * dx + dy * dy)
  if l < 1e-6 then return { x = 0, y = 0 } end
  local size = runSpeed * math.min(1, runDist / M.fullRunDistance) * self:momentumRetain()
  size = size * (1 + M.lungeBoost * (stretch or 0))
  size = math.max(0, size - self:fadeRate() * math.max(0, slack or 0))
  return { x = dx / l * size, y = dy / l * size }
end

-- Ideal hitting spot for a right-hander (see core/body.lua): slightly to the player's left
-- of the shuttle and a little behind it, so the racket on the right meets it in front.
function Athlete:hittingSpot(p) return Body.hittingSpot(p, self.side) end

-- Can this athlete get a racket on a shuttle at ground point p in `time` seconds?
-- Timing uses the distance to the shuttle minus racket reach (symmetric, so the
-- backhand side is not slower while there is no backhand); the body still moves to the
-- right-hander's hitting spot so it ends up beside/behind the shuttle on screen.
-- Returns { state = "early"|"ontime"|"stretched"|"winner", slack, stretch, bodyDest, delay }
function Athlete:arrival(p, time, earlySlack)
  local spot = self:hittingSpot(p)
  local tx, ty = p.x - self.pos.x, p.y - self.pos.y
  local need = math.max(0, math.sqrt(tx * tx + ty * ty) - Athlete.REACH)
  -- the opponent just hit: wait out what is left of the swing pause, and at least the reaction
  local delay = math.max(self.delay, self:reaction())
  local avail = math.max(0, time - delay)
  local lunge = self:lungeReach()
  local travel = self:distanceIn(tx, ty, avail)

  local dx, dy = spot.x - self.pos.x, spot.y - self.pos.y
  local dist = math.sqrt(dx * dx + dy * dy)
  local function partway(frac)           -- body position part of the way to the hitting spot
    if dist < 1e-6 or frac >= 1 then return spot end
    return { x = self.pos.x + dx * frac, y = self.pos.y + dy * frac }
  end

  if travel >= need then
    local slack = avail - self:timeToCover(tx, ty, need)
    return { state = slack >= earlySlack and "early" or "ontime", slack = slack, stretch = 0,
             bodyDest = spot, delay = delay }
  end
  local slack = avail - self:timeToCover(tx, ty, need)
  local frac = (need > 0) and (travel / (need + Athlete.REACH)) or 1
  if travel >= need - lunge then
    return { state = "stretched", slack = slack, stretch = (need - travel) / lunge,
             bodyDest = partway(frac), delay = delay }
  end
  return { state = "winner", slack = slack, stretch = 1, bodyDest = partway(frac), delay = delay }
end

-- How far this athlete can recover in direction (dx, dy) within `time` after the recovery
-- pause. The pause is where you regain balance after the hit (longer after a deep lunge), so
-- the move after it is the same in every direction: a circle.
function Athlete:recoveryRadius(dx, dy, time, pause)
  return self:distanceIn(dx, dy, time - pause, true)
end

---------------------------------------------------------------------------- movement
function Athlete:placeAt(pos)
  self.pos = V.copy(pos)
  self.dest = nil
  self.delay = 0
  self.pose = nil
  self.momentum = { x = 0, y = 0 }
end

-- Move to dest after `delay`, animated with the same kinematics as the timing model: start
-- with the momentum projected on the move direction, accelerate to top speed.
-- speedMul (>= 1) scales acceleration and top speed together; used only when a lunge must
-- carry the sprite to its hitting spot in time.
-- balanced: start without momentum (a recovery move after the pause, see recoveryRadius).
function Athlete:moveTo(dest, delay, speedMul, balanced)
  self.dest = V.copy(dest)
  self.balanced = balanced or false
  self.delay = delay or 0
  self.delayTotal = self.delay     -- for animation: how long this pause is in total
  self.speedMul = speedMul or 1
  self.vel = nil                   -- set from momentum when the move actually starts
end

-- Smallest speedMul so the sprite reaches `dest` within `avail` seconds of movement.
function Athlete:speedMulTo(dest, avail)
  local dx, dy = dest.x - self.pos.x, dest.y - self.pos.y
  local d = math.sqrt(dx * dx + dy * dy)
  if d < 1e-6 or self:timeToCover(dx, dy, d) <= avail then return 1 end
  local lo, hi = 1, 4
  for _ = 1, 20 do
    local mid = (lo + hi) / 2
    local t = self:timeToCover(dx, dy, d, mid)
    if t <= avail then hi = mid else lo = mid end
  end
  return hi
end

function Athlete:isMoving() return self.dest ~= nil and self.delay <= 0 end

function Athlete:update(dt)
  local x, y = self.pos.x, self.pos.y
  self:_move(dt)
  if dt > 0 then
    local moved = math.sqrt((self.pos.x - x) ^ 2 + (self.pos.y - y) ^ 2)
    self:heartStep(dt, moved / dt)
  end
end

function Athlete:_move(dt)
  -- regaining balance: momentum fades at the Legs rate
  local s = self:momentumSize()
  if s > 0 then
    local k = math.max(0, s - self:fadeRate() * dt) / s
    self.momentum.x, self.momentum.y = self.momentum.x * k, self.momentum.y * k
  end
  if not self.dest then return end
  if self.delay > 0 then
    local used = math.min(self.delay, dt)
    self.delay = self.delay - used
    dt = dt - used
  end
  if dt <= 0 then return end

  local dx, dy = self.dest.x - self.pos.x, self.dest.y - self.pos.y
  local d = math.sqrt(dx * dx + dy * dy)
  if d < 1e-6 then self.dest = nil; return end
  local ux, uy = dx / d, dy / d
  local mul = self.speedMul or 1
  if not self.vel then self.vel = self:startVelocity(ux, uy, self.balanced) end
  local vmax, a = self:speed() * mul, M.accel * mul
  -- integrate along the line (velocity may start negative: carried the wrong way)
  local v0 = self.vel
  local v1 = math.min(vmax, v0 + a * dt)
  local step = (v0 + v1) / 2 * dt
  self.vel = v1
  if step >= d then
    self.pos = V.copy(self.dest)
    self.dest = nil
  else
    self.pos = { x = self.pos.x + ux * step, y = self.pos.y + uy * step }
  end
end

return Athlete
