-- A knockout tournament for one league (src/data/career.lua events). Pure Lua (no love.*).
--
-- You are always slot 1 of the draw. Your round r opponent comes out of the block of slots
-- 2^(r-1)+1 .. 2^r; that block's top seed has stats blended from this league toward the next
-- by r / R, the rest are weaker, so the draw gets harder each round and the final previews
-- the next league. Matches you are not in are decided from the players' ratings.
--
--   t = Tournament.new({ level, you = athleteDef, rng })
--   Tournament.opponent(t)          who you play this round
--   Tournament.report(t, youWon, score)   your result; resolves the rest of the round
--   t.over, t.won, t.round, t.rounds (R), t.field[r] (players entering round r), t.results[r]
local CD = require("src.data.career")
local Athletes = require("src.data.athletes")

local Tournament = {}

local STAT_KEYS = { "clear", "lift", "drop", "net", "drive", "smash", "power", "speed", "legs", "stamina",
                    "reach", "reaction", "recovery" }
Tournament.STAT_KEYS = STAT_KEYS

-- Average stat level (1-10): the number shown as a player's rating.
function Tournament.rating(stats)
  local sum = 0
  for _, k in ipairs(STAT_KEYS) do sum = sum + (stats[k] or 5) end
  return sum / #STAT_KEYS
end

-- "Round 1", "Round 2", ... and "Final" (draws are small: semi- / quarter-final add nothing).
function Tournament.roundName(rounds, r)
  if r >= rounds then return "Final" end
  return "Round " .. r
end

-- Opponent stats: this league's level blended toward the next by u (0..1), with noise.
function Tournament.blendStats(level, u, rng, spread)
  local A = Athletes.levels[level].stats
  local B
  if level < #Athletes.levels then
    B = Athletes.levels[level + 1].stats
  else
    B = {}
    for _, k in ipairs(STAT_KEYS) do B[k] = math.min(10, A[k] + CD.beyondTop) end
  end
  local st = {}
  for _, k in ipairs(STAT_KEYS) do
    local v = A[k] + (B[k] - A[k]) * u + (rng() * 2 - 1) * (spread or 0)
    st[k] = math.floor(math.max(1, math.min(10, v)) * 10 + 0.5) / 10
  end
  return st
end

local function makePlayer(level, u, rng, name)
  local brainLevel = math.min(#Athletes.levels, level + (u >= 0.5 and 1 or 0))
  local stats = Tournament.blendStats(level, u, rng, CD.spread)
  return { name = name, stats = stats, brain = Athletes.levels[brainLevel].brain, level = level,
           title = Athletes.levels[level].title, rating = Tournament.rating(stats), strength = u }
end

-- Names without repeats.
local function namePicker(rng)
  local pool = {}
  for i, n in ipairs(CD.names) do pool[i] = n end
  return function()
    if #pool == 0 then return "Player" end
    return table.remove(pool, math.floor(rng() * #pool) + 1)
  end
end

function Tournament.new(o)
  local rng = o.rng or math.random
  local ev = CD.events[o.level]
  local size = ev.size
  local R = math.floor(math.log(size) / math.log(2) + 0.5)
  local t = { level = o.level, event = ev, name = ev.name, size = size, rounds = R, round = 1, rng = rng,
              field = {}, results = {}, over = false, won = false }
  local you = {}
  for k, v in pairs(o.you) do you[k] = v end
  you.you = true
  you.rating = Tournament.rating(you.stats)
  local slots = { you }
  local nextName = namePicker(rng)
  for r = 1, R do
    local first, last = 2 ^ (r - 1) + 1, 2 ^ r
    local top = r / R
    for i = first, last do
      local u = i == first and top or top * (0.25 + 0.6 * rng())
      slots[i] = makePlayer(o.level, u, rng, nextName())
    end
  end
  t.field[1] = slots
  return t
end

function Tournament.opponent(t)
  local f = t.field[t.round]
  return f and f[2]
end

-- Chance that a beats b (ratings in stat levels).
function Tournament.winChance(a, b)
  local gap = (a.rating or 0) - (b.rating or 0)
  local edge = (CD.upsetEdge - 0.5) * math.min(1, math.abs(gap))
  return gap >= 0 and 0.5 + edge or 0.5 - edge
end

-- Resolve round r (field[r] -> field[r+1]); yourResult = true/false for pair 1, nil = simulate it.
local function playRound(t, r, yourResult, score)
  local f = t.field[r]
  local nextField, res = {}, {}
  for i = 1, #f, 2 do
    local a, b = f[i], f[i + 1]
    local aWins
    if i == 1 and yourResult ~= nil then aWins = yourResult
    else aWins = t.rng() < Tournament.winChance(a, b) end
    local w = aWins and a or b
    res[#res + 1] = { a = a, b = b, winner = w, score = i == 1 and score or nil }
    nextField[#nextField + 1] = w
  end
  t.results[r] = res
  t.field[r + 1] = nextField
end

-- Your match this round is done. Resolves the other matches, then either moves you to the
-- next round, or ends the tournament (lost: the remaining rounds are simulated so the
-- bracket still gets a champion).
function Tournament.report(t, youWon, score)
  if t.over then return end
  playRound(t, t.round, youWon, score)
  if not youWon then
    t.over, t.won, t.lostRound, t.lostTo = true, false, t.round, t.field[t.round][2]
    for r = t.round + 1, t.rounds do playRound(t, r) end
    t.champion = t.field[t.rounds + 1][1]
    return
  end
  if t.round == t.rounds then
    t.over, t.won, t.champion = true, true, t.field[t.rounds + 1][1]
    return
  end
  t.round = t.round + 1
end

return Tournament
