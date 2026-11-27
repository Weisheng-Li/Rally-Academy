-- Headless simulation: AI vs AI using only src/core (no rendering).
-- Run from the repo root:
--   lovec tools/sim levels [matches]          each level vs the next one up
--   lovec tools/sim anticipation [matches]    equal players, only anticipation differs
-- Uses plain package.path so it also proves src/core has no love.* dependency.
package.path = "./?.lua;" .. package.path

local Match = require("src.core.match")
local Athletes = require("src.data.athletes")

local function copy(t)
  local o = {}
  for k, v in pairs(t) do o[k] = type(v) == "table" and copy(v) or v end
  return o
end

-- Play n matches A vs B, swapping sides and first server every match.
-- Returns A's match win rate, A's point share, seconds.
local function play(defA, defB, n, seed)
  math.randomseed(seed or 1234)
  local wins, ptsA, ptsB = 0, 0, 0
  local t0 = os.clock()
  for i = 1, n do
    local aNear = i % 2 == 1
    local m = Match.new({ near = aNear and defA or defB, far = aNear and defB or defA, human = {},
                          rng = math.random, server = (i % 4 < 2) and "near" or "far" })
    local guard = 0
    while not m.over do
      m:update(1 / 30)
      m:drainEvents()
      guard = guard + 1
      assert(guard < 30 * 60 * 60, "match did not finish")
    end
    local a, b = aNear and "near" or "far", aNear and "far" or "near"
    if m.winner == a then wins = wins + 1 end
    ptsA, ptsB = ptsA + m.score[a], ptsB + m.score[b]
  end
  return wins / n, ptsA / (ptsA + ptsB), os.clock() - t0
end

-- 95% interval half-width for a proportion
local function ci(p, n) return 1.96 * math.sqrt(p * (1 - p) / n) end

local function levels(n)
  for i = 1, #Athletes.levels - 1 do
    local w, pts, s = play(Athletes.level(i + 1), Athletes.level(i), n)
    print(string.format("%-12s vs %-12s  wins %3.0f%%  points %3.0f%%  (%.0fs)",
      Athletes.levels[i + 1].title, Athletes.levels[i].title, w * 100, pts * 100, s))
  end
end

local function anticipation(n)
  for _, lvl in ipairs({ 4, 5 }) do
    print(string.format("\n%s stats on both sides, same brain except anticipation (%d matches each):",
      Athletes.levels[lvl].title, n))
    local function with(ant)
      local d = copy(Athletes.level(lvl))
      d.brain.anticipation = ant
      d.brain.recovery = "center"
      return d
    end
    for _, pair in ipairs({ { 1, 0 }, { 2, 0 }, { 3, 0 }, { 2, 1 }, { 3, 2 } }) do
      local w, pts, s = play(with(pair[1]), with(pair[2]), n, 1000 + pair[1] * 10 + pair[2])
      print(string.format("  anticipation %d vs %d: wins %3.0f%% +-%2.0f   points %4.1f%% +-%3.1f  (%.0fs)",
        pair[1], pair[2], w * 100, ci(w, n) * 100, pts * 100, ci(pts, n * 25) * 100, s))
    end
  end
end

function love.load(args)
  local mode, n = args[1] or "levels", tonumber(args[2]) or 200
  if mode == "anticipation" then anticipation(n) else levels(n) end
  love.event.quit()
end
