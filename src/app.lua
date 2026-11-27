-- App shell: virtual-resolution canvas, integer scaling, scene switching, dev hooks.
-- This and src/view, src/scenes are the only places that call love.*.
local Layout = require("src.config.layout")
local Assets = require("src.view.assets")
local Dev = require("src.dev")

local App = {}
App.__index = App

function App.new(args)
  local self = setmetatable({}, App)
  self.dev = Dev.parse(args)
  self.canvas = love.graphics.newCanvas(Layout.width, Layout.height)
  self.canvas:setFilter("nearest", "nearest")
  self.mouse = { x = 0, y = 0 }
  self.time = 0
  Assets.load()
  self:resize(love.graphics.getDimensions())
  if self.dev.demo then
    self:switch("demo_" .. self.dev.demo)
  elseif self.dev.profile then
    self:switch("match", { you = self.dev.profile, opp = self.dev.opp, seed = self.dev.seed })
  else
    self:switch("title")
  end
  return self
end

function App:switch(name, params)
  local Scene = require("src.scenes." .. name)
  self.sceneName = name
  self.scene = Scene.new(self, params or {})
end

function App:resize(w, h)
  self.scale = math.max(1, math.floor(math.min(w / Layout.width, h / Layout.height)))
  self.ox = math.floor((w - Layout.width * self.scale) / 2)
  self.oy = math.floor((h - Layout.height * self.scale) / 2)
end

function App:toVirtual(x, y)
  return (x - self.ox) / self.scale, (y - self.oy) / self.scale
end

function App:update(dt)
  dt = math.min(dt, 1 / 20)
  if self.dev.gifAt then dt = 1 / (self.dev.gifFps or 20) end   -- fixed step: one gif frame per frame
  self.time = self.time + dt
  if self.dev.mouse then self.mouse.x, self.mouse.y = self.dev.mouse.x, self.dev.mouse.y end
  if self.scene.update then self.scene:update(dt) end

  local ready = not self.scene.readyForShot or self.scene:readyForShot()
  if self.dev.anytime then ready = true end
  if self.dev.skidShot then
    local rally = self.scene.match and self.scene.match.rally
    ready = rally and rally.skid and rally.skid.t >= self.dev.skidShot or false
  end
  if self.dev.shotAt and self.time >= self.dev.shotAt and ready and not self.shotTaken then
    self.shotTaken = true
    love.graphics.captureScreenshot(function(img)
      love.filesystem.createDirectory("screenshots")
      img:encode("png", "screenshots/shot.png")
      love.event.quit()
    end)
  end
end

function App:draw()
  love.graphics.setCanvas({ self.canvas, stencil = true })
  love.graphics.clear(Layout.colors.bg)
  love.graphics.setColor(1, 1, 1)
  self.scene:draw()
  love.graphics.setCanvas()
  if self.dev.gifAt then self:_recordGif() end

  love.graphics.clear(0, 0, 0)
  love.graphics.setColor(1, 1, 1)
  love.graphics.draw(self.canvas, self.ox, self.oy, 0, self.scale, self.scale)
end

-- Dev: grab the canvas every frame from --gif SECONDS for --giflen SECONDS, then write
-- screenshots/shot.gif (src/gif.lua) and quit.
function App:_recordGif()
  local d = self.dev
  if self.time < d.gifAt then return end
  local ffi = require("ffi")
  self.gifFrames = self.gifFrames or {}
  local img = self.canvas:newImageData()
  local frames = self.gifFrames
  frames[#frames + 1] = { img = img, p = ffi.cast("uint8_t*", img:getFFIPointer()) }
  local fps = d.gifFps or 20
  if #frames >= math.floor((d.gifLen or 4) * fps + 0.5) then
    local ptrs = {}
    for i, f in ipairs(frames) do ptrs[i] = f.p end
    local data = require("src.gif").encode(ptrs, { w = Layout.width, h = Layout.height,
      scale = d.gifScale or 2, delay = math.floor(100 / fps + 0.5) })
    love.filesystem.createDirectory("screenshots")
    love.filesystem.write("screenshots/shot.gif", data)
    love.event.quit()
  end
end

function App:mousemoved(x, y)
  self.mouse.x, self.mouse.y = self:toVirtual(x, y)
end

function App:mousepressed(x, y, button)
  local vx, vy = self:toVirtual(x, y)
  if self.scene.mousepressed then self.scene:mousepressed(vx, vy, button) end
end

function App:keypressed(key)
  if key == "f11" then love.window.setFullscreen(not love.window.getFullscreen()) return end
  if self.scene.keypressed then self.scene:keypressed(key) end
end

return App
