-- Headless balance simulation: AI vs AI using only src/core (no rendering).
-- Run from the repo root:  lovec tools/sim [matches]
-- Uses plain package.path so it also proves src/core has no love.* dependency.
package.path = "./?.lua;" .. package.path

local Match = require("src.core.match")
local Athletes = require("src.data.athletes")

local function run(profile, n)
  local wins, points, shots, rallies, reasons = 0, { near = 0, far = 0 }, 0, 0, { winner = 0, out = 0, net = 0 }
  math.randomseed(1234)
  for _ = 1, n do
    local m = Match.new({ near = Athletes[profile], far = Athletes.kai, human = {}, rng = math.random })
    local guard = 0
    while not m.over do
      local r = m.rally
      m:update(1 / 30)
      if r ~= m.rally or m.over then
        rallies = rallies + 1
        shots = shots + r.result.shots
        reasons[r.result.reason] = reasons[r.result.reason] + 1
      end
      guard = guard + 1
      assert(guard < 30 * 60 * 60, "match did not finish")
    end
    m:drainEvents()
    if m.winner == "near" then wins = wins + 1 end
    points.near, points.far = points.near + m.score.near, points.far + m.score.far
  end
  print(string.format("%-8s vs Kai: wins %3d%%  avg score %.1f-%.1f  avg shots/rally %.1f  ends: winner %d%% out %d%% net %d%%",
    profile, math.floor(wins / n * 100 + 0.5), points.near / n, points.far / n, shots / rallies,
    math.floor(reasons.winner / rallies * 100), math.floor(reasons.out / rallies * 100), math.floor(reasons.net / rallies * 100)))
end

function love.load(args)
  local n = tonumber(args[1]) or 200
  run("rookie", n)
  run("trained", n)
  love.event.quit()
end
