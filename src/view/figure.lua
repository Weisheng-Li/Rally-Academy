-- Sprite geometry (pixels) for athletes, rackets and the shuttle, from core/body.lua
-- numbers. No drawing and no love.* calls, so tests/ can check the sprites stay in
-- proportion to the model.
--
-- All sprite sizes use one scale per depth: k = pixels per meter on the camera's
-- squashed vertical (cam.hs * s), so body, racket and shuttle stay in proportion.
local Body = require("src.core.body")

local Figure = {}

Figure.MIN_SHUTTLE_RADIUS = 1.5   -- px, so the shuttle stays visible far away

-- Pixels per meter for sprites at a ground point.
function Figure.scale(cam, x, y)
  local _, _, s = cam:project(x, y, 0)
  return cam.hs * s
end

-- Static athlete sprite: fixed upright body, racket attached at the right shoulder,
-- rotated in 2D to point at `h` (the shuttle height it is playing), or ready if nil.
function Figure.athlete(cam, a, h)
  local fx, fy = cam:project(a.pos.x, a.pos.y, 0)
  local k = Figure.scale(cam, a.pos.x, a.pos.y)
  local bodyH, bodyW = Body.HEIGHT * k, Body.WIDTH * k
  local right = a.side                    -- near player's right is screen +x, far player's is -x
  local sx, sy = fx + right * bodyW / 2, fy - Body.SHOULDER_HEIGHT * k

  local f = Figure.racket(sx, sy, k, right, h)
  f.k, f.feetX, f.feetY, f.bodyH, f.bodyW = k, fx, fy, bodyH, bodyW
  return f
end

-- Racket from a shoulder point, rotated in 2D to point at height h (ready angle if nil),
-- or at an explicit `angle` (rad above horizontal) when given.
function Figure.racket(sx, sy, k, right, h, angle)
  local ang = angle or (h and Body.racketAngle(h)) or math.rad(Body.READY_ANGLE)
  local ux, uy = right * math.cos(ang), -math.sin(ang)
  local L = Body.RACKET_LENGTH * k
  local headLen = Body.RACKET_HEAD * k
  local tx, ty = sx + ux * L, sy + uy * L
  local hx, hy = tx - ux * headLen, ty - uy * headLen
  return {
    shoulderX = sx, shoulderY = sy,
    tipX = tx, tipY = ty, headStartX = hx, headStartY = hy,
    headCX = (tx + hx) / 2, headCY = (ty + hy) / 2, headAngle = math.atan2(uy, ux),
    headLen = headLen, headWidth = Body.RACKET_HEAD_WIDTH * k, racketLen = L,
  }
end

Figure.THIGH = Body.HIP_HEIGHT / 2   -- m; thigh = shin, so a straight leg = HIP_HEIGHT
Figure.SHIN = Body.HIP_HEIGHT / 2
Figure.TRAIL_CURL = 55              -- deg, most a lifted back leg bends at the knee (foot stays low)
Figure.HIP_HALF = 0.09              -- m, each leg hangs this far either side of the centre

-- Two-bone leg from hip (hx,hy) toward foot target (fx,fy), all in pixels, segment lengths
-- t and s. pref = (px,py): the knee bends to the side this vector points to.
-- Out of reach -> the foot leaves the ground: the thigh points at the target and the shin
-- curls up behind it (trailing leg), more the further out of reach it is.
-- flat (0..1): how much of the knee bend points into/out of the screen; that part is not
-- drawn sideways (the bent leg is seen end-on and just looks shorter).
local function leg(hx, hy, fx, fy, t, s, px, py, flat)
  local dx, dy = fx - hx, fy - hy
  local d = math.sqrt(dx * dx + dy * dy)
  local max = t + s
  if d < 1e-6 then return { x = hx, y = hy + t }, { x = hx, y = hy + t + s }, true end
  local ux, uy = dx / d, dy / d
  if d <= max then
    local a = (t * t - s * s + d * d) / (2 * d)
    local h = math.sqrt(math.max(0, t * t - a * a)) * (1 - (flat or 0))
    local mx, my = hx + ux * a, hy + uy * a
    local nx, ny = -uy, ux
    if nx * px + ny * py < 0 then nx, ny = -nx, -ny end
    return { x = mx + nx * h, y = my + ny * h }, { x = fx, y = fy }, true
  end
  local knee = { x = hx + ux * t, y = hy + uy * t }
  local curl = math.min(1, (d - max) / (0.5 * max)) * math.rad(Figure.TRAIL_CURL)
  local c, sn = math.cos(curl), math.sin(curl)
  -- rotate the thigh direction by +-curl, whichever lifts the foot (smaller screen y)
  local ax, ay = ux * c - uy * sn, ux * sn + uy * c
  local bx, by = ux * c + uy * sn, -ux * sn + uy * c
  if by < ay then ax, ay = bx, by end
  return knee, { x = knee.x + ax * s, y = knee.y + ay * s }, false
