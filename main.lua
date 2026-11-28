-- LÖVE entry point. Kept intentionally thin: everything is forwarded to src/app.lua,
-- which is the only place that knows about window scaling and scene switching.
local App = require("src.app")

local app

function love.load(args)
  love.graphics.setDefaultFilter("nearest", "nearest")
  app = App.new(args or {})
end

function love.update(dt) app:update(dt) end
function love.draw() app:draw() end
function love.resize(w, h) app:resize(w, h) end
function love.mousemoved(x, y) app:mousemoved(x, y) end
function love.mousepressed(x, y, button) app:mousepressed(x, y, button) end
function love.mousereleased(x, y, button) app:mousereleased(x, y, button) end
function love.keypressed(key) app:keypressed(key) end
function love.textinput(t) app:textinput(t) end
