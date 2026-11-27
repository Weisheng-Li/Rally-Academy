-- Training demo world: the court (with the feeder) and the gym, and the athlete acting out
-- whatever src/core/training.lua says he is doing. The sim decides what and when (reps, breaks,
-- moods); this file only decides how it looks: where he stands, his pose, props, shuttles.
-- Sprites go through src/view/figure.lua (sizes from src/core/body.lua).
local Layout = require("src.config.layout")
local CourtView = require("src.view.court_view")
local Figure = require("src.view.figure")
local Draw = require("src.view.draw")
local Assets = require("src.view.assets")
local Body = require("src.core.body")
local Court = require("src.core.court")
local Animator = require("src.view.animator")
local Anim = require("src.config.animation")
local Training = require("src.core.training")

local TL = Layout.training
local C, TC = Layout.colors, Layout.training.colors
local CS, GS = TL.court, TL.gym
local STAND = Body.HIP_HEIGHT
local TD = Training.data
-- the feeder stands so his racket head (screen left of him) is at the feed point
local FEED_STAND = Body.hittingSpot(TD.feeder, -1)
-- tidying up: stands standX/standY (m) from a shuttle to reach it with the racket (within
-- reach m), scoops it at `scoop` s, it flies `flight` s into the basket, next one after `cycle` s
-- underNet: shuttles on the athlete's side closer than this (m) to the net he reaches under for;
-- further ones stay where they are
local FLICK = { standX = 0.45, standY = 0.2, reach = 0.08, scoop = 0.3, cycle = 0.75, flight = 0.7, underNet = 0.6 }

local View = {}
View.__index = View

