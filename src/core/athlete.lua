-- An athlete on court: stats, position and the footwork model. Pure Lua (no love.*).
--
-- Getting to a shuttle = reaction delay + straight-line run at Speed - reach
-- (racket + optional lunge). Reaching only by lunging = "stretched": more wobble,
-- longer recovery.
local V = require("src.core.vec")
local Body = require("src.core.body")
local Bal = require("src.data.balance")

local Athlete = {}
Athlete.__index = Athlete

Athlete.REACH = 0.7                                 -- m, racket reach without lunging (timing model)

function Athlete.new(def, side)
  local self = setmetatable({}, Athlete)
  self.name = def.name
  self.title = def.title
  self.stats = def.stats
  self.side = side                 -- +1 near, -1 far
  self.pos = { x = 0, y = side * 3.6 }
  self.dest = nil
  self.delay = 0                   -- seconds before starting to move
  self.speedMul = 1                -- >1 when lunging to make it in time
  self.pose = nil                  -- { state, x, y, h } contact the racket is reaching for (nil = ready)
  self.offBalance = 0              -- 0 = set and balanced, 1 = completely off balance
  return self
end

---------------------------------------------------------------------------- stat -> numbers
function Athlete:baseSpeed() return 2.25 + 0.2 * self.stats.speed end          -- m/s when balanced
function Athlete:speed() return self:baseSpeed() * (1 - Bal.speedLoss * self.offBalance) end
function Athlete:baseReaction() return 0.36 - 0.022 * self.stats.reaction end   -- s when balanced
function Athlete:reaction() return self:baseReaction() + Bal.reactionAdd * self.offBalance end
function Athlete:balanceRecovery() return Bal.recoverBase + Bal.recoverPerLevel * self.stats.balance end -- per s
function Athlete:recoveryPause() return 0.42 - 0.03 * self.stats.balance end    -- s
function Athlete:stretchPause() return 0.55 - 0.035 * self.stats.balance end   -- s extra at full stretch
function Athlete:lungeReach() return 0.25 + 0.05 * self.stats.reach end         -- m extra reach by lunging
function Athlete:maxLaunchSpeed() return 30 + 4 * self.stats.power end          -- m/s

function Athlete:startDelay() return math.max(self.delay, self:reaction()) end

-- Ideal hitting spot for a right-hander (see core/body.lua): slightly to the player's left
-- of the shuttle and a little behind it, so the racket on the right meets it in front.
function Athlete:hittingSpot(p) return Body.hittingSpot(p, self.side) end

-- Can this athlete get a racket on a shuttle at ground point p in `time` seconds?
-- Timing uses the distance to the shuttle minus racket reach (symmetric, so the
-- backhand side is not slower while there is no backhand); the body still moves to the
-- right-hander's hitting spot so it ends up beside/behind the shuttle on screen.
-- Returns { state = "early"|"ontime"|"stretched"|"winner", slack, stretch, bodyDest }
function Athlete:arrival(p, time, earlySlack)
  local spot = self:hittingSpot(p)
  local tx, ty = p.x - self.pos.x, p.y - self.pos.y
  local need = math.max(0, math.sqrt(tx * tx + ty * ty) - Athlete.REACH)
  local v = self:speed()
  local delay = self:startDelay()
  local avail = math.max(0, time - delay)
  local lunge = self:lungeReach()
  local travel = v * avail

  local dx, dy = spot.x - self.pos.x, spot.y - self.pos.y
  local dist = math.sqrt(dx * dx + dy * dy)
  local function partway(frac)           -- body position part of the way to the hitting spot
    if dist < 1e-6 or frac >= 1 then return spot end
    return { x = self.pos.x + dx * frac, y = self.pos.y + dy * frac }
  end

  if travel >= need then
    local slack = avail - need / v
    return { state = slack >= earlySlack and "early" or "ontime", slack = slack, stretch = 0,
             bodyDest = spot }
  end
  local frac = (need > 0) and (travel / (need + Athlete.REACH)) or 1
  if travel >= need - lunge then
    return { state = "stretched", slack = avail - need / v, stretch = (need - travel) / lunge,
             bodyDest = partway(frac) }
  end
  return { state = "winner", slack = avail - need / v, stretch = 1, bodyDest = partway(frac) }
end

-- How far this athlete can recover within `time` after a pause.
function Athlete:recoveryRadius(time, pause)
  return self:speed() * math.max(0, time - pause)
end

---------------------------------------------------------------------------- movement
function Athlete:placeAt(pos)
  self.pos = V.copy(pos)
  self.dest = nil
  self.delay = 0
  self.pose = nil
  self.offBalance = 0
end

-- Push the off-balance meter up (clamped to 1).
function Athlete:unsettle(amount)
  self.offBalance = math.min(1, self.offBalance + amount)
end

-- Is the athlete currently heading away from point p (so a ball there wrong-foots them)?
function Athlete:movingAwayFrom(p)
  if not self.dest or self.delay > 0 then return false end
  local mx, my = self.dest.x - self.pos.x, self.dest.y - self.pos.y
  local ml = math.sqrt(mx * mx + my * my)
  if ml < 0.3 then return false end
  local px, py = p.x - self.pos.x, p.y - self.pos.y
  local pl = math.sqrt(px * px + py * py)
  if pl < 0.3 then return false end
  return (mx * px + my * py) / (ml * pl) < -0.2     -- pointing more than ~100 degrees apart
end

function Athlete:moveTo(dest, delay, speedMul)
  self.dest = V.copy(dest)
  self.delay = delay or 0
  self.speedMul = speedMul or 1
end

function Athlete:isMoving() return self.dest ~= nil and self.delay <= 0 end

function Athlete:update(dt)
  self.offBalance = math.max(0, self.offBalance - self:balanceRecovery() * dt)
  if not self.dest then return end
  if self.delay > 0 then
    local used = math.min(self.delay, dt)
    self.delay = self.delay - used
    dt = dt - used
  end
  if dt > 0 then
    local p, arrived = V.moveToward(self.pos, self.dest, self:speed() * self.speedMul * dt)
    self.pos = p
    if arrived then self.dest = nil end
  end
end

return Athlete
