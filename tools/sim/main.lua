-- Headless balance simulation: AI vs AI using only src/core (no rendering).
-- Run from the repo root:  lovec tools/sim [matches]
-- Uses plain package.path so it also proves src/core has no love.* dependency.
package.path = "./?.lua;" .. package.path

local Match = require("src.core.match")
local Athletes = require("src.data.athletes")

local ERRORS = { net = true, long = true, wide = true, short = true }

local function run(profile, n)
  local wins, points, rallies = 0, { near = 0, far = 0 }, 0
  local hits = { near = 0, far = 0 }
  local errs = { near = 0, far = 0 }
  local winners = 0
  math.randomseed(1234)
  local t0 = os.clock()
  for _ = 1, n do
    local m = Match.new({ near = Athletes[profile], far = Athletes.kai, human = {}, rng = math.random })
    local guard = 0
    while not m.over do
      local r = m.rally
      m:update(1 / 30)
      for _, ev in ipairs(m:drainEvents()) do
        if ev.type == "hit" then hits[ev.key] = hits[ev.key] + 1 end
      end
      if r ~= m.rally or m.over then
        rallies = rallies + 1
        local res = r.result
        if ERRORS[res.reason] then
          -- the loser of the point made the error
          local loser = res.winner == "near" and "far" or "near"
          errs[loser] = errs[loser] + 1
        else
          winners = winners + 1
        end
      end
      guard = guard + 1
      assert(guard < 30 * 60 * 60, "match did not finish")
    end
    if m.winner == "near" then wins = wins + 1 end
    points.near, points.far = points.near + m.score.near, points.far + m.score.far
  end
  local shots = hits.near + hits.far
  print(string.format(
    "%-10s vs Kai: wins %3d%%  score %.1f-%.1f  shots/rally %.1f  points from mistakes %d%%  shot errors: %s %d%%, Kai %d%%  (%.1fs)",
    profile, math.floor(wins / n * 100 + 0.5), points.near / n, points.far / n, shots / rallies,
    math.floor((rallies - winners) / rallies * 100 + 0.5),
    profile, math.floor(errs.near / math.max(1, hits.near) * 100 + 0.5),
    math.floor(errs.far / math.max(1, hits.far) * 100 + 0.5), os.clock() - t0))
end

function love.load(args)
  local n = tonumber(args[1]) or 200
  local Ath = require("src.data.athletes")
  for _, key in ipairs(Ath.playable) do run(key, n) end
  love.event.quit()
end