local function smooth(u) u = math.max(0, math.min(1, u)) return u * u * (3 - 2 * u) end
local function mix(a, b, w) return a + (b - a) * w end
local function lerpP(a, b, w) return { x = mix(a.x, b.x, w), y = mix(a.y, b.y, w) } end
local function dist(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end
local function copy(p) return { x = p.x, y = p.y } end
local function norm(dx, dy)
  local l = math.sqrt(dx * dx + dy * dy)
  if l < 1e-6 then return nil end
  return { x = dx / l, y = dy / l }
end

local FACE_NET = { x = 0, y = -1 }
local SIDE_R, SIDE_L = { x = 1, y = 0 }, { x = -1, y = 0 }

-- walking: like the run gait but shorter, lower steps
local WALK = { stride = 1.3, amp = 0.2, lift = 0.07, hip = 0.73 }
local function walkPose(s)
  local ph = 2 * math.pi * s / WALK.stride
  return WALK.amp * math.sin(ph), -WALK.amp * math.sin(ph), WALK.hip - 0.01 * math.abs(math.sin(ph)),
         WALK.lift * math.max(0, math.cos(ph)), WALK.lift * math.max(0, -math.cos(ph))
end

local function standing(cog, dir)
  return { cog = cog, dir = dir or FACE_NET, hipH = STAND, front = Anim.stand.front, back = Anim.stand.back, lean = 0 }
end

function View.new(cam)
  local self = setmetatable({}, View)
  self.cam = cam
  self.pos = copy(CS.entry)
  self.dir = SIDE_L
  self.travelled = 0
  self.feeder = { pos = copy(FEED_STAND), travelled = 0, dir = { x = 0, y = 1 } }
  self.flying = {}        -- shuttles the feeder flicked toward the basket
  self.pile = {}          -- shuttles lying on the far court (the feeder collects them)
  self.popups = {}
  self.time = 0
  self.loc = nil
  return self
end

-- After the sim jumped to another time: drop what was going on and start in the new room.
function View:reset()
  self.loc, self.act, self.pose = nil, nil, nil
  self.pile, self.flying, self.popups = {}, {}, {}
  self.feeder.pos = copy(FEED_STAND)
  self.feeder.flickT = nil
end

---------------------------------------------------------------------------- spots
local function locSpots(loc) return loc == "gym" and GS or CS end

-- Where the current activity happens (nil = wherever he is).
function View:anchor(s)
  local a = s.activity
  local S = locSpots(s.location)
  if a.kind == "drill" then return CS.base, FACE_NET end
  if a.kind == "exercise" then
    if a.name == "squat" then return { x = GS.rack.x, y = GS.rack.y + 0.35 }, SIDE_R end
    if a.name == "skip" then return GS.skip, SIDE_R end
    if a.name == "treadmill" then return GS.treadmill, SIDE_R end
    if a.name == "press" then return GS.press, SIDE_R end
    if a.name == "jog" then return { x = CS.jog.x1, y = CS.jog.y2 }, SIDE_R end
  end
  if a.kind == "walk" then return nil end
  if a.kind == "arrive" then return S == GS and GS.idle or CS.base, FACE_NET end
  if a.kind == "home" then return S.entry, nil end
  local n = a.name
  if n == "water" then return S.water, s.location == "gym" and SIDE_L or SIDE_R end
  if n == "chat" then return CS.chat, FACE_NET end
  if n == "juggle" then return CS.juggle, FACE_NET end
  if n == "selfie" then return GS.selfie, FACE_NET end
  if n == "music" and s.location == "gym" and a.dur < 10 then return { x = -0.9, y = -1.0 }, FACE_NET end
  if n == "bench" or n == "snack" or n == "music" or n == "phone" and s.location == "gym" then
    return { x = GS.bench.x, y = GS.bench.y }, SIDE_R
  end
  if n == "phone" then return { x = CS.water.x - 0.3, y = CS.water.y - 0.5 }, SIDE_R end
  if n == "nap" then return GS.mat, SIDE_R end
  return nil
end

---------------------------------------------------------------------------- drill rep geometry
-- Point on a recorded flight path (world {x,y,h} every dt s) at time t.
local function onPath(path, dt, t)
  local i = t / dt
  local j = math.floor(i)
  if j >= #path - 1 then local p = path[#path]; return { pos = { x = p.x, y = p.y }, h = p.h }, true end
  local a, b = path[j + 1], path[j + 2]
  local f = i - j
  return { pos = { x = mix(a.x, b.x, f), y = mix(a.y, b.y, f) }, h = mix(a.h, b.h, f) }, false
end
local NET_DROP = 0.45      -- s for a shuttle that hit the net to slide down the cloth

-- Everything about drill rep `cur` at rep time ts (s since the feeder fed it). The shuttle
-- follows the real flights from the sim (feed, then his shot); he moves to meet it.
function View:drillRep(a, cur, ts)
  local R = cur.endT - cur.t0
  local c = cur.contactT - cur.t0
  local spot = cur.contact
  local hit = Body.hittingSpot(spot, 1)
  local out = { hit = hit }
  -- shuttle
  if ts < c then
    out.shuttle = onPath(cur.feed, cur.dt, ts)
  else
    local p, done = onPath(cur.ret, cur.dt, ts - c)
    if not done then
      out.shuttle = p
    elseif cur.outcome == "net" and p.h > 0.05 then   -- caught in the net: slides down the cloth
      -- (a net shot that falls short lands on his side instead: it just stays where it fell)
      local u = (ts - c - cur.retTime) / NET_DROP
      if u < 1 then out.shuttle = { pos = { x = p.pos.x, y = 0.05 }, h = p.h * (1 - u * u) }
      else out.landed = { x = p.pos.x, y = 0.05 } end
    else
      out.landed = p.pos
    end
  end
  -- player: split hop, move to the hitting spot, contact, move back
  local base = CS.base
  local len = dist(base, hit)
  local dir = norm(hit.x - base.x, hit.y - base.y) or FACE_NET
  local overhead = cur.h > 1.8
  local m0, hold = 0.12, 0.25
  local st, lift
  local gait = Animator.gaitFor(self.cam, base, dir.x * len, dir.y * len, math.max(len, 0.01))
  local lungeKind = "controlled"
  local function gaitAt(sDist, d)
    local front, back, hip, l, fl, bl, knees = Animator.gaitPose(gait, sDist)
    return { dir = d, hipH = hip, front = front, back = back, frontLift = fl, backLift = bl, runKnees = knees, lean = 0 }, l
  end
  local function lungeAt(w, cog)
    local K = Anim.lunge[lungeKind]
    local kb = K.straight > 0 and Figure.straightBack(self.cam, cog, dir, K.hip) or K.back
    local kl = K.lean or Body.leanFor(K.base + K.perStretch * 0.6)
    return w * K.front, w * kb, mix(STAND, K.hip, w), kl * w
  end
  if ts < m0 then
    st, lift = standing(copy(base)), 0.1 * math.sin(math.pi * ts / m0)
  elseif ts < c then
    local u = (ts - m0) / (c - m0)
    local cog = lerpP(base, hit, u)
    st, lift = gaitAt(u * len, dir)
    st.cog = cog
    local w = overhead and 0 or smooth(1 - (1 - u) * len / Anim.lunge.start)
    if len < Anim.lunge.minMove then w = 0 end
    if w > 0 then
      local f, b, hip, lean = lungeAt(w, cog)
      st.front, st.back, st.hipH, st.lean = mix(st.front, f, w), mix(st.back, b, w), mix(st.hipH, hip, w), lean
      st.frontLift, st.backLift, lift = st.frontLift * (1 - w), st.backLift * (1 - w), lift * (1 - w)
      if w > 0.5 then st.runKnees = false end
    end
    st.h = cur.h
    if a.name == "smash" and u > 0.75 then lift = 0.3 * math.sin(math.pi * (u - 0.75) / 0.5) end
  elseif ts < c + hold then
    st, lift = standing(copy(hit), dir), 0
    if not overhead and len >= Anim.lunge.minMove then
      st.front, st.back, st.hipH, st.lean = lungeAt(1, hit)
    end
    st.h = cur.h
    if a.name == "smash" then lift = 0.3 * math.sin(math.pi * (0.25 + (ts - c) / hold * 0.25 + 0.5)) end
    if overhead then st.racketAngle = math.rad(mix(80, a.name == "smash" and -30 or 20, (ts - c) / hold)) end
  else
    local back = math.max(c + hold + 0.5, R - 0.15)
    local u = math.min(1, (ts - c - hold) / (back - c - hold))
    if ts >= back then
      st, lift = standing(copy(base)), 0
    else
      st, lift = gaitAt(u * len, { x = -dir.x, y = -dir.y })
      st.cog = lerpP(hit, base, u)
      st.dir = FACE_NET
      local w = overhead and 0 or 1 - smooth(u / 0.4)
      if w > 0 and len >= Anim.lunge.minMove then
        local f, b, hip, lean = lungeAt(w, st.cog)
        st.dir = dir
        st.front, st.back, st.hipH, st.lean = mix(st.front, f, w), mix(st.back, b, w), mix(st.hipH, hip, w), lean
        lift = lift * (1 - w)
      end
    end
  end
  out.st, out.lift = st, lift
  return out
end

---------------------------------------------------------------------------- update
function View:popup(text, color, big)
  self.popups[#self.popups + 1] = { text = text, color = color, t = 0, big = big, x = self.pos.x, y = self.pos.y }
end

local function qualityText(e)
  local name = e.skill
  if e.quality == "perfect" then return string.format("+%g %s  perfect!", e.gain, name), TC.perfect end
  if e.quality == "miss" then
    local why = ({ net = "in the net", long = "long", wide = "wide", short = "short" })[e.outcome] or "miss"
    return string.format("+%g %s  (%s)", e.gain, name, why), C.textDim
  end
  return string.format("+%s %s", e.gain and string.format("%g", e.gain) or "1", name), C.good
end

-- Things he walks around (court metres): the courtside bench, padded by `clear` m.
local function obstacles(loc)
  if loc ~= "court" then return {} end
  local B, BL = CS.bench, TL.courtBench
  local c = BL.clear
  return { { x1 = B.x - BL.hx - c, x2 = B.x + BL.hx + c, y1 = B.y - BL.hy - c, y2 = B.y + BL.hy + c } }
end

local function inside(r, p) return p.x > r.x1 and p.x < r.x2 and p.y > r.y1 and p.y < r.y2 end

local function crosses(r, a, b)
  for i = 1, 24 do
    local u = i / 25
    if inside(r, { x = a.x + (b.x - a.x) * u, y = a.y + (b.y - a.y) * u }) then return true end
  end
  return false
end

-- Next point to head for on the way to goal: straight there, or via the corner of an obstacle
-- that keeps the detour shortest.
function View:steer(goal)
  for _, r in ipairs(obstacles(self.loc)) do
    if not inside(r, goal) and not inside(r, self.pos) and crosses(r, self.pos, goal) then
      local best, bestD
      for _, c in ipairs({ { x = r.x1, y = r.y1 }, { x = r.x2, y = r.y1 }, { x = r.x1, y = r.y2 }, { x = r.x2, y = r.y2 } }) do
        local d = dist(self.pos, c) + dist(c, goal)
        if dist(self.pos, c) > 0.01 and not crosses(r, self.pos, c) and (not bestD or d < bestD) then best, bestD = c, d end
      end
      if best then return best end
    end
  end
  return goal
end

-- How far through the current gym rep (0..1). Reps vary in length (quicker while the coach
-- pushes him), so this comes from the rep's own start and end.
function View:repPhase(a)
  local cur = a.cur
  if not cur then return 0 end
  return math.max(0, math.min(1, (a.t - cur.t0) / math.max(1e-6, cur.endT - cur.t0)))
end

function View:walkTo(goal, dt, speed)
  goal = self:steer(goal)
  local d = dist(self.pos, goal)
  if d < 1e-3 then return false end
  local step = math.min(d, speed * dt)
  self.dir = norm(goal.x - self.pos.x, goal.y - self.pos.y) or self.dir
  self.pos = { x = self.pos.x + self.dir.x * step, y = self.pos.y + self.dir.y * step }
  self.travelled = self.travelled + step
  return true
end

function View:update(s, dt)
  self.time = self.time + dt
  for _, e in ipairs(s.events) do
    if e.type == "rep" then
      local text, col = qualityText(e)
      self:popup(text, col)
    elseif e.type == "levelup" then
      self:popup(string.format("%s  LEVEL %d!", e.skill:upper(), e.level), TC.levelup, true)
    end
  end
  for i = #self.popups, 1, -1 do
    local p = self.popups[i]
    p.t = p.t + dt
    if p.t > (p.big and 2.6 or 1.4) then table.remove(self.popups, i) end
  end

  local a = s.activity
  if self.loc ~= s.location then            -- arrived in the other room: come in from its door
    local first = self.loc == nil
    self.loc = s.location
    self.pos = copy(locSpots(s.location).entry)
    -- jumped straight into the day (--clock): start in the room, not at the door
    if first and a.kind ~= "arrive" then self.pos = copy(s.location == "gym" and GS.idle or CS.base) end
  end
  if a ~= self.act then
    self.act, self.arrived, self.actT0 = a, false, a.t
    self.lastRep = nil
  end

  self.walking = false
  self.pose = nil
  local speed = TL.walkSpeed
  if a.kind == "walk" then
    local goal = a.switched and (s.location == "gym" and GS.idle or CS.base) or locSpots(a.from).entry
    local left = (a.switched and a.dur or a.dur / 2) - a.t
    speed = math.max(speed, dist(self.pos, goal) / math.max(0.2, left))
    self.walking = self:walkTo(goal, dt, speed)
  elseif a.kind == "drill" and a.t >= a.lead and a.cur then
    self.arrived = true
    local ts = a.t - a.cur.t0
    local r = self:drillRep(a, a.cur, ts)
    self.pose = r
    self.pos = copy(r.st.cog)
    if r.landed and self.lastRep ~= a.cur.i then
      self.lastRep = a.cur.i
      self.pile[#self.pile + 1] = { x = r.landed.x, y = r.landed.y }   -- stays exactly where it landed
      if #self.pile > 50 then table.remove(self.pile, 1) end
    end
  elseif a.kind == "exercise" and a.name == "jog" and a.t >= a.lead then
    self.arrived = true
    local J = CS.jog
    local w, h = J.x2 - J.x1, J.y2 - J.y1
    local P = 2 * (w + h)
    local d = (self:repPhase(a) + math.max(0, (a.cur and a.cur.i or 1) - 1)) * P   -- one lap per rep
    local dd = d % P
    local p, dir
    if dd < w then p, dir = { x = J.x1 + dd, y = J.y2 }, SIDE_R
    elseif dd < w + h then p, dir = { x = J.x2, y = J.y2 - (dd - w) }, { x = 0, y = -1 }
    elseif dd < 2 * w + h then p, dir = { x = J.x2 - (dd - w - h), y = J.y1 }, SIDE_L
    else p, dir = { x = J.x1, y = J.y1 + (dd - 2 * w - h) }, { x = 0, y = 1 } end
    self.pos, self.dir, self.travelled = p, dir, d
    self.jogging = true
  else
    local goal, face = self:anchor(s)
    if goal and not self.arrived then
      local left = (a.lead or 2.0) - a.t
      if a.lead then speed = math.max(speed, dist(self.pos, goal) / math.max(0.25, left)) end
      self.walking = self:walkTo(goal, dt, speed)
      if not self.walking then self.arrived, self.actT0 = true, a.t end
    elseif not goal then
      self.arrived = true
    end
    self.face = face
  end
  if a.name ~= "jog" then self.jogging = false end

  self:updateFeeder(s, dt)
end

-- Feeder: feeds during drills, chats at the net, collects shuttles during breaks.
function View:reachablePile()
  for _, p in ipairs(self.pile) do if p.y < FLICK.underNet then return true end end
  return false
end

function View:updateFeeder(s, dt)
  local F = self.feeder
  local a = s.activity
  F.walking = false
  local function go(goal, speed)
    local d = dist(F.pos, goal)
    if d < 0.02 then return false end
    local step = math.min(d, (speed or 1.6) * dt)
    F.dir = norm(goal.x - F.pos.x, goal.y - F.pos.y) or F.dir
    F.pos = { x = F.pos.x + F.dir.x * step, y = F.pos.y + F.dir.y * step }
    F.travelled = F.travelled + step
    F.walking = true
    return true
  end
  -- shuttles he flicked, flying into the basket
  local B = CS.basket
  for i = #self.flying, 1, -1 do
    local fl = self.flying[i]
    fl.t = fl.t + dt
    if fl.t >= FLICK.flight then table.remove(self.flying, i) end
  end
  local flicking = false
  if a.kind == "drill" or (a.kind == "walk" and a.to == "court") or a.kind == "arrive" then
    if not go(FEED_STAND, 2.5) then F.dir = { x = 0, y = 1 } end
  elseif a.name == "chat" and s.location == "court" then
    if not go(CS.chatFeeder) then F.dir = { x = 0, y = 1 } end
  elseif self:reachablePile() then
    -- tidy up: walk up to the nearest shuttle, scoop it up with the racket and flick it
    -- into the basket (far player: the racket is on his screen left, so stand to its right)
    local target, best = nil, 1e9
    for i, p in ipairs(self.pile) do
      local d = dist(F.pos, p)
      if p.y < FLICK.underNet and d < best then target, best = i, d end
    end
    local p = self.pile[target]
    -- he stays on his side of the net: shuttles just over it he reaches under the net
    local goal = { x = p.x + FLICK.standX, y = math.min(p.y - FLICK.standY, -0.3) }
    if dist(F.pos, goal) > FLICK.reach and go(goal) then
      F.flickT = 0
    else
      flicking = true
      F.dir = norm(B.x - F.pos.x, B.y - F.pos.y) or F.dir
      F.flickT = (F.flickT or 0) + dt
      if F.flickT >= FLICK.scoop and not F.flicked then
        table.remove(self.pile, target)
        self.flying[#self.flying + 1] = { from = { x = p.x, y = p.y }, t = 0 }
        F.flicked = true
      end
      if F.flickT >= FLICK.cycle then F.flickT, F.flicked = 0, false end
    end
  else
    if not go(FEED_STAND) then F.dir = { x = 0, y = 1 } end
  end
  if not flicking then F.flickT, F.flicked = nil, false end
end

---------------------------------------------------------------------------- poses
-- The athlete's pose right now: stance params, body lift (m), arms/props, racket shown?
function View:playerPose(s)
  local a = s.activity
  local t = self.time
  if self.pose then
    return { st = self.pose.st, lift = self.pose.lift, racket = true }
  end
  if self.walking or self.jogging then
    local front, back, hip, fl, bl, knees, lift
    if self.jogging then
      front, back, hip, lift, fl, bl, knees = Animator.gaitPose("run", self.travelled * 0.9)
    else
      front, back, hip, fl, bl = walkPose(self.travelled)
      lift = 0
    end
    return { st = { cog = self.pos, dir = self.dir, hipH = hip, front = front, back = back, lean = 0,
                    frontLift = fl, backLift = bl, runKnees = true }, lift = lift, racket = s.location == "court" and a.kind ~= "exercise" }
  end
  local face = self.face or FACE_NET
  local st = standing(self.pos, face)
  local P = { st = st, lift = 0, racket = s.location == "court" and a.kind ~= "exercise", arms = {} }
  local lt = a.t - (self.actT0 or 0)       -- seconds since he got there
  local n = a.name
  if not self.arrived then return P end

  if a.kind == "exercise" then
    local ts = math.max(0, a.t - a.lead)
    local u = self:repPhase(a)
    P.racket = false
    st.dir = SIDE_R
    if n == "squat" then
      local depth = math.sin(math.pi * u) ^ 2
      st.hipH = mix(STAND, 0.42, depth)
      st.front, st.back, st.runKnees = 0.16, 0.0, true
      st.lean = 0.45 * depth
      st.cog = { x = self.pos.x - 0.12 * depth, y = self.pos.y }
      P.barbell = true
    elseif n == "skip" then
      local ph = (ts * 2.2) % 1                      -- 2.2 jumps per second
      P.lift = 0.09 * math.max(0, math.sin(math.pi * ph * 1.0))
      P.rope = ph
      st.front, st.back = 0.03, -0.03
    elseif n == "treadmill" then
      local front, back, hip, lift, fl, bl, knees = Animator.gaitPose("run", ts * 2.8)
      st.front, st.back, st.hipH, st.frontLift, st.backLift, st.runKnees = front, back, hip, fl, bl, knees
      P.lift = lift + 0.18                          -- standing on the deck
    elseif n == "press" then
      local up = math.sin(math.pi * u) ^ 2
      local ang = math.rad(mix(35, 88, up))
      P.arms = { { angle = ang, reach = mix(0.45, 1, up), prop = "dumbbell" },
                 { angle = ang, mirror = -1, reach = mix(0.45, 1, up), prop = "dumbbell" } }
    end
    return P
  end

  if n == "water" then
    local sip = (lt % 4) < 2.2
    P.racket = false
    if sip then P.drink = true else P.arms = { { angle = math.rad(-60), reach = 0.85, prop = "bottle" } } end
  elseif n == "shoelace" then
    st.dir, st.hipH, st.front, st.back, st.lean = SIDE_R, 0.34, 0.28, -0.3, 0.9
    P.racket = false
  elseif n == "chat" then
    st.dir = FACE_NET
    P.lift = 0.01 * math.sin(t * 3)
  elseif n == "juggle" then
    st.dir = FACE_NET
    P.racketAngle = math.rad(12)
    P.juggle = true
  elseif n == "stretch" then
    local left = lt % 8 >= 4
    st.dir = left and SIDE_L or SIDE_R
    st.hipH, st.front, st.lean = 0.5, 0.45, 0.05
    st.back = Figure.straightBack(self.cam, st.cog, st.dir, 0.5)
    P.racket = false
  elseif n == "phone" or (n == "music" and a.dur < 10) then
    P.racket = false
    P.arms = { { angle = math.rad(-15), reach = 0.55, prop = "phone" } }
    if s.location == "gym" and n == "phone" then self:sit(P) end
  elseif n == "yawn" then
    P.racket = false
  elseif n == "selfie" then
    P.racket = false
    P.arms = { { angle = math.rad(70), reach = 0.95, prop = "phone" } }
    P.flash = (lt % 2.5) < 0.12 and lt > 1
    st.lean = 0
  elseif n == "bench" then
    self:sit(P)
  elseif n == "snack" then
    self:sit(P)
    local bite = (lt % 3) < 1.1
    P.arms = { { angle = math.rad(bite and 100 or -20), reach = bite and 0.7 or 0.6, prop = "banana" } }
  elseif n == "music" then
    self:sit(P)
    P.lift = 0.015 * math.abs(math.sin(t * 4.2))
    P.notes = true
  elseif n == "nap" then
    P.lying = true
  elseif n == "sulk" then
    P.racketAngle = math.rad(-80)
    st.lean = 0.1
    P.lift = 0
    if lt % 2 < 0.3 then st.front = 0.25 end      -- kicks the floor
  elseif n == "celebrate" then
    P.lift = 0.25 * math.max(0, math.sin(math.pi * math.min(1, lt / 0.6)))
    P.racketAngle = math.rad(85)
  end
  return P
end

function View:sit(P)
  local st = P.st
  st.dir = SIDE_R
  st.hipH = 0.5
  st.front, st.back, st.runKnees = 0.42, 0.36, true
  P.racket = false
  P.seated = true
end

---------------------------------------------------------------------------- drawing
local function proj(cam, x, y, h) return cam:project(x, y, h or 0) end

local function shade(c, f) return { c[1] * f, c[2] * f, c[3] * f, c[4] } end

-- Box on the floor: x/y centre, half sizes hx/hy, from height z0 (default 0) up to h.
-- Draws the front face, the end face turned toward the camera (boxes off to one side show
-- it) and the top.
local function box(cam, x, y, hx, hy, h, top, side, z0)
  z0 = z0 or 0
  local ax, ay = proj(cam, x - hx, y + hy, z0)
  local bx, by = proj(cam, x + hx, y + hy, z0)
  local cx, cy = proj(cam, x + hx, y + hy, h)
  local dx, dy = proj(cam, x - hx, y + hy, h)
  local ex, ey = proj(cam, x + hx, y - hy, h)
  local fx, fy = proj(cam, x - hx, y - hy, h)
  -- right of centre we see its left end, left of centre its right end
  local seen = (x - hx > 0) and -1 or ((x + hx < 0) and 1 or 0)
  if seen ~= 0 then
    local sx = x + seen * hx
    local p1x, p1y = proj(cam, sx, y - hy, z0)
    local p2x, p2y = proj(cam, sx, y + hy, z0)
    local p3x, p3y = proj(cam, sx, y + hy, h)
    local p4x, p4y = proj(cam, sx, y - hy, h)
    Draw.color(shade(side, 0.8))
    love.graphics.polygon("fill", p1x, p1y, p2x, p2y, p3x, p3y, p4x, p4y)
  end
  Draw.color(side)
  love.graphics.polygon("fill", ax, ay, bx, by, cx, cy, dx, dy)
  Draw.color(top)
  love.graphics.polygon("fill", dx, dy, cx, cy, ex, ey, fx, fy)
end

function View:drawBody(f, lift, color, P)
  P = P or {}
  local alpha = P.alpha or 1
  Draw.color(C.shadow, 0.35 * alpha)
  love.graphics.ellipse("fill", f.groundX, f.groundY, f.bodyW * 0.8, f.bodyW * 0.3)
  love.graphics.push()
  love.graphics.translate(0, -(lift or 0) * f.k)
  local skin = { 0.95, 0.80, 0.65 }
  -- no arms or hands are drawn: a held prop just floats where the hand would be (Figure.arm).
  -- The other hand's prop (mirror) goes behind the body.
  local function drawArm(arm)
    self:drawProp(arm.prop, Figure.arm(f, arm.angle, arm.mirror, arm.reach), f, arm)
  end
  for _, arm in ipairs(P.arms or {}) do if arm.mirror == -1 then drawArm(arm) end end
  Draw.color({ 0.15, 0.15, 0.2 }, alpha)
  love.graphics.setLineWidth(f.legW)
  love.graphics.setLineJoin("bevel")
  for _, L in ipairs(f.legs) do love.graphics.line(L) end
  love.graphics.setLineWidth(1)
  Draw.color(color, alpha)
  love.graphics.polygon("fill", f.torso)
  Draw.color(skin, alpha)
  love.graphics.circle("fill", f.head.x, f.head.y, f.head.r)
  if P.cap then          -- coach's cap: crown over the top of the head, brim to the front
    Draw.color(P.cap, alpha)
    love.graphics.arc("fill", f.head.x, f.head.y - f.head.r * 0.1, f.head.r * 1.05, math.pi, math.pi * 2)
    love.graphics.rectangle("fill", f.head.x + (f.right > 0 and 0 or -f.head.r * 1.6), f.head.y - f.head.r * 0.25,
      f.head.r * 1.6, math.max(1, f.head.r * 0.3))
  end
  if P.drink then        -- bottle tipped up at his mouth (cap at the front of the face)
    View.drawBottle(f.head.x + f.right * f.head.r * 0.9, f.head.y + f.head.r * 0.3, f.k, math.pi + f.right * 0.6)
  end
  if P.headphones then
    Draw.color(TC.dark, alpha)
    love.graphics.setLineWidth(1)
    love.graphics.arc("line", "open", f.head.x, f.head.y, f.head.r + 1, math.pi * 1.05, math.pi * 1.95)
    love.graphics.rectangle("fill", f.head.x - f.head.r - 2, f.head.y - 1, 2, 4)
    love.graphics.rectangle("fill", f.head.x + f.head.r, f.head.y - 1, 2, 4)
  end
  if P.barbell then
    -- seen end-on (side view): the near plate, on the upper back just behind the neck
    local bx, by = f.shoulderMidX - f.right * f.k * 0.12, f.shoulderMidY + 1
    local r = f.k * 0.16
    Draw.color(TC.dark, alpha)
    love.graphics.circle("fill", bx, by, r)
    Draw.color(TC.metal, alpha)
    love.graphics.circle("line", bx, by, r)
    love.graphics.circle("fill", bx, by, 1)
  end
  for _, arm in ipairs(P.arms or {}) do if arm.mirror ~= -1 then drawArm(arm) end end
  if P.racket ~= false then
    CourtView.drawRacket(f, alpha)
  end
  if P.rope then
    -- rope loop from the hands around the body; the far point of the loop circles
    local hand = Figure.arm(f, math.rad(-55), 1, 0.7)
    local cx, cy = f.hipX, (f.head.y + f.groundY) / 2
    local ang = P.rope * 2 * math.pi + math.pi / 2       -- under the feet at the jump
    local rx, ry = f.bodyH * 0.45, f.bodyH * 0.62
    local px, py = cx + math.cos(ang) * rx * 0.3, cy + math.sin(ang) * ry
    Draw.color(TC.dark, alpha)
    local curve = love.math.newBezierCurve(hand.handX, hand.handY, px - rx * 0.5, py, px + rx * 0.5, py, hand.handX, hand.handY)
    love.graphics.line(curve:render(3))
  end
  love.graphics.pop()
end

-- Water bottle (m): drawn from its cap at (x, y), body hanging below, turned by rot (rad).
local BOTTLE = { w = 0.11, h = 0.32, cap = 0.04 }
function View.drawBottle(x, y, k, rot)
  local w, h, cap = math.max(3, BOTTLE.w * k), math.max(8, BOTTLE.h * k), math.max(1, BOTTLE.cap * k)
  love.graphics.push()
  love.graphics.translate(x, y)
  love.graphics.rotate(rot)
  Draw.color(TC.dark)
  love.graphics.rectangle("fill", -w * 0.3, 0, w * 0.6, cap)
  Draw.color(TC.water)
  love.graphics.rectangle("fill", -w / 2, cap, w, h - cap)
  love.graphics.setColor(1, 1, 1, 0.35)
  love.graphics.rectangle("fill", -w / 2 + 1, cap + 1, 1, h - cap - 2)
  love.graphics.pop()
end

-- Working harder (the coach's cheering sped him up): two sweat drops run down from his temples
-- and fall off, one after the other. self.time runs at his pace, so they drip faster the
-- faster he goes.
function View:drawWorkingHard(head)
  local r, t = head.r, self.time
  local d = math.max(1, r * 0.28)
  for i, side in ipairs({ -1, 1 }) do
    local ph = (t * 0.9 + i * 0.45) % 1
    local px = head.x + side * r * 0.95
    local py = head.cy - r * 0.2 + ph * ph * r * 3.5          -- slides, then falls faster
    Draw.color(TC.sweat, ph < 0.8 and 1 or (1 - ph) / 0.2)
    love.graphics.circle("fill", px, py, d)
    love.graphics.polygon("fill", px - d, py, px + d, py, px, py - d * 2.4)
  end
end

-- The coach bounces on his toes for a moment when he shouts (body lift, m).
function View:coachHop(s)
  local line = s.coachLine
  if not line or not line.shout then return 0 end
  local age = line.life - line.t
  if age > 0.3 then return 0 end
  return 0.08 * math.sin(math.pi * age / 0.3)
end

function View:drawProp(prop, g, f, arm)
  if not prop then return end
  local k = f.k
  if prop == "clipboard" then
    local w, h = math.max(3, 0.16 * k), math.max(4, 0.22 * k)
    Draw.color(TC.wood)
    love.graphics.rectangle("fill", g.handX - w / 2, g.handY - h / 2, w, h)
    Draw.color(TC.wallTrim)
    love.graphics.rectangle("fill", g.handX - w / 2 + 1, g.handY - h / 2 + 2, w - 2, h - 3)
    return
  end
  if prop == "bottle" then
    View.drawBottle(g.handX, g.handY - BOTTLE.h * k * 0.6, k, 0)
  elseif prop == "phone" then
    Draw.color(TC.dark)
    love.graphics.rectangle("fill", g.handX - 2, g.handY - 3, 4, 5)
    Draw.color(TC.phone, 0.7 + 0.3 * math.sin(self.time * 7))
    love.graphics.rectangle("fill", g.handX - 1, g.handY - 2, 2, 3)
  elseif prop == "banana" then
    Draw.color(TC.banana)
    love.graphics.arc("fill", "open", g.handX, g.handY - 3, math.max(3, k * 0.1), 0.2, math.pi - 0.2)
  elseif prop == "dumbbell" then
    Draw.color(TC.dark)
    local r = math.max(2, k * 0.07)
    love.graphics.rectangle("fill", g.handX - r, g.handY - r, r * 2, r * 2)
    Draw.color(TC.metal)
    love.graphics.rectangle("line", g.handX - r + 0.5, g.handY - r + 0.5, r * 2 - 1, r * 2 - 1)
  end
end

function View:drawLying(pos, color)
  local g = Figure.lying(self.cam, pos, -1)
  Draw.color(C.shadow, 0.35)
  love.graphics.ellipse("fill", g.groundX, g.groundY, g.length * 0.55, g.k * 0.12)
  Draw.color({ 0.15, 0.15, 0.2 })
  love.graphics.setLineWidth(g.legW)
  love.graphics.line(g.legs)
  love.graphics.setLineWidth(1)
  Draw.color(color)
  love.graphics.polygon("fill", g.torso)
  Draw.color({ 0.95, 0.80, 0.65 })
  love.graphics.circle("fill", g.head.x, g.head.y, g.head.r)
  -- zzz
  for i = 0, 2 do
    local u = (self.time * 0.5 + i / 3) % 1
    local a = math.sin(u * math.pi)
    love.graphics.setColor(1, 1, 1, a)
    love.graphics.setFont(Assets.fonts.small)
    love.graphics.print(u > 0.5 and "Z" or "z", g.head.x + 4 + u * 10, g.head.y - 6 - u * 22)
  end
  return g
end

-- Speech bubble whose tail points at (x, y).
local function bubble(text, x, y, fade)
  local font = Assets.fonts.small
  local w = font:getWidth(text) + 8
  local h = font:getHeight() + 4
  local bx = math.floor(math.max(2, math.min(Layout.width - w - 2, x - w / 2)))
  local by = math.floor(y - h - 6)
  local a = math.min(1, fade or 1)
  love.graphics.setColor(1, 1, 1, 0.92 * a)
  love.graphics.rectangle("fill", bx, by, w, h, 3, 3)
  love.graphics.polygon("fill", x - 3, by + h, x + 3, by + h, x, by + h + 4)
  love.graphics.setColor(0.1, 0.1, 0.12, a)
  love.graphics.setFont(font)
  love.graphics.print(text, bx + 4, by + 2)
end

function View:drawCourtRoom(s, items)
  local cam = self.cam
  CourtView.drawFloor(cam)
  -- feeder's shuttle basket, shuttles on the floor
  for _, p in ipairs(self.pile) do
    local x, y = proj(cam, p.x, p.y, 0)
    Draw.color(C.shuttle, 0.9)
    love.graphics.circle("fill", x, y, 1.2)
  end
  items[#items + 1] = { y = 0, draw = function() CourtView.drawNet(cam) end }
  local B = CS.basket
  items[#items + 1] = { y = B.y, draw = function()
    box(cam, B.x, B.y, 0.22, 0.22, 0.45, shade(C.lines, 0.75), shade(C.lines, 0.5))
    local x, y = proj(cam, B.x, B.y, 0.45)
    Draw.color(C.shuttle)
    for i = -2, 2 do love.graphics.circle("fill", x + i * 1.6, y - 1, 1.2) end
  end }
  -- courtside bench (long, along the sideline): blue seat on legs, his racket bag and his
  -- water bottle on it
  local bench = CS.bench
  local BL = TL.courtBench
  items[#items + 1] = { y = bench.y - BL.hy, draw = function()
    for _, dy in ipairs({ -BL.legY, BL.legY }) do
      box(cam, bench.x, bench.y + dy, BL.hx * 0.8, 0.04, BL.seat, TC.benchLeg, shade(TC.benchLeg, 0.7))
    end
    box(cam, bench.x, bench.y, BL.hx, BL.hy, BL.seat + BL.thick, TC.benchTop, TC.benchSide, BL.seat)
    -- racket bag standing on the seat, turned so its racket-shaped side faces the court
    local G = BL.bag
    local top = BL.seat + BL.thick
    View.drawRacketBag(cam, bench.x, bench.y + G.y, top, G, G.dir)
    local a = s.activity
    if not (a.name == "water" and self.arrived) then        -- his bottle waits on the bench
      local kb = Figure.scale(cam, bench.x, bench.y + BL.bottleY)
      local x, y = proj(cam, bench.x, bench.y + BL.bottleY, top)
      View.drawBottle(x, y - kb * 0.34, kb, 0)
    end
  end }
end

-- Racket bag side profile in its own metres (s along the bag 0..len, z up): the head end
-- (s = 0) is tall with a big rounded corner, the top slopes down to the lower handle end
-- (s = len). Closed outline of { s, z } points.
function View.bagProfile(G)
  local L, Hh, Hl, r, rb = G.len, G.hHead, G.hHandle, G.round, G.roundBottom
  local pts = {}
  local function add(s, z) pts[#pts + 1] = { s = s, z = z } end
  local function arc(cs, cz, rad, a0, a1, n)
    for i = 0, n do
      local a = a0 + (a1 - a0) * i / n
      add(cs + math.cos(a) * rad, cz + math.sin(a) * rad)
    end
  end
  local function topZ(s) return Hl + (Hh - Hl) * (1 - smooth((s - L * 0.3) / (L * 0.5))) end
  local re = r * 0.5                                               -- handle end corner
  arc(rb, rb, rb, math.pi, math.pi * 1.5, 3)                      -- bottom, head end
  arc(L - rb, rb, rb, math.pi * 1.5, math.pi * 2, 3)              -- bottom, handle end
  arc(L - re, topZ(L) - re, re, 0, math.pi / 2, 4)                -- top, handle end
  for i = 9, 1, -1 do add(r + (L - r - re) * i / 10, topZ(r + (L - r - re) * i / 10)) end
  arc(r, Hh - r, r, math.pi / 2, math.pi, 6)                      -- big round head corner
  return pts
end

-- Racket bag standing on a surface at height z0, centred at (x, y), its length along the
-- ground direction `dir` (head end at -dir). Drawn: the top/ends, then the side facing the
-- camera with a lighter lower panel and orange piping.
function View.drawRacketBag(cam, x, y, z0, G, dir)
  local prof = View.bagProfile(G)
  local u = dir
  local n = { x = -u.y, y = u.x }
  -- the side whose normal points toward the camera (camera sits behind the near baseline)
  local toCam = { x = -x, y = Court.LENGTH + cam.D - y }
  if n.x * toCam.x + n.y * toCam.y < 0 then n = { x = -n.x, y = -n.y } end
  local hw = G.width / 2
  local function P(p, side)
    local s = p.s - G.len / 2
    return proj(cam, x + u.x * s + n.x * hw * side, y + u.y * s + n.y * hw * side, z0 + p.z)
  end
  Draw.color(TC.bagTop)
  for i = 1, #prof do
    local p, q = prof[i], prof[i % #prof + 1]
    local ax, ay = P(p, 1)
    local bx, by = P(q, 1)
    local cx, cy = P(q, -1)
    local dx, dy = P(p, -1)
    love.graphics.polygon("fill", ax, ay, bx, by, cx, cy, dx, dy)
  end
  local side = {}
  for _, p in ipairs(prof) do
    local sx, sy = P(p, 1)
    side[#side + 1] = sx; side[#side + 1] = sy
  end
  Draw.color(TC.bag)
  local ok, tris = pcall(love.math.triangulate, side)
  if ok then for _, tri in ipairs(tris) do love.graphics.polygon("fill", tri) end end
Draw.color(shade(TC.bag, 0.6))  love.graphics.polygon("line", side)
  -- lighter lower panel under a curve rising toward the head end, orange piping on it
  local curve, poly = {}, {}
  local s0 = G.len * 0.6
  for i = 0, 10 do
    local t = i / 10
    local cx, cy = P({ s = s0 * (1 - t) + G.roundBottom * t, z = G.hHead * 0.45 * t * t }, 1)
    curve[#curve + 1] = cx; curve[#curve + 1] = cy
  end
  local bx, by = P({ s = G.roundBottom, z = 0 }, 1)
  for i = 1, #curve do poly[i] = curve[i] end
  poly[#poly + 1] = bx; poly[#poly + 1] = by
  Draw.color(TC.bagPanel)
  local ok2, tris2 = pcall(love.math.triangulate, poly)
  if ok2 then for _, tri in ipairs(tris2) do love.graphics.polygon("fill", tri) end end
  Draw.color(TC.bagTrim)
  love.graphics.line(curve)
end

-- Flat rectangle on the floor (centre x/y, half sizes hx/hy).
local function floorRect(cam, x, y, hx, hy)
  local pts = {}
  for _, c in ipairs({ { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } }) do
    local px, py = proj(cam, x + c[1] * hx, y + c[2] * hy, 0)
    pts[#pts + 1] = px; pts[#pts + 1] = py
  end
  return pts
end

-- Warm, bright gym: wood plank floor, beige panelled wall with white trim, big windows,
-- coloured mats, a plant, a gym ball and coloured dumbbells.
function View:drawGymRoom(s, items)
  local cam = self.cam
  local HD = Court.HALF_WIDTH_DOUBLES
  local L = Court.LENGTH
  local wy = GS.wallY
  local G = TL.gymLook
  -- wood floor: planks run across the screen, seams staggered row by row
  local a1, a2 = proj(cam, -HD - 8, wy, 0)
  local b1, b2 = proj(cam, HD + 8, wy, 0)
  local c1, c2 = proj(cam, HD + 8, L + 0.4, 0)
  local d1, d2 = proj(cam, -HD - 8, L + 0.4, 0)
  Draw.color(TC.gymFloor)
  love.graphics.polygon("fill", a1, a2, b1, b2, c1, c2, d1, d2)
  local row = 0
  for y = wy, L + 0.4, G.plank do
    row = row + 1
    if row % 2 == 0 then                    -- every other plank row a touch lighter
      Draw.color(TC.gymFloorLight)
      love.graphics.polygon("fill", floorRect(cam, 0, y + G.plank / 2, HD + 8, G.plank / 2))
    end
    Draw.color(TC.gymFloorLine)
    local p1, p2 = proj(cam, -HD - 8, y, 0)
    local q1, q2 = proj(cam, HD + 8, y, 0)
    love.graphics.line(p1, p2, q1, q2)
    for x = -HD - 8 + (row % 3) * G.plankLen / 3, HD + 8, G.plankLen do
      local s1, s2 = proj(cam, x, y, 0)
      local t1, t2 = proj(cam, x, y + G.plank, 0)
      love.graphics.line(s1, s2, t1, t2)
    end
  end
  -- back wall: beige panels, white crown trim, dark baseboard
  Draw.color(TC.wall)
  love.graphics.rectangle("fill", 0, 0, Layout.width, a2)
  Draw.color(TC.wallStripe)
  for x = -HD - 8, HD + 8, G.panel * 2 do
    local p1 = proj(cam, x, wy, 0)
    local p2 = proj(cam, x + G.panel, wy, 0)
    love.graphics.rectangle("fill", p1, 0, p2 - p1, a2)
  end
  local _, topY = proj(cam, 0, wy, G.wallTop)
  Draw.color(TC.wallTrim)
  love.graphics.rectangle("fill", 0, topY - 5, Layout.width, 5)
  Draw.color(TC.baseboard)
  love.graphics.rectangle("fill", 0, a2 - 4, Layout.width, 4)
  -- windows: light blue glass, white frames, a glare stripe
  for _, w in ipairs(G.windows) do
    local w1x, w1y = proj(cam, w.x1, wy, 2.4)
    local w2x, w2y = proj(cam, w.x2, wy, 1.3)
    Draw.color(TC.glass)
    love.graphics.rectangle("fill", w1x, w1y, w2x - w1x, w2y - w1y)
    love.graphics.setColor(1, 1, 1, 0.5)
    love.graphics.polygon("fill", w1x + 6, w2y, w1x + 12, w2y, w1x + 26, w1y, w1x + 20, w1y)
    Draw.color(TC.wallTrim)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", w1x, w1y, w2x - w1x, w2y - w1y)
    love.graphics.line((w1x + w2x) / 2, w1y, (w1x + w2x) / 2, w2y)
    love.graphics.setLineWidth(1)
  end
  -- mirror
  local m1x, m1y = proj(cam, GS.mirror.x1, wy, 2.2)
  local m2x, m2y = proj(cam, GS.mirror.x2, wy, 0.3)
  Draw.color(TC.mirror)
  love.graphics.rectangle("fill", m1x, m1y, m2x - m1x, m2y - m1y)
  love.graphics.setColor(1, 1, 1, 0.35)
  love.graphics.line(m1x + 6, m2y - 4, m1x + 20, m1y + 4)
  love.graphics.line(m1x + 12, m2y - 4, m1x + 26, m1y + 4)
  Draw.color(TC.wallTrim)
  love.graphics.rectangle("line", m1x, m1y, m2x - m1x, m2y - m1y)
  -- poster (trophy) and the speaker
  local px, py = proj(cam, G.poster.x, wy, 1.9)
  local k = Figure.scale(cam, 0, wy)
  local pw, ph = 0.5 * k / cam.hs * 0.6, 0.6 * k
  Draw.color(TC.wallTrim)
  love.graphics.rectangle("fill", px - pw / 2 - 1, py - 1, pw + 2, ph + 2)
  Draw.color(TC.poster)
  love.graphics.rectangle("fill", px - pw / 2, py, pw, ph)
  Draw.color(TC.trophy)
  love.graphics.rectangle("fill", px - 2, py + ph * 0.3, 4, ph * 0.35)
  love.graphics.rectangle("fill", px - 3, py + ph * 0.7, 6, 2)
  local sx, sy = proj(cam, GS.speaker.x, wy, 2.3)
  Draw.color(TC.dark)
  love.graphics.rectangle("fill", sx - 4, sy, 8, 11)
  Draw.color(TC.metal)
  love.graphics.circle("line", sx, sy + 7, 2.5)
  -- floor mats: red rug, rubber pad under the rack, chequered tiles at the skipping spot,
  -- blue stretching mat
  Draw.color(TC.rug)
  love.graphics.polygon("fill", floorRect(cam, G.rug.x, G.rug.y, G.rug.hx, G.rug.hy))
  Draw.color(TC.rugEdge)
  love.graphics.polygon("line", floorRect(cam, G.rug.x, G.rug.y, G.rug.hx - 0.08, G.rug.hy - 0.08))
  Draw.color(TC.rubber)
  love.graphics.polygon("fill", floorRect(cam, GS.rack.x, GS.rack.y + 0.3, 1.1, 0.7))
  local C0 = G.tiles
  for i = 0, C0.n - 1 do
    for j = 0, C0.n - 1 do
      Draw.color((i + j) % 2 == 0 and TC.tileA or TC.tileB)
      love.graphics.polygon("fill", floorRect(cam, C0.x + (i - C0.n / 2 + 0.5) * C0.size,
        C0.y + (j - C0.n / 2 + 0.5) * C0.size, C0.size / 2, C0.size / 2))
    end
  end
  local M = GS.mat
  Draw.color(TC.gymMat)
  love.graphics.polygon("fill", floorRect(cam, M.x, M.y, 1.1, 0.5))
  Draw.color(TC.gymMatEdge)
  love.graphics.polygon("line", floorRect(cam, M.x, M.y, 1.1, 0.5))
  -- loose dumbbells and a kettlebell on the floor
  for _, d in ipairs(G.floorWeights) do
    local x, y = proj(cam, d.x, d.y, 0)
    local kk = Figure.scale(cam, d.x, d.y)
    Draw.color(TC[d.color])
    if d.kettle then
      love.graphics.circle("fill", x, y - 0.12 * kk, 0.13 * kk)
      love.graphics.circle("line", x, y - 0.28 * kk, 0.07 * kk)
    else
      love.graphics.rectangle("fill", x - 0.16 * kk, y - 0.1 * kk, 0.08 * kk, 0.1 * kk)
      love.graphics.rectangle("fill", x + 0.08 * kk, y - 0.1 * kk, 0.08 * kk, 0.1 * kk)
      Draw.color(TC.metal)
      love.graphics.line(x - 0.08 * kk, y - 0.05 * kk, x + 0.08 * kk, y - 0.05 * kk)
    end
  end
  -- plant and gym ball (depth sorted with the athlete)
  local P = G.plant
  items[#items + 1] = { y = P.y, draw = function()
    box(cam, P.x, P.y, 0.2, 0.2, 0.45, TC.potTop, TC.pot)
    local x, y = proj(cam, P.x, P.y, 0.45)
    local kk = Figure.scale(cam, P.x, P.y)
    for i, l in ipairs({ { 0, -0.45, 0.22 }, { -0.16, -0.3, 0.17 }, { 0.17, -0.32, 0.17 }, { 0.02, -0.68, 0.15 } }) do
      Draw.color(i % 2 == 0 and TC.leafDark or TC.leaf)
      love.graphics.circle("fill", x + l[1] * kk, y + l[2] * kk, l[3] * kk)
    end
  end }
  local Bl = G.ball
  items[#items + 1] = { y = Bl.y, draw = function()
    local x, y = proj(cam, Bl.x, Bl.y, 0)
    local kk = Figure.scale(cam, Bl.x, Bl.y)
    local r = Bl.r * kk
    Draw.color(C.shadow)
    love.graphics.ellipse("fill", x, y, r, r * 0.3)
    Draw.color(TC.ball)
    love.graphics.circle("fill", x, y - r, r)
    love.graphics.setColor(1, 1, 1, 0.45)
    love.graphics.circle("fill", x - r * 0.35, y - r * 1.35, r * 0.25)
  end }

  -- treadmill: deck along x, console at the +x end
  local Tm = GS.treadmill
  items[#items + 1] = { y = Tm.y - 0.3, draw = function()
    box(cam, Tm.x, Tm.y, 0.95, 0.38, 0.18, TC.dark, shade(TC.metal, 0.5))
    local a = s.activity
    local run = a.name == "treadmill" and self.arrived
    love.graphics.setColor(1, 1, 1, 0.18)
    for i = 0, 5 do
      local u = (i / 6 + (run and -self.time * 0.9 or 0)) % 1
      local x1, y1 = proj(cam, Tm.x - 0.9 + u * 1.8, Tm.y - 0.3, 0.18)
      local x2, y2 = proj(cam, Tm.x - 0.9 + u * 1.8, Tm.y + 0.3, 0.18)
      love.graphics.line(x1, y1, x2, y2)
    end
    local px, py = proj(cam, Tm.x + 0.9, Tm.y, 0.18)
    local qx, qy = proj(cam, Tm.x + 0.9, Tm.y, 1.25)
    Draw.color(TC.metal)
    love.graphics.setLineWidth(2)
    love.graphics.line(px, py, qx, qy)
    love.graphics.setLineWidth(1)
    Draw.color(TC.dark)
    love.graphics.rectangle("fill", qx - 7, qy - 4, 12, 6)
    if run then Draw.color(C.good); love.graphics.rectangle("fill", qx - 5, qy - 3, 4, 2) end
  end }
  -- squat rack: two posts and a bar rest
  local R = GS.rack
  items[#items + 1] = { y = R.y, draw = function()
    Draw.color(TC.metal)
    for _, dx in ipairs({ -0.75, 0.75 }) do
      local x1, y1 = proj(cam, R.x + dx, R.y, 0)
      local x2, y2 = proj(cam, R.x + dx, R.y, 2.3)
      love.graphics.setLineWidth(2)
      love.graphics.line(x1, y1, x2, y2)
    end
    local x1, y1 = proj(cam, R.x - 0.75, R.y, 2.3)
    local x2, y2 = proj(cam, R.x + 0.75, R.y, 2.3)
    love.graphics.line(x1, y1, x2, y2)
    love.graphics.setLineWidth(1)
    if s.activity.name ~= "squat" or not self.arrived then      -- bar resting on the hooks
      local h1x, h1y = proj(cam, R.x - 0.9, R.y + 0.1, 1.4)
      local h2x = proj(cam, R.x + 0.9, R.y + 0.1, 1.4)
      love.graphics.setLineWidth(2)
      love.graphics.line(h1x, h1y, h2x, h1y)
      love.graphics.setLineWidth(1)
      Draw.color(TC.dark)
      love.graphics.rectangle("fill", h1x - 1, h1y - 5, 3, 10)
      love.graphics.rectangle("fill", h2x - 2, h1y - 5, 3, 10)
    end
  end }
  -- dumbbell rack
  local Db = GS.dumbbells
  items[#items + 1] = { y = Db.y, draw = function()
    box(cam, Db.x, Db.y, 0.5, 0.25, 0.6, shade(TC.metal, 0.7), shade(TC.metal, 0.45))
    Draw.color(TC.dark)
    for i = -2, 2 do
      local x, y = proj(cam, Db.x + i * 0.18, Db.y, 0.6)
      love.graphics.rectangle("fill", x - 2, y - 3, 4, 3)
    end
  end }
  -- weight bench: padded top on two metal legs (floor shows underneath)
  local Bn = GS.bench
  items[#items + 1] = { y = Bn.y - 0.2, draw = function()
    local B = TL.gymLook.bench
    for _, dx in ipairs({ -B.legX, B.legX }) do
      box(cam, Bn.x + dx, Bn.y, 0.04, B.hy, 0.04, TC.metal, shade(TC.metal, 0.6))          -- foot bar
      box(cam, Bn.x + dx, Bn.y, 0.035, 0.035, B.padZ, TC.metal, shade(TC.metal, 0.75))      -- post
    end
    box(cam, Bn.x, Bn.y, B.hx, B.hy * 0.7, B.padZ + 0.03, TC.metal, shade(TC.metal, 0.5), B.padZ)  -- frame
    box(cam, Bn.x, Bn.y, B.hx, B.hy, B.top, TC.pad, TC.padSide, B.padZ + 0.03)
    local x1, y1 = proj(cam, Bn.x - B.hx * 0.35, Bn.y - B.hy, B.top)
    local x2, y2 = proj(cam, Bn.x - B.hx * 0.35, Bn.y + B.hy, B.top)
    Draw.color(TC.padSide)
    love.graphics.line(x1, y1, x2, y2)                                                      -- seam
  end }
  -- water cooler
  local Co = GS.cooler
  items[#items + 1] = { y = Co.y, draw = function()
    box(cam, Co.x, Co.y, 0.22, 0.22, 0.95, shade(TC.metal, 0.9), shade(TC.metal, 0.6))
    local x, y = proj(cam, Co.x, Co.y, 0.95)
    Draw.color(TC.water, 0.8)
    love.graphics.rectangle("fill", x - 4, y - 12, 8, 12)
  end }
end

function View:draw(s)
  local cam = self.cam
  local items = {}
  if s.location == "gym" then self:drawGymRoom(s, items) else self:drawCourtRoom(s, items) end

  -- athlete
  local P = self:playerPose(s)
  P.headphones = s.music
  local head
  items[#items + 1] = { y = self.pos.y + 0.001, draw = function()
    if P.lying then
      local g = self:drawLying(self.pos, C.near)
      head = { x = g.head.x, y = g.head.y - g.head.r }
      return
    end
    local f = Figure.stance(cam, P.st, 1)
    if P.racketAngle then
      local r = Figure.racket(f.shoulderX, f.shoulderY, f.k, 1, nil, P.racketAngle)
      for k2, v in pairs(r) do f[k2] = v end
    end
    self:drawBody(f, P.lift, C.near, P)
    local liftPx = (P.lift or 0) * f.k
    head = { x = f.head.x, y = f.head.y - f.head.r - liftPx, cy = f.head.y - liftPx, r = f.head.r }
    if P.juggle then                       -- shuttle bouncing on the strings
      local ph = (self.time / 0.55) % 1
      local hgt = 4 * ph * (1 - ph) * 0.6 * f.k
      Draw.color(C.shuttle)
      love.graphics.circle("fill", f.headCX, f.headCY - liftPx - 2 - hgt, Figure.shuttleRadius(f.k))
    end
    if P.flash then
      love.graphics.setColor(1, 1, 1, 0.8)
      love.graphics.circle("fill", f.head.x + f.right * 10, f.head.y - 8, 6)
    end
    if P.notes or (s.music and self.time % 3 < 1.5) then
      for i = 0, 1 do
        local u = (self.time * 0.4 + i * 0.5) % 1
        Draw.color(TC.perfect, math.sin(u * math.pi))
        local nx, ny = f.head.x + 6 + i * 4 + u * 6, f.head.y - 4 - u * 18
        love.graphics.circle("fill", nx, ny, 1.5)
        love.graphics.line(nx + 1.5, ny, nx + 1.5, ny - 5)
      end
    end
  end }
  -- feeder (court only)
  if s.location == "court" then
    local F = self.feeder
    items[#items + 1] = { y = F.pos.y, draw = function()
      local st
      if F.walking then
        local front, back, hip, fl, bl = walkPose(F.travelled)
        st = { cog = F.pos, dir = F.dir, hipH = hip, front = front, back = back, lean = 0, frontLift = fl, backLift = bl, runKnees = true }
      else
        st = standing(F.pos, F.dir)
      end
      local a = s.activity
      local angle = math.rad(-40)
      if a.kind == "drill" and a.cur and not F.walking then
        -- underarm feed: the shuttle leaves the strings at ts = 0
        local ts = a.t - a.cur.t0
        if ts < 0.08 then angle = math.rad(mix(-70, 35, smooth(ts / 0.08)))
        else angle = math.rad(mix(35, -70, smooth((ts - 0.08) / 1.0))) end
      elseif F.flickT then
        -- scoop: crouch a little, racket down to the floor, then flick it up
        local t = F.flickT
        local down = smooth(t / FLICK.scoop)
        local up = smooth((t - FLICK.scoop) / 0.12)
        local back = smooth((t - FLICK.scoop - 0.12) / 0.3)
        angle = math.rad(mix(mix(mix(-40, -88, down), 50, up), -40, back))
        st.hipH = mix(STAND, 0.55, down * (1 - up))
      end
      st.racketAngle = angle
      local f = Figure.stance(cam, st, -1)
      -- the feeder is the coach: his cap and jacket, and he shouts the coaching lines
      self:drawBody(f, self:coachHop(s), TC.coachShirt, { cap = TC.coachCap })
      local talk = s.coachLine or s.feederBubble
      if talk then bubble(talk.text, f.head.x, f.head.y - f.head.r - 2 - self:coachHop(s) * f.k, talk.t * 3) end
    end }
  end
  -- gym: the coach stands by and watches him (facing him), shouting when you click
  if s.location == "gym" then
    local cp = GS.coach
    items[#items + 1] = { y = cp.y, draw = function()
      local dir = norm(self.pos.x - cp.x, self.pos.y - cp.y) or FACE_NET
      local st = standing(cp, dir)
      st.lean = 0.04 * math.sin(self.time * 0.8)                  -- shifts his weight a little
      local f = Figure.stance(cam, st, 1)
      self:drawBody(f, self:coachHop(s), TC.coachShirt,
        { cap = TC.coachCap, racket = false, arms = { { angle = math.rad(-30), reach = 0.6, prop = "clipboard" } } })
      if s.coachLine then
        bubble(s.coachLine.text, f.head.x, f.head.y - f.head.r - 2 - self:coachHop(s) * f.k, s.coachLine.t * 3)
      end
    end }
  end
  -- shuttles flicked toward the basket
  if s.location == "court" then
    local B = CS.basket
    for _, fl in ipairs(self.flying) do
      local u = fl.t / FLICK.flight
      local p = { pos = lerpP(fl.from, B, u), h = mix(0.1, 0.5, u) + 4 * 1.0 * u * (1 - u) }
      items[#items + 1] = { y = p.pos.y + 0.01, draw = function() CourtView.drawShuttle(cam, p) end }
    end
  end
  -- drill shuttle
  local sh = self.pose and self.pose.shuttle
  if sh then
    CourtView.drawShuttleShadow(cam, sh)
    items[#items + 1] = { y = sh.pos.y + 0.01, draw = function() CourtView.drawShuttle(cam, sh) end }
  end
  table.sort(items, function(p, q) return p.y < q.y end)
  for _, it in ipairs(items) do it.draw() end

  -- working harder (coach clicks sped him up): see View:drawWorkingHard
  if head and head.r and (s.pace or 1) > 1.05 then self:drawWorkingHard(head) end
  -- rep popups rising from his head, his speech bubble
  if head then
    for _, p in ipairs(self.popups) do
      local dur = p.big and 2.6 or 1.4
      local u = p.t / dur
      local font = p.big and Assets.fonts.normal or Assets.fonts.small
      local alpha = 1 - smooth((u - 0.6) / 0.4)
      local col = { p.color[1], p.color[2], p.color[3], alpha }
      Draw.text(p.text, head.x - 80, head.y - 14 - u * (p.big and 30 or 22), col, font, "center", 160)
    end
    if s.bubble then bubble(s.bubble.text, head.x, head.y - 2, s.bubble.t * 3) end
  end
end

return View
