-- Low serve in the rally (src/core/rally.lua): tossed up a little, hit on the way down.
local Athlete = require("src.core.athlete")
local Rally = require("src.core.rally")
local Shots = require("src.core.shots")

local function stats()
  local s = {}
  for _, k in ipairs({ "clear", "lift", "drop", "net", "drive", "smash", "power", "speed", "legs", "reach" }) do s[k] = 5 end
  return s
end

local function rally(server)
  local seed = 7
  local rng = function() seed = (seed * 16807) % 2147483647; return seed / 2147483647 end
  local players = { near = Athlete.new({ name = "N", stats = stats() }, 1),
                    far = Athlete.new({ name = "F", stats = stats() }, -1) }
  return Rally.new({ players = players, server = server, serverScore = 0, human = {}, rng = rng })
end

return {
  ["serve: shuttle is tossed up, hit on the way down, then flies from the contact"] = function(t)
    for _, key in ipairs({ "near", "far" }) do
      local r = rally(key)
      local g = r.serveGeo
      t:near(r.shuttle.h, g.start.h, 1e-9, key .. " held at the chest")
      local s = r.players[key]
      t:near(r.shuttle.pos.x, s.pos.x, 1e-9, key .. " in front of the body centre")
      -- depth-sorted drawing: toward the net = hidden behind the near player (seen from
      -- behind), drawn over the far player (facing the camera)
      t:ok((r.shuttle.pos.y + 0.01 - s.pos.y) * s.side < 0, key .. " in front of the body, toward the net")
      t:ok(r.players[key].pose.state == "serve", key .. " serving pose")
      local dt = 1 / 60
      while r.phase == "pre" do r:update(dt) end
      t:ok(r.phase == "toss", key .. " AI serve goes to the toss")
      local recv = r.players[key == "near" and "far" or "near"]
      local before = { x = recv.pos.x, y = recv.pos.y }
      local maxH = 0
      for _ = 1, math.floor(Shots.data.serveToss.time / dt) - 1 do
        r:update(dt)
        maxH = math.max(maxH, r.shuttle.h)
      end
      t:ok(r.phase == "toss", key .. " still tossing")
      t:ok(recv.delay > 0 and not recv:isMoving(), key .. " receiver not moving yet (no frozen mid-step)")
      t:ok(maxH > g.start.h + 0.05, key .. " tossed up a little first")
      t:ok(r.shuttle.h < maxH, key .. " hit on the way down")
      t:near(recv.pos.x, before.x, 1e-12, key .. " receiver waits for the contact")
      t:near(recv.pos.y, before.y, 1e-12, key .. " receiver waits for the contact")
      r:update(dt); r:update(dt)
      t:ok(r.phase == "flight", key .. " flight after contact")
      t:ok(r.players[key].pose == nil, key .. " serve pose ends at contact")
      local p = r.path.points[1]
      t:near(p.x, g.contact.x, 1e-6, key .. " flight starts at the contact x")
      t:near(p.h, g.contact.h, 1e-6, key .. " flight starts at the contact height")
    end
  end,

  ["serve: even a backyard player lands at least half of both serves"] = function(t)
    local Athletes = require("src.data.athletes")
    local Court = require("src.core.court")
    local g = Shots.serveGeometry({ x = 0.7, y = 2.3 }, 1)
    local court = { xMin = -Court.HALF_WIDTH_SINGLES, xMax = 0, yMin = Court.SHORT_SERVICE, yMax = Court.LENGTH }
    local a = Athlete.new(Athletes.level(1), 1)
    local ctx = { stats = a.stats, from = { x = g.contact.x, y = g.contact.y }, h0 = g.contact.h,
                  contact = { state = "ontime", stretch = 0 }, momentum = 0, maxSpeed = a:maxLaunchSpeed(), court = court }
    for _, s in ipairs({ { "short_serve", -2.5 }, { "long_serve", -6.0 } }) do
      local ev = Shots.evaluate(ctx, { x = -1.0, y = s[2] }, s[1])
      t:ok(ev.available and ev.success >= 0.5, string.format("%s %.0f%%", s[1], (ev.success or 0) * 100))
    end
  end,

  ["serve: landing in front of the short service line is called short, even if it drifts across"] = function(t)
    local Court = require("src.core.court")
    local g = Shots.serveGeometry({ x = 0.7, y = 2.3 }, 1)
    local court = { xMin = -Court.HALF_WIDTH_SINGLES, xMax = 0, yMin = Court.SHORT_SERVICE, yMax = Court.LENGTH }
    local a = Athlete.new({ stats = stats() }, 1)
    local ctx = { stats = a.stats, from = { x = g.contact.x, y = g.contact.y }, h0 = g.contact.h,
                  contact = { state = "ontime", stretch = 0 }, momentum = 0, maxSpeed = a:maxLaunchSpeed(), court = court }
    local ev = Shots.evaluate(ctx, { x = -1.0, y = -2.5 }, "short_serve")
    t:ok(ev.classify(0.3, -1.5) == "short", "short and across the centre line = short")
    t:ok(ev.classify(-1.0, -1.5) == "short", "short")
    t:ok(ev.classify(0.3, -3.0) == "wide", "past the line but wrong box = wide")
  end,

  ["serve: toss arcs from the chest onto the contact"] = function(t)
    local g = Shots.serveGeometry({ x = 0.7, y = 2.3 }, 1)
    local s0, s1 = Shots.tossAt(g, 0), Shots.tossAt(g, 1)
    t:near(s0.h, g.start.h, 1e-9, "starts at the chest")
    t:near(s0.pos.x, g.start.x, 1e-9, "starts at the chest x")
    t:near(s1.h, g.contact.h, 1e-9, "ends at contact height")
    t:near(s1.pos.x, g.contact.x, 1e-9, "ends at contact x")
    t:near(s1.pos.y, g.contact.y, 1e-9, "ends at contact y")
    t:ok(Shots.tossAt(g, 0.98).h > s1.h, "falling into the contact")
  end,
}
