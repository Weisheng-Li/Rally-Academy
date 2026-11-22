-- Perspective projection from court meters to screen pixels.
-- Configured by on-screen measurements (see config/layout.lua camera) and solved
-- for a pinhole camera standing behind the near baseline.
local Court = require("src.core.court")

local Camera = {}
Camera.__index = Camera

local COURT_LEN = Court.LENGTH * 2
local COURT_W = Court.HALF_WIDTH_DOUBLES * 2

function Camera.new(cfg)
  local self = setmetatable({}, Camera)
  local r = cfg.nearWidth / cfg.farWidth
  self.D = COURT_LEN / (r - 1)                       -- camera ground distance to near baseline
  self.f = cfg.nearWidth * self.D / COURT_W          -- focal length (px)
  self.H = (cfg.nearY - cfg.farY) / (self.f * (1 / self.D - 1 / (self.D + COURT_LEN)))
  self.horizon = cfg.nearY - self.f * self.H / self.D
  self.cx = cfg.centerX
  self.hs = cfg.heightScale
  return self
end

function Camera:depth(y) return self.D + (Court.LENGTH - y) end

-- World (x, y, height) -> screen x, y and pixels-per-meter at that depth.
function Camera:project(x, y, h)
  local s = self.f / self:depth(y)
  return self.cx + x * s, self.horizon + (self.H - (h or 0) * self.hs) * s, s
end

-- Screen point -> ground point (height 0), or nil above the horizon.
function Camera:unproject(sx, sy)
  local dy = sy - self.horizon
  if dy <= 0 then return nil end
  local z = self.f * self.H / dy
  return { x = (sx - self.cx) * z / self.f, y = Court.LENGTH + self.D - z }
end

-- Screen vertices of a circle lying on the ground.
function Camera:groundCircle(cx, cy, r, segments)
  segments = segments or 32
  local pts = {}
  for i = 0, segments - 1 do
    local a = i / segments * math.pi * 2
    local sx, sy = self:project(cx + math.cos(a) * r, cy + math.sin(a) * r, 0)
    pts[#pts + 1] = sx
    pts[#pts + 1] = sy
  end
  return pts
end

return Camera
