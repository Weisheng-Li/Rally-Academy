-- Footwork animation driven by the athlete's state (src/view/animator.lua; no drawing).
local Animator = require("src.view.animator")
local Athlete = require("src.core.athlete")
local Camera = require("src.view.camera")
local Layout = require("src.config.layout")
local A = require("src.config.animation")
local Body = require("src.core.body")

local cam = Camera.new(Layout.camera)

local function athlete()
  local s = {}
  for _, k in ipairs({ "clear", "lift", "drop", "net", "drive", "smash", "power", "speed", "legs", "reach" }) do s[k] = 5 end
  local a = Athlete.new({ name = "T", stats = s }, 1)
  a.pos = { x = 0, y = 3.6 }
  return a
end

-- run the athlete and its animator together until it arrives (or `time` runs out)
local function run(a, anim, time)
  local t = 0
  while t < time do
    a:update(1 / 60); anim:update(a, 1 / 60, cam); t = t + 1 / 60
  end
end

return {
  ["gait: shuffle sideways, run forward/back and on long moves"] = function(t)
    local from = { x = 0, y = 3.6 }
    t:ok(Animator.gaitFor(cam, from, 1, 0, 1.0) == "shuffle", "short sideways = shuffle")
    t:ok(Animator.gaitFor(cam, from, 0, -1, 1.0) == "run", "short forward = run")
    t:ok(Animator.gaitFor(cam, from, 0, 1, 1.0) == "run", "short back = run")
    t:ok(Animator.gaitFor(cam, from, 0.7, -0.7, A.run.from + 0.5) == "run", "long diagonal = run")
  end,

  ["a stretched contact ends in an overreach lunge, held until the hit"] = function(t)
    local a, anim = athlete(), Animator.new(1)
    anim:update(a, 1 / 60, cam)
    a:moveTo({ x = 1.5, y = 3.6 }, 0)
    a.pose = { state = "stretched", stretch = 1, h = 0.8 }
    run(a, anim, 0.2)
    t:ok(anim.moving and anim.lunge < 1, "still moving, not fully lunged yet")
    run(a, anim, 2.0)
    t:near(anim.lunge, 1, 1e-9, "fully lunged on arrival")
    t:ok(anim.kind == "overreach", "stretched = overreach")
    local st = anim:stance(a, cam)
    t:ok(st.lean > 0.2, "upper body tilted")
  end,

  ["an on-time contact after a real move is a controlled lunge"] = function(t)
    local a, anim = athlete(), Animator.new(1)
    anim:update(a, 1 / 60, cam)
    a:moveTo({ x = 1.2, y = 3.6 }, 0)
    a.pose = { state = "ontime", stretch = 0, h = 1.2 }
    run(a, anim, 2.0)
    t:ok(anim.kind == "controlled", "controlled")
    t:ok(anim:stance(a, cam).lean < 0.1, "upright")
  end,

  ["after the hit the lunge blends back to standing over the recovery pause"] = function(t)
    local a, anim = athlete(), Animator.new(1)
    anim:update(a, 1 / 60, cam)
    a:moveTo({ x = 1.5, y = 3.6 }, 0)
    a.pose = { state = "stretched", stretch = 1 }
    run(a, anim, 2.0)
    a.pose = nil
    a:moveTo({ x = 0, y = 3.6 }, 0.6)        -- recovery step after a 0.6 s pause
    run(a, anim, 0.3)
    t:ok(anim.lunge > 0 and anim.lunge < 1, "partly recovered mid-pause")
    run(a, anim, 0.4)
    t:near(anim.lunge, 0, 1e-9, "standing again when the pause ends")
  end,

  ["serve: racket hangs back, swings underarm into the contact, then follows through"] = function(t)
    local Shots = require("src.core.shots")
    local contact = Shots.serveGeometry({ x = 0, y = 0 }, 1).angle
    t:near(Animator.serveRacket(0), math.rad(A.serve.holdAngle), 1e-9, "holding: racket back")
    t:near(Animator.serveRacket(1), contact, 1e-9, "contact angle at the end of the toss")
    local a1, a2 = Animator.serveRacket(0.8), Animator.serveRacket(0.95)
    t:ok(a1 < a2 and a2 < contact, "swinging up toward the contact")
    t:near(Animator.serveRacket(nil, A.serve.follow), math.rad(A.serve.followAngle), 1e-9, "follow-through")
    t:near(Animator.serveRacket(nil, A.serve.follow + A.serve.settle), math.rad(Body.READY_ANGLE), 1e-9, "back to ready")

    local a, anim = athlete(), Animator.new(1)
    a.pose = { state = "serve", toss = 0 }
    anim:update(a, 1 / 60, cam)
    local st = anim:stance(a, cam)
    t:near(anim.lunge, 0, 1e-12, "no lunge while serving")
    t:near(st.racketAngle, math.rad(A.serve.holdAngle), 1e-9, "racket back before the toss")
    a.pose = nil                               -- contact
    anim:update(a, 1 / 60, cam)
    t:ok(anim:stance(a, cam).racketAngle ~= nil, "follow-through after contact")
    run(a, anim, A.serve.follow + A.serve.settle + 0.1)
    t:ok(anim:stance(a, cam).racketAngle == nil, "serve animation over")
  end,
}
