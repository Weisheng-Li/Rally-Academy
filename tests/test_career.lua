-- Career mode core: the daily plan, tournaments and promotion (src/core/career.lua,
-- src/core/tournament.lua).
local Career = require("src.core.career")
local Tournament = require("src.core.tournament")
local Training = require("src.core.training")
local Athletes = require("src.data.athletes")
local CD = require("src.data.career")
local PLAN = { "net_lift", "gym_legs", "clear_smash", "drives" }

local function lcg(seed)
  local x = seed
  return function()
    x = (x * 1103515245 + 12345) % 2147483648
    return x / 2147483648
  end
end

local function run(c, seconds)
  for _ = 1, math.floor(seconds / 0.05) do Training.update(c.sim, 0.05) end
  c.sim.events = {}
end

return {
  ["career core never touches love"] = function(t)
    for _, path in ipairs({ "src/core/career.lua", "src/core/tournament.lua", "src/data/career.lua" }) do
      local f = assert(io.open(path, "r"))
      local src = f:read("*a")
      f:close()
      t:ok(not src:find("love%.%a"), path .. " calls love.*")
    end
  end,

  ["a new career starts at Backyard with every trainable stat at 1"] = function(t)
    local c = Career.new({ rng = lcg(1) })
    t:ok(c.level == 1, "level 1")
    for name, sk in pairs(c.sim.skills) do t:ok(sk.level == 1, name .. " starts at 1") end
    t:ok(c.sim.schedule ~= Training.schedule, "career has its own schedule")
  end,

  ["the training demo keeps its own schedule and start"] = function(t)
    local s = Training.new({ rng = lcg(2) })
    t:ok(s.schedule == Training.schedule, "default schedule")
    t:ok(s.skills.clear.level == Training.data.start.clear, "default start")
  end,

  ["the plan fills the 4 slots and empty slots are free time"] = function(t)
    local c = Career.new({ rng = lcg(3), plan = PLAN })
    for i, id in ipairs(PLAN) do
      t:ok(c.slots[i].program == id, "slot " .. i .. " holds " .. id)
      t:ok(c.slots[i].label == Career.program(id).label, "slot " .. i .. " label")
    end
    t:ok(Career.setSlot(c, 4, false), "clear slot 4")
    t:ok(c.slots[4].kind == "idle" and not c.slots[4].loc and c.slots[4].label == "Free time", "empty slot = free time")
    t:ok(Career.setSlot(c, 4, "gym_arms") and c.slots[4].kind == "gym", "fill slot 4 again")
    t:ok(not Career.setSlot(c, 4, "no_such_program"), "unknown program refused")
  end,

  ["a slot locks once it starts, and editing later slots keeps the running block"] = function(t)
    local c = Career.new({ rng = lcg(4), plan = PLAN })
    t:ok(not Career.slotLocked(c, 1), "slot 1 open before 08:20")
    Training.jumpTo(c.sim, Training.minutes("08:30"))
    t:ok(Career.slotLocked(c, 1), "slot 1 locked once running")
    t:ok(not Career.setSlot(c, 1, "gym_arms"), "locked slot refuses changes")
    local running = Training.block(c.sim)
    t:ok(running == c.slots[1], "slot 1 is the running block")
    t:ok(Career.setSlot(c, 3, "gym_arms"), "later slot can change")
    t:ok(Career.swapSlots(c, 2, 4), "swap two open slots")
    t:ok(c.plan[2] == PLAN[4] and c.plan[4] == PLAN[2], "swapped")
    t:ok(not Career.swapSlots(c, 1, 2), "can't swap with a locked slot")
    t:ok(Training.block(c.sim) == running, "same block object still running")
    run(c, 20)
    t:ok(c.sim.activity.kind ~= nil, "sim still runs")
  end,

  ["match stats: reach and recovery follow legs, reaction is the league's"] = function(t)
    local c = Career.new({ rng = lcg(5), level = 3 })
    c.sim.skills.legs.level = 6
    local d = Career.athleteDef(c)
    t:ok(d.stats.reach == 6 and d.stats.recovery == 6, "reach/recovery = legs")
    t:ok(d.stats.reaction == Athletes.levels[3].stats.reaction, "reaction = league")
    t:ok(d.level == 3 and d.brain == Athletes.levels[3].brain, "level and brain")
  end,

  ["draw sizes and rounds per league"] = function(t)
    local rounds = { 2, 2, 3, 3, 4, 5 }
    for level = 1, 6 do
      local tm = Tournament.new({ level = level, you = Athletes.level(level, "You"), rng = lcg(level) })
      t:ok(#tm.field[1] == CD.events[level].size, "draw size Lv" .. level)
      t:ok(tm.rounds == rounds[level], "rounds Lv" .. level)
      t:ok(tm.field[1][1].you, "you are slot 1")
      local names = {}
      for i = 2, #tm.field[1] do
        local n = tm.field[1][i].name
        t:ok(not names[n], "no repeated names: " .. n)
        names[n] = true
      end
    end
  end,

  ["each round's top seed is stronger, the final previews the next league"] = function(t)
    local tm = Tournament.new({ level = 3, you = Athletes.level(3, "You"), rng = lcg(9) })
    local last = -1
    for r = 1, tm.rounds do
      local seed = tm.field[1][2 ^ (r - 1) + 1]
      t:ok(seed.strength > last, "round " .. r .. " seed stronger")
      last = seed.strength
    end
    t:near(last, 1, 1e-9, "final seed is the next league")
  end,

  ["win every round: promoted, history recorded"] = function(t)
    local c = Career.new({ rng = lcg(11), level = 2 })
    local tm = Career.enter(c)
    local opponents = {}
    while not tm.over do
      opponents[#opponents + 1] = Tournament.opponent(tm)
      Tournament.report(tm, true, "5-2")
    end
    t:ok(#opponents == tm.rounds, "played every round")
    t:ok(tm.won and tm.champion.you, "you are champion")
    local res = Career.finish(c)
    t:ok(res.promoted and res.from == 2 and res.to == 3 and c.level == 3, "promoted to 3")
    t:ok(#c.history == 1 and c.history[1].won and c.history[1].result == "Won", "history")
    t:ok(c.tournament == nil, "tournament cleared")
  end,

  ["lose in round 1: no promotion, the bracket still finishes"] = function(t)
    local c = Career.new({ rng = lcg(12), level = 4 })
    local tm = Career.enter(c)
    local opp = Tournament.opponent(tm)
    Tournament.report(tm, false, "3-5")
    t:ok(tm.over and not tm.won and tm.lostRound == 1 and tm.lostTo == opp, "lost round 1")
    t:ok(tm.champion and not tm.champion.you, "someone else won it")
    t:ok(#tm.results == tm.rounds, "every round resolved")
    local res = Career.finish(c)
    t:ok(not res.promoted and c.level == 4, "still Lv4")
    t:ok(c.history[1].result == "Lost Round 1", "result text: " .. c.history[1].result)
  end,

  ["winning the World Championship makes you champion"] = function(t)
    local c = Career.new({ rng = lcg(13), level = 6 })
    local tm = Career.enter(c)
    t:ok(tm.size == 32, "32 draw")
    while not tm.over do Tournament.report(tm, true) end
    local res = Career.finish(c)
    t:ok(res.champion and c.champion and c.level == 6, "world champion")
  end,

  ["a new career has nothing planned: he arrives in the lobby and spends the day on his own"] = function(t)
    local c = Career.new({ rng = lcg(21) })
    for i = 1, 4 do t:ok(c.plan[i] == false, "slot " .. i .. " empty") end
    t:ok(c.sim.location == "lobby", "arrives in the lobby")
    for _, b in ipairs(c.schedule) do
      t:ok(b.kind == "idle" or b.kind == "free", b.label .. " is free time (no warm-up with an empty plan)")
    end
    local rooms, reps = {}, 0
    for _ = 1, math.floor(600 / 0.05) do
      Training.update(c.sim, 0.05)
      rooms[c.sim.location] = true
      for _, e in ipairs(c.sim.events) do if e.type == "rep" and c.sim.activity.kind == "drill" then reps = reps + 1 end end
      c.sim.events = {}
    end
    t:ok(reps == 0, "no drills without a plan")
    t:ok(rooms.lobby and (rooms.court or rooms.gym), "wanders out of the lobby")
    t:ok(Career.setSlot(c, 4, "drives"), "plan a slot")
    local warm = c.schedule[1]
    t:ok(warm.kind == "warmup" and warm.loc == "court", "warm-up comes back once something is planned")
  end,

  ["round names: Round 1, 2 ... then Final (no semi- / quarter-finals)"] = function(t)
    t:ok(Tournament.roundName(2, 1) == "Round 1" and Tournament.roundName(2, 2) == "Final", "4 players")
    t:ok(Tournament.roundName(5, 4) == "Round 4" and Tournament.roundName(5, 5) == "Final", "32 players")
  end,

  ["bracket portraits: you are in your blue, everyone else keeps one colour by name"] = function(t)
    local Avatar = require("src.view.avatar")
    local Layout = require("src.config.layout")
    t:ok(Avatar.color({ name = "Alex", you = true }) == Layout.colors.near, "you")
    t:ok(Avatar.color({ name = "Okafor" }) == Avatar.color({ name = "Okafor" }), "same name, same colour")
  end,
}
