-- Footwork animation for one athlete in a match: turns the athlete's state (position,
-- destination, pause, contact pose) into a Figure.stance pose every frame.
-- No love.* calls (state + maths only), so tests can drive it.
--
--   moving        shuffle (short sideways moves) or run (long or forward/back moves),
--                 stepping in time with the distance covered so feet don't skate
--   approaching   the last `lunge.start` m before a contact blend into the lunge:
--                 controlled (on time) or overreach (stretched contact: the upper body
--                 tilts toward the shuttle by Body.leanFor, the back foot trails)
--   contact       the lunge is held through the decision freeze
--   recovering    the lunge blends back to standing over the recovery pause
--   new move      a small split-step hop
local Body = require("src.core.body")
local Figure = require("src.view.figure")
local A = require("src.config.animation")
local Shots = require("src.core.shots")

local Animator = {}
Animator.__index = Animator

local STAND = Body.HIP_HEIGHT

local function smooth(u) return u * u * (3 - 2 * u) end
local function mix(a, b, w) return a + (b - a) * w end
local function clamp01(u) return math.max(0, math.min(1, u)) end

-- Low serve racket angle (rad). While serving pass toss (0 holding .. 1 contact): the racket
-- hangs back, then swings underarm in the last `swing` s, accelerating into the contact angle.
-- After contact pass follow (s since contact): short follow-through, then back to ready.
function Animator.serveRacket(toss, follow)
  local S = A.serve
  local contact = Shots.serveGeometry({ x = 0, y = 0 }, 1).angle
  if toss then
    local T = Shots.data.serveToss.time
    local s = clamp01((toss * T - (T - S.swing)) / S.swing)
    return mix(math.rad(S.holdAngle), contact, s * s)
  end
  if follow <= S.follow then return mix(contact, math.rad(S.followAngle), smooth(follow / S.follow)) end
  return mix(math.rad(S.followAngle), math.rad(Body.READY_ANGLE), smooth(clamp01((follow - S.follow) / S.settle)))
end

-- Gait pose at distance s (m) covered in the current move.
-- Returns front, back, hip, lift, frontLift, backLift, runKnees.
function Animator.gaitPose(gait, s)
  if gait == "run" then
    local R = A.run
    local ph = 2 * math.pi * s / R.stride
    return R.amp * math.sin(ph), -R.amp * math.sin(ph), R.hip - 0.03 * math.abs(math.sin(ph)), 0,
           R.lift * math.max(0, math.cos(ph)), R.lift * math.max(0, -math.cos(ph)), true
  end
  local S = A.shuffle
  local u = math.abs(math.sin(math.pi * s / S.step))      -- 0 = feet wide, 1 = closed in
  local w = S.wide + (S.narrow - S.wide) * u
  return w / 2, -w / 2, S.hip, S.hop * u, 0, 0, false
end

-- Run or shuffle for a move of length `len` in direction (dx, dy). Forward/back moves are
-- judged by how much of the move shows sideways on screen (ex from the camera).
function Animator.gaitFor(cam, from, dx, dy, len)
  if len > A.run.from then return "run" end
  local _, _, s = cam:project(from.x, from.y, 0)
  local x0 = cam:project(from.x, from.y, 0)
  local x1 = cam:project(from.x + dx / len * 0.1, from.y + dy / len * 0.1, 0)
  local ex = (x1 - x0) / (0.1 * s)
  return math.abs(ex) < A.run.inOut and "run" or "shuffle"
end

function Animator.new(side)
  return setmetatable({ side = side, lunge = 0, travelled = 0, hop = 0,
                        dir = { x = 0, y = -side } }, Animator)
end

