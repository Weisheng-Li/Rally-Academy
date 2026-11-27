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
  ARM_LENGTH = 0.62,        -- m, shoulder to hand (training demo: holding a bottle, phone, weights)
}

Body.HIP_HEIGHT = Body.HEIGHT * 0.42                            -- 0.735 m, leg length when standing
Body.TORSO_LENGTH = Body.SHOULDER_HEIGHT - Body.HIP_HEIGHT       -- 0.705 m, hip to shoulder

-- Overreach: the legs are at full lunge, so the extra distance comes from tilting the upper
-- body toward the shuttle. The shoulder moves forward by TORSO_LENGTH * sin(lean), so the
-- lean is just enough to cover the overreach (m). Returns radians.
function Body.leanFor(overreach)
  return math.asin(math.max(0, math.min(1, overreach / Body.TORSO_LENGTH)))
end

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

-- Racket angle (rad) that puts the head centre (the strings) at height h, swung low on the
-- right side.
local HEAD_R = Body.RACKET_LENGTH - Body.RACKET_HEAD / 2
function Body.angleForHead(h)
  return math.asin(math.max(-1, math.min(1, (h - Body.SHOULDER_HEIGHT) / HEAD_R)))
end

return Body
