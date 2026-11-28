-- The academy's rooms (court | lobby | gym): doors between neighbours, and the lobby's
-- clickable desk and whiteboard (src/view/lobby_view.lua, layout.training.lobby / doors).
local Layout = require("src.config.layout")
local Camera = require("src.view.camera")
local Lobby = require("src.view.lobby_view")
local Training = require("src.core.training")

local TL, HB = Layout.training, Layout.hub

local function overlaps(a, b)
  return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

return {
  ["every pair of neighbouring rooms has a door on both sides, at the side facing the other"] = function(t)
    local rooms = Training.data.rooms
    for i, r in ipairs(rooms) do
      for _, n in ipairs(Training.neighbours(r)) do
        local d = TL.doors[r] and TL.doors[r][n]
        t:ok(d, r .. " has a door to " .. n)
        local j
        for k, q in ipairs(rooms) do if q == n then j = k end end
        t:ok((d.x > 0) == (j > i), r .. "'s door to " .. n .. " is on the " .. (j > i and "right" or "left"))
      end
    end
  end,

  ["doors are off-screen: he walks out of the picture toward the next room"] = function(t)
    local cam = Camera.new(TL.camera)
    for room, doors in pairs(TL.doors) do
      for other, d in pairs(doors) do
        local x = cam:project(d.x, d.y, 0)
        t:ok(x < 0 or x > Layout.width, room .. " -> " .. other .. " door on screen at x " .. x)
      end
    end
  end,

  ["the lobby's desk and whiteboard are on screen and clear of the hub panels"] = function(t)
    local cam = Camera.new(TL.camera)
    local plan = { x = HB.plan.x, y = HB.plan.y, w = HB.plan.w, h = 125 }
    local stats = { x = HB.stats.x, y = HB.stats.y, w = HB.stats.w, h = 156 }
    for name, r in pairs({ desk = Lobby.deskRect(cam), board = Lobby.boardRect(cam) }) do
      t:ok(r.x >= 0 and r.y >= 0 and r.x + r.w <= Layout.width and r.y + r.h <= Layout.height, name .. " on screen")
      t:ok(r.w > 20 and r.h > 10, name .. " big enough to click")
      t:ok(not overlaps(r, plan) and not overlaps(r, stats), string.format("%s not under the plan or stats panel (%.0f,%.0f %.0fx%.0f)", name, r.x, r.y, r.w, r.h))
    end
  end,
}
