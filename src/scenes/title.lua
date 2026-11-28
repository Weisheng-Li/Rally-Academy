-- Title screen: the academy hall (src/view/hall_view.lua) with the centre court empty and
-- lit, waiting for a new athlete. Only for starting a career: with a career running the
-- game opens on the hub, and the hub's Menu button brings you back here.
--   New career -> name your athlete -> hub.  With a career: Back to academy, or New career
--   (replaces it, after a second click).
--   Dev keys: M quick match, D footwork demo, T training demo, Esc quit.
local Layout = require("src.config.layout")
local Draw = require("src.view.draw")
local Assets = require("src.view.assets")
local Hall = require("src.view.hall_view")
local Career = require("src.core.career")

local Title = {}
Title.__index = Title

local C = Layout.colors
local HL = Layout.hall

function Title.new(app, params)
  local self = setmetatable({ app = app }, Title)
  local seed = app.dev.seed or os.time()
  local rng = love.math.newRandomGenerator(seed)
  self.rng = function() return rng:random() end
  self.hall = Hall.new(self.rng)
  self.hall:update(0)
  self.naming = params.naming and "" or nil     -- the name being typed (nil = dialog closed)
  local dev = app.dev.open and app.dev.open:match("^naming:?(.*)")   -- dev: --open naming[:Name]
  if dev then self.naming = dev end
  return self
end

local function inside(x, y, rx, ry, rw, rh) return x >= rx and x <= rx + rw and y >= ry and y <= ry + rh end

function Title:_backRect()
  local x, y, w, h = self.hall:buttonRect()
  return x, y + h + 6, w, h
end

function Title:update(dt)
  self.hall:update(dt)
  local mx, my = self.app.mouse.x, self.app.mouse.y
  self.hoverNew = not self.naming and inside(mx, my, self.hall:buttonRect())
  self.hoverBack = not self.naming and self.app.career and inside(mx, my, self:_backRect())
  if self.naming then
    local R = self:_namingRects()
    self.hoverStart = self.naming ~= "" and inside(mx, my, R.start.x, R.start.y, R.start.w, R.start.h)
    self.hoverCancel = inside(mx, my, R.cancel.x, R.cancel.y, R.cancel.w, R.cancel.h)
  end
end

function Title:_newCareer()
  if self.app.career and not self.confirmReplace then
    self.confirmReplace = true
    return
  end
  self.naming = ""
end

-- Name dialog geometry (layout.hall.naming): box, input field, Start and Cancel buttons.
function Title:_namingRects()
  local N = HL.naming
  local x = (Layout.width - N.w) / 2
  local bx = Layout.width / 2 - N.buttonW - N.buttonGap / 2
  return {
    box = { x = x, y = N.y, w = N.w, h = N.h },
    field = { x = (Layout.width - N.fieldW) / 2, y = N.y + N.fieldY, w = N.fieldW, h = N.fieldH },
    start = { x = bx, y = N.y + N.buttonY, w = N.buttonW, h = N.buttonH },
    cancel = { x = bx + N.buttonW + N.buttonGap, y = N.y + N.buttonY, w = N.buttonW, h = N.buttonH },
  }
end

function Title:_cancelNaming() self.naming = nil; self.confirmReplace = false end

function Title:_start()
  local name = self.naming:match("^%s*(.-)%s*$")
  if name == "" then return end
  self.app.career = Career.new({ rng = self.rng, name = name })
  self.app:switch("hub")
end

local function button(x, y, w, h, label, hot, glow, dim)
  Draw.color(C.panel)
  love.graphics.rectangle("fill", x, y, w, h)
  local col = hot and C.text or HL.colors.post
  Draw.color(col, glow)
  love.graphics.setLineWidth(1)
  love.graphics.rectangle("line", math.floor(x) + 0.5, math.floor(y) + 0.5, w - 1, h - 1)
  Draw.text(label, x, y + (h - 10) / 2, dim and C.textDim or (hot and C.text or HL.colors.post), Assets.fonts.normal, "center", w)
end

