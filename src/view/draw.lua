-- Small drawing helpers shared by views.
local Layout = require("src.config.layout")
local Assets = require("src.view.assets")

local Draw = {}
local C = Layout.colors

function Draw.color(c, alpha)
  love.graphics.setColor(c[1], c[2], c[3], alpha or c[4] or 1)
end

-- Text with a 1px dark outline so it reads on any background.
function Draw.text(str, x, y, color, font, align, width)
  font = font or Assets.fonts.normal
  love.graphics.setFont(font)
  x, y = math.floor(x), math.floor(y)
  love.graphics.setColor(0, 0, 0, 0.85)
  for _, o in ipairs({ { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }) do
    if align then
      love.graphics.printf(str, x + o[1], y + o[2], width, align)
    else
      love.graphics.print(str, x + o[1], y + o[2])
    end
  end
  Draw.color(color or C.text)
  if align then love.graphics.printf(str, x, y, width, align) else love.graphics.print(str, x, y) end
end

function Draw.panel(x, y, w, h)
  x, y, w, h = math.floor(x), math.floor(y), math.floor(w), math.floor(h)
  Draw.color(C.panel)
  love.graphics.rectangle("fill", x, y, w, h)
  Draw.color(C.panelEdge, 0.8)
  love.graphics.setLineWidth(1)
  love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1)
end

function Draw.successColor(p)
  if p >= 0.85 then return C.good end
  if p >= 0.70 then return C.ok end
  return C.bad
end

-- Dashed polyline through a flat {x1,y1,x2,y2,...} list (closed if requested).
function Draw.dashed(pts, closed, on)
  on = on or 2
  local n = #pts / 2
  local last = closed and n or n - 1
  for i = 1, last do
    if i % 2 == 1 then
      local j = (i % n) + 1
      love.graphics.line(pts[i * 2 - 1], pts[i * 2], pts[j * 2 - 1], pts[j * 2])
    end
  end
end

return Draw
