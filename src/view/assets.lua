-- Loads fonts/images once. Swap the default font for a pixel font in assets/fonts later.
local Layout = require("src.config.layout")

local Assets = {}

local function font(size)
  local f = love.graphics.newFont(size, "mono")
  f:setFilter("nearest", "nearest")
  return f
end

function Assets.load()
  Assets.fonts = {
    small = font(Layout.fonts.small),
    normal = font(Layout.fonts.normal),
    big = font(Layout.fonts.big),
    title = font(Layout.fonts.title),
  }
end

return Assets
