-- Career: one athlete from Backyard to World Champion. Pure Lua (no love.*).
-- Holds the training sim (src/core/training.lua) running his days, the 4-slot daily plan,
-- his league, the tournament he is in (src/core/tournament.lua) and his history.
--
--   c = Career.new({ rng, name, level, plan })   plan: program ids per slot (default: empty)
--   Career.setSlot(c, i, programId | false)   change a slot that hasn't started yet
--   Career.slotLocked(c, i)                   started or done today
--   Career.athleteDef(c)                      him as a match athlete (src/core/athlete.lua def)
--   Career.enter(c) -> tournament;  Career.finish(c) -> { promoted, from, to, champion }
local CD = require("src.data.career")
local Athletes = require("src.data.athletes")
local Training = require("src.core.training")
local Tournament = require("src.core.tournament")

local Career = {}
Career.data = CD

local PROGRAMS = {}
for _, p in ipairs(CD.programs) do PROGRAMS[p.id] = p end
function Career.program(id) return id and PROGRAMS[id] or nil end

local IDLE = { kind = "idle", label = "Free time" }   -- no loc: he stays wherever he is

-- Fill a schedule block from a program (or free time) in place, so the sim's current block
-- table stays the same object.
local function fill(block, programId)
  local p = Career.program(programId) or IDLE
  block.kind, block.loc, block.label, block.focus, block.program = p.kind, p.loc, p.label, p.focus, p.id
end

-- Warm-up and cool-down only happen on a day with something planned: with an empty plan the
-- whole day is free time.
local function frame(c)
  local any = false
  for i = 1, #c.slots do if c.plan[i] then any = true end end
  for _, b in ipairs(c.schedule) do
    if b.base and b.base.kind ~= "free" then
      local p = any and b.base or IDLE
      b.kind, b.loc, b.label = p.kind, p.loc, p.label
    end
  end
end

-- Stats the sim's shot model uses for the untrained ones (placeholders, src/data/career.lua).
local function statsHook(c)
  return function(st)
    for _, k in ipairs(CD.movement.fromLegs) do st[k] = st.legs end
    for _, k in ipairs(CD.movement.fromLeague) do st[k] = Athletes.levels[c.level].stats[k] end
  end
end

function Career.new(o)
  o = o or {}
  local c = { name = o.name or "You", level = o.level or CD.startLevel, history = {}, plan = {},
              rng = o.rng or math.random, champion = false }
  for i, id in ipairs(o.plan or CD.defaultPlan) do c.plan[i] = id end
  local defs, slotIndex = {}, {}
  for i, b in ipairs(CD.day) do
    defs[i] = { start = b.start, stop = b.stop, kind = b.kind or "idle", loc = b.loc, label = b.label }
    if b.slot then slotIndex[b.slot] = i end
  end
  local schedule = Training.buildSchedule(defs)
  c.schedule, c.slots = schedule, {}
  for i, b in ipairs(CD.day) do
    if not b.slot then schedule[i].base = { kind = b.kind, loc = b.loc, label = b.label } end
  end
  for slot, i in pairs(slotIndex) do
    c.slots[slot] = schedule[i]
    schedule[i].slot = slot
    fill(schedule[i], c.plan[slot])
  end
  frame(c)
  -- every trainable stat starts at the league's level (Backyard = 1)
  local start = {}
  local L = Athletes.levels[c.level].stats
  for _, group in pairs(Training.data.skills) do
    for _, k in ipairs(group) do start[k] = math.floor(L[k]) end
  end
  c.sim = Training.new({ rng = c.rng, schedule = schedule, start = start, statsHook = statsHook(c),
                        arriveAt = CD.arriveAt })
  return c
end

function Career.slotBlock(c, i) return c.slots[i] end

-- A slot is locked once its block has started today (running or done).
function Career.slotLocked(c, i)
  return c.sim.clock >= c.slots[i].start
end

function Career.setSlot(c, i, id)
  if Career.slotLocked(c, i) then return false end
  if id and not PROGRAMS[id] then return false end
  c.plan[i] = id or false
  fill(c.slots[i], c.plan[i])
  frame(c)
  return true
end

-- Swap two slots' programs (drag one onto another); both must be open.
function Career.swapSlots(c, i, j)
  if Career.slotLocked(c, i) or Career.slotLocked(c, j) then return false end
  c.plan[i], c.plan[j] = c.plan[j], c.plan[i]
  fill(c.slots[i], c.plan[i]); fill(c.slots[j], c.plan[j])
  frame(c)
  return true
end

-- His stat levels as a match sees them.
function Career.stats(c)
  return Training.stats(c.sim)
end

function Career.rating(c) return Tournament.rating(Career.stats(c)) end

-- Typical stats of the next league (what the athlete card compares against).
function Career.targetStats(c)
  return Athletes.levels[math.min(#Athletes.levels, c.level + 1)].stats
end

function Career.athleteDef(c)
  local L = Athletes.levels[c.level]
  return { name = c.name, title = L.title, stats = Career.stats(c), brain = L.brain, level = c.level }
end

function Career.event(c) return CD.events[c.level] end

function Career.enter(c)
  c.tournament = Tournament.new({ level = c.level, you = Career.athleteDef(c), rng = c.rng })
  return c.tournament
end

-- After the tournament is over: record it, promote on a win.
function Career.finish(c)
  local t = c.tournament
  if not t or not t.over then return nil end
  local res = { from = c.level, to = c.level, promoted = false, champion = false }
  local result
  if t.won then
    result = "Won"
    if c.level < #Athletes.levels then
      c.level = c.level + 1
      res.promoted, res.to = true, c.level
    else
      c.champion, res.champion = true, true
    end
  else
    result = "Lost " .. Tournament.roundName(t.rounds, t.lostRound)
  end
  c.history[#c.history + 1] = { day = c.sim.day, event = t.name, level = t.level, result = result, won = t.won }
  c.tournament = nil
  return res
end

return Career