local function dist(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end

function Animator:update(a, dt, cam)
  local pos = a.pos
  local last = self.last or pos
  local step = dist(pos, last)
  self.last = { x = pos.x, y = pos.y }
  if step > 1.0 then                       -- placed for a new rally: start fresh
    self.lunge, self.kind, self.dest, self.travelled = 0, nil, nil, 0
    step = 0
  end
  self.travelled = self.travelled + step

  -- a new move: decide the gait, remember its direction, split-step hop
  local moving = a.dest ~= nil and a.delay <= 0
  if a.dest and (not self.dest or dist(a.dest, self.dest) > 1e-3) then
    self.dest = { x = a.dest.x, y = a.dest.y }
    local dx, dy = a.dest.x - pos.x, a.dest.y - pos.y
    local len = math.sqrt(dx * dx + dy * dy)
    self.moveLen = len
    if len > 1e-3 then
      self.dir = { x = dx / len, y = dy / len }
      self.gait = Animator.gaitFor(cam, pos, dx, dy, len)
    end
    self.travelled = 0
    self.hopPending = true
  end
  if not a.dest then self.dest = nil end
  if moving and self.hopPending then self.hop, self.hopPending = A.splitHop.time, false end
  self.hop = math.max(0, self.hop - dt)

  -- low serve: no footwork; the racket swing is timed by the toss (rally sets pose.toss)
  local pose = a.pose
  if pose and pose.state == "serve" then
    self.serveToss, self.serveFollow = pose.toss or 0, nil
    self.lunge, self.kind, self.h = 0, nil, nil
    self.moving = moving
    return
  end
  if self.serveToss then self.serveToss, self.serveFollow = nil, 0 end   -- just hit it
  if self.serveFollow then
    self.serveFollow = self.serveFollow + dt
    if self.serveFollow > A.serve.follow + A.serve.settle then self.serveFollow = nil end
  end

  -- lunge: from the contact pose the athlete is moving to (rally sets a.pose)
  if pose and pose.state then
    self.serveFollow = nil                   -- next contact already lined up
    local stretched = pose.state == "stretched"
    if stretched then self.kind, self.stretch = "overreach", pose.stretch or 1
    elseif (self.moveLen or 0) >= A.lunge.minMove and pose.state ~= "early" then self.kind, self.stretch = "controlled", 0
    else self.kind = nil end
    if self.kind then
      local target = 1
      if moving then target = math.max(0, math.min(1, 1 - dist(pos, a.dest) / A.lunge.start)) end
      self.lunge = math.max(self.lunge, smooth(target))
    else
      self.lunge = 0
    end
    self.h = pose.h or (stretched and Body.MIN_REACH) or nil
  else
    -- after the hit: blend back to standing over the recovery pause
    local pause = math.max(0.15, a.delayTotal or 0.25)
    self.lunge = math.max(0, self.lunge - dt / pause)
    if self.lunge <= 0 then self.kind, self.h = nil, nil end
  end
  self.moving = moving
end

-- Figure.stance parameters for the athlete right now, plus the body lift (m).
function Animator:stance(a, cam)
  local S = A.stand
  local front, back, hip, lift, fl, bl, runKnees = S.front, S.back, STAND, 0, 0, 0, false
  local lean = 0
  if self.moving and self.lunge < 1 then
    front, back, hip, lift, fl, bl, runKnees = Animator.gaitPose(self.gait or "shuffle", self.travelled)
  end
  local w = self.lunge
  if w > 0 and self.kind then
    local K = A.lunge[self.kind]
    local kb = K.back
    if K.straight > 0 then kb = Figure.straightBack(cam, a.pos, self.dir, K.hip) end
    local kl = K.lean or Body.leanFor(K.base + K.perStretch * (self.stretch or 1))
    front, back, hip = mix(front, K.front, w), mix(back, kb, w), mix(hip, K.hip, w)
    lift, fl, bl = lift * (1 - w), fl * (1 - w), bl * (1 - w)
    lean = kl * w
    if w > 0.5 then runKnees = false end
  end
  if self.hop > 0 then lift = lift + A.splitHop.height * math.sin(math.pi * self.hop / A.splitHop.time) end
  local racketAngle
  if self.serveToss or self.serveFollow then
    racketAngle = Animator.serveRacket(self.serveToss, self.serveFollow)
  end
  return { cog = a.pos, dir = self.dir, hipH = hip, front = front, back = back, lean = lean,
           h = self.h, frontLift = fl, backLift = bl, runKnees = runKnees,
           racketAngle = racketAngle }, lift
end

return Animator
