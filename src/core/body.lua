-- Body + racket numbers shared by the rules and the sprites. Pure Lua (no love.*).
-- Sprites are drawn from these numbers so their static proportions match (see tests/).
--
-- The player is a fixed upright sprite. The racket is a fixed-length stick whose handle
-- is attached at the right shoulder; it rotates in 2D (screen plane) to point at the
-- shuttle's height: straight up for the highest contact, level at shoulder height,
-- down for low ones. Highest reach = SHOULDER_HEIGHT + RACKET_LENGTH.
local Body = {
  HEIGHT = 1.75,            -- m, sprite height
  WIDTH = 0.42,             -- m, sprite width
  SHOULDER_HEIGHT = 1.44,   -- m, top of the torso (where the racket is held)
  RACKET_LENGTH = 0.75,     -- m, handle end to racket tip
  RACKET_HEAD = 0.26,       -- m, length of the head (part of RACKET_LENGTH)
  RACKET_HEAD_WIDTH = 0.22, -- m
  SHUTTLE_DIAMETER = 0.065, -- m
  -- Where the body stands relative to the shuttle at contact, in the player's own
  -- frame (left / behind), so the racket on the right side meets it.
  HIT_LEFT = 0.45,
  HIT_BEHIND = 0.20,
  READY_ANGLE = 60,         -- degrees above horizontal when not hitting
}

Body.MAX_REACH = Body.SHOULDER_HEIGHT + Body.RACKET_LENGTH   -- 2.19 m
Body.MIN_REACH = Body.SHOULDER_HEIGHT - Body.RACKET_LENGTH   -- 0.69 m (racket straight down)

-- Body position for contact at ground point p (side: +1 near, -1 far).
function Body.hittingSpot(p, side)
  return { x = p.x - side * Body.HIT_LEFT, y = p.y + side * Body.HIT_BEHIND }
end

-- Racket angle in radians above horizontal so the tip points at height h.
function Body.racketAngle(h)
  local s = (h - Body.SHOULDER_HEIGHT) / Body.RACKET_LENGTH
  return math.asin(math.max(-1, math.min(1, s)))
end

return Body