end
Figure.leg = leg

-- On-screen step along dir per sprite metre (in units of k): full length sideways,
-- foreshortened when the direction goes into or out of the screen.
local function screenDir(cam, cog, dir)
  local gx, gy, s = cam:project(cog.x, cog.y, 0)
  local px, py = cam:project(cog.x + dir.x * 0.1, cog.y + dir.y * 0.1, 0)
  return (px - gx) / (0.1 * s), (py - gy) / (0.1 * s)
end

-- Back-foot offset (negative, sprite m along dir) that puts the back foot on the floor with
-- the leg fully straight: |(ex*b, ey*b + hipH)| = leg length.
function Figure.straightBack(cam, cog, dir, hipH)
  local ex, ey = screenDir(cam, cog, dir)
  local L = Body.HIP_HEIGHT * 0.999
  local a, b, c = ex * ex + ey * ey, 2 * ey * hipH, hipH * hipH - L * L
  if a < 1e-9 or c > 0 then return 0 end
  return (-b - math.sqrt(b * b - 4 * a * c)) / (2 * a)
end

-- Posed athlete (prototype for the balance model). Drawn in sprite scale (k px per m, the
-- same as Figure.athlete) so legs and torso keep fixed sizes whatever the pose. st = {
--   cog   = {x,y}  ground point under the hips
--   dir   = {x,y}  unit lunge/run direction on the court
--   hipH  hip height (m): Body.HIP_HEIGHT standing, lower in a lunge
--   front, back    feet along dir from the hips (m, sprite scale; back is negative)
--   lean  upper-body tilt toward dir (rad, Body.leanFor)
--   h     racket target height (nil = ready)
--   frontLift, backLift  foot heights off the floor (m, running swing foot)
--   runKnees  true = both knees bend forward (running)
--   racketAngle  explicit racket angle (rad, overrides h; serve swing) }
function Figure.stance(cam, st, side)
  local k = Figure.scale(cam, st.cog.x, st.cog.y)
  local bodyW = Body.WIDTH * k
  local gx, gy = cam:project(st.cog.x, st.cog.y, 0)
  local ex, ey = screenDir(cam, st.cog, st.dir)
  local hipX, hipY = gx, gy - st.hipH * k

  -- legs: fixed thigh + shin; front knee bends forward, back knee toward the floor
  local T, S = Figure.THIGH * k, Figure.SHIN * k
  -- the front foot carries the weight and stays on the floor: shorten the stride until the
  -- leg reaches it (a longer reach has to come from the upper-body lean instead)
  local front = st.front
  local function dist(fr)
    local dx, dy = ex * fr * k, ey * fr * k + st.hipH * k
    return math.sqrt(dx * dx + dy * dy)
  end
  if dist(front) > (T + S) * 0.97 then
    local lo, hi = 0, front
    for _ = 1, 30 do
      local mid = (lo + hi) / 2
      if dist(mid) > (T + S) * 0.97 then hi = mid else lo = mid end
    end
    front = lo
  end
  -- each leg hangs from its own hip, either side of the centre (across dir). Seen from behind
  -- (moving forward/back) this keeps the two legs apart instead of on one line.
  local qx, qy = screenDir(cam, st.cog, { x = -st.dir.y, y = st.dir.x })
  local hx1, hy1 = hipX + qx * Figure.HIP_HALF * k, hipY + qy * Figure.HIP_HALF * k
  local hx2, hy2 = hipX - qx * Figure.HIP_HALF * k, hipY - qy * Figure.HIP_HALF * k
  local ffx = hx1 + ex * front * k
  local ffy = gy + qy * Figure.HIP_HALF * k + ey * front * k - (st.frontLift or 0) * k
  local bfx = hx2 + ex * st.back * k
  local bfy = gy - qy * Figure.HIP_HALF * k + ey * st.back * k - (st.backLift or 0) * k
  -- running: knees bend forward, and when the move is mostly into/out of the screen they
  -- also splay a little outward so a folded (heel-kick) leg reads from behind.
  -- lunging/standing: front knee forward, back knee toward the floor
  -- A knee bending toward/away from the camera (moves into/out of the screen) is hidden
  -- behind the leg: the leg just looks a bit shorter. `flat` scales the sideways knee bend
  -- down by how much the move points in/out of the screen (0 sideways .. 1 straight in/out).
  local inOut = 1 - math.min(1, math.abs(ex))
  local fpx, fpy = ex, ey - 0.6
  local bpx, bpy = -ex, 0.6
  local flat1, flat2 = inOut, inOut
  if st.runKnees then
    -- only the swinging (lifted) leg folds out to the side so the heel kick reads from
    -- behind; the planted one stays straight under the body
    local l1 = math.min(1, (st.frontLift or 0) / 0.08)
    local l2 = math.min(1, (st.backLift or 0) / 0.08)
    fpx, fpy = ex + qx * inOut * l1 * 2, ey - 0.6 + qy * inOut * l1 * 2
    bpx, bpy = ex - qx * inOut * l2 * 2, ey - 0.6 - qy * inOut * l2 * 2
    flat1, flat2 = inOut * (1 - l1), inOut * (1 - l2)
  end
  local kneeF, footF = leg(hx1, hy1, ffx, ffy, T, S, fpx, fpy, flat1)
  local kneeB, footB, planted = leg(hx2, hy2, bfx, bfy, T, S, bpx, bpy, flat2)

  -- torso: fixed length, tilted toward the sideways part of dir (into-screen lean shortens it)
  local L = Body.TORSO_LENGTH * k
  local lean = st.lean or 0
  local tx, ty = math.sin(lean) * ex * L, -math.cos(lean) * L
  local tl = math.sqrt(tx * tx + ty * ty)
  local ux, uy = tx / tl, ty / tl                 -- hip -> shoulder
  local nx, ny = -uy, ux                          -- across the torso (screen right when upright)
  local shX, shY = hipX + tx, hipY + ty
  local hw = bodyW / 2
  local headR = (Body.HEIGHT - Body.SHOULDER_HEIGHT) * k / 2
  local right = side
  local f = Figure.racket(shX + nx * hw * right, shY + ny * hw * right, k, right, st.h, st.racketAngle)
  f.k, f.bodyW, f.bodyH = k, bodyW, Body.HEIGHT * k
  f.groundX, f.groundY = gx, gy
  f.hipX, f.hipY = hipX, hipY
  f.shoulderMidX, f.shoulderMidY = shX, shY
  f.torsoLen = tl
  f.torso = { hipX - nx * hw, hipY - ny * hw, hipX + nx * hw, hipY + ny * hw,
              shX + nx * hw, shY + ny * hw, shX - nx * hw, shY - ny * hw }
  f.head = { x = shX + ux * headR, y = shY + uy * headR, r = headR }
  f.legs = { { hx1, hy1, kneeF.x, kneeF.y, footF.x, footF.y },
             { hx2, hy2, kneeB.x, kneeB.y, footB.x, footB.y } }
  f.backPlanted = planted
  f.legW = math.max(1, bodyW * 0.38)
  return f
end

function Figure.shuttleRadius(k) return math.max(Figure.MIN_SHUTTLE_RADIUS, Body.SHUTTLE_DIAMETER / 2 * k) end

function Figure.shuttle(cam, sh)
  local x, y = cam:project(sh.pos.x, sh.pos.y, sh.h)
  return { x = x, y = y, r = Figure.shuttleRadius(Figure.scale(cam, sh.pos.x, sh.pos.y)) }
end

return Figure
