-- An athlete on court: stats, position and a simple "walk to a point" movement model.
-- Pure Lua (no love.*).
local V = require("src.core.vec")

local Athlete = {}
Athlete.__index = Athlete

function Athlete.new(def, side)
  local self = setmetatable({}, Athlete)
  self.name = def.name
  self.title = def.title
  self.stats = def.stats
  self.side = side                 -- +1 near, -1 far
  self.pos = { x = 0, y = side * 3.6 }
  self.dest = nil
  self.delay = 0                   -- seconds before starting to move (reaction / recovery pause)
  self.moveSpeed = self:speed()
  return self
end

-- Derived physical values (stat levels 1-10 -> real units).
function Athlete:speed() return 2.2 + 0.24 * self.stats.speed end            -- m/s
function Athlete:reaction() return 0.36 - 0.022 * self.stats.reaction end     -- s
function Athlete:recoveryPause() return 0.45 - 0.035 * self.stats.recovery end -- s

function Athlete:placeAt(pos)
  self.pos = V.copy(pos)
  self.dest = nil
  self.delay = 0
end

function Athlete:moveTo(dest, delay, speed)
  self.dest = V.copy(dest)
  self.delay = delay or 0
  self.moveSpeed = speed or self:speed()
end

-- How long before they could start running if asked right now.
function Athlete:startDelay()
  return math.max(self.delay, self:reaction())
end

function Athlete:timeToReach(point)
  return self:startDelay() + V.dist(self.pos, point) / self:speed()
end

function Athlete:isMoving()
  return self.dest ~= nil and self.delay <= 0
end

function Athlete:update(dt)
  if not self.dest then return end
  if self.delay > 0 then
    local used = math.min(self.delay, dt)
    self.delay = self.delay - used
    dt = dt - used
  end
  if dt > 0 then
    local p, arrived = V.moveToward(self.pos, self.dest, self.moveSpeed * dt)
    self.pos = p
    if arrived then self.dest = nil end
  end
end

return Athlete