function Title:draw()
  self.hall:draw()
  local W = Layout.width
  Draw.text("RALLY ACADEMY", 0, HL.titleY, C.text, Assets.fonts.title, "center", W)

  if self.naming then
    local R = self:_namingRects()
    local b, f = R.box, R.field
    local font = Assets.fonts.normal
    love.graphics.setColor(0, 0, 0, 0.45)
    love.graphics.rectangle("fill", 0, 0, W, Layout.height)
    Draw.panel(b.x, b.y, b.w, b.h)
    Draw.text("NEW ATHLETE", b.x, b.y + 12, C.text, font, "center", b.w)
    -- input field: placeholder when empty, the blinking caret drawn after the name (so the
    -- centred name never shifts)
    Draw.color(HL.colors.wall)
    love.graphics.rectangle("fill", f.x, f.y, f.w, f.h)
    Draw.color(HL.colors.post, 0.8)
    love.graphics.rectangle("line", f.x + 0.5, f.y + 0.5, f.w - 1, f.h - 1)
    local ty = f.y + (f.h - 10) / 2
    local placeholder = "Enter a name"
    local cx
    if self.naming == "" then
      Draw.text(placeholder, f.x, ty, C.textDim, font, "center", f.w)
      cx = f.x + f.w / 2 - font:getWidth(placeholder) / 2 - 3      -- caret before the placeholder
    else
      Draw.text(self.naming, f.x, ty, C.text, font, "center", f.w)
      cx = f.x + f.w / 2 + font:getWidth(self.naming) / 2 + 1
    end
    if math.floor(self.hall.time * 2) % 2 == 0 then
      Draw.color(C.text)
      love.graphics.rectangle("fill", math.floor(cx), f.y + 3, 1, f.h - 6)
    end
    local ok = self.naming ~= ""
    button(R.start.x, R.start.y, R.start.w, R.start.h, "Start", self.hoverStart, ok and 1 or 0.3, not ok)
    button(R.cancel.x, R.cancel.y, R.cancel.w, R.cancel.h, "Cancel", self.hoverCancel, 1)
    return
  end

  local glow = 0.6 + 0.4 * math.sin(self.hall.time * 2.2)
  local bx, by, bw, bh = self.hall:buttonRect()
  local label = self.confirmReplace and "Replace career?" or "New career"
  button(bx, by, bw, bh, label, self.hoverNew, glow)
  if self.app.career then
    local x, y, w, h = self:_backRect()
    button(x, y, w, h, "Back to academy", self.hoverBack, 1)
  end
  if self.confirmReplace then
    Draw.text("Click again to start over. " .. self.app.career.name .. "'s career will be lost.", 0, by - 14,
      C.bad, Assets.fonts.small, "center", W)
  end
  Draw.text("M quick match   D footwork demo   T training demo   Esc quit", 0, Layout.height - 10, C.textDim,
    Assets.fonts.small, "right", W - 6)
end

function Title:mousepressed(x, y, button)
  if button ~= 1 then return end
  if self.naming then
    if self.hoverStart then self:_start() elseif self.hoverCancel then self:_cancelNaming() end
    return
  end
  if self.hoverNew then self:_newCareer(); return end
  if self.hoverBack then self.app:switch("hub"); return end
  self.confirmReplace = false
end

function Title:textinput(t)
  if self.naming and #self.naming < HL.naming.maxLen and t:match("^[%w%s%-']$") then self.naming = self.naming .. t end
end

function Title:keypressed(key)
  if self.naming then
    if key == "backspace" then self.naming = self.naming:sub(1, -2)
    elseif key == "return" then self:_start()
    elseif key == "escape" then self:_cancelNaming() end
    return
  end
  if key == "return" then self:_newCareer() end
  if key == "m" then self.app:switch("quickmatch") end
  if key == "d" then self.app:switch("demo_balance") end
  if key == "t" then self.app:switch("demo_training") end
  if key == "escape" then
    if self.confirmReplace then self.confirmReplace = false else love.event.quit() end
  end
end

return Title
