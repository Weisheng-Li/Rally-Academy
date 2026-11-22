-- Shot evaluation: turns (stats, where from, where to, timing) into success %, flight time
-- and a human-readable breakdown. Pure Lua (no love.*).
local Data = require("src.data.shots")

local Shots = { data = Data }

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

function Shots.typeFor(fromDepth, toDepth)
  return Data.matrix[fromDepth][toDepth]
end

function Shots.contactHeight(depth, timing)
  return Data.contactHeight[depth][timing or "ontime"]
end

-- Receiver's timing when they get to the shuttle.
function Shots.timingFromSlack(slack)
  if slack >= Data.slackEarly then return "early" end
  if slack >= 0 then return "ontime" end
  return "late"
end

-- Like timingFromSlack, but also says when they cannot reach it at all.
function Shots.reachState(slack)
  if slack < Data.slackReach then return "winner" end
  return Shots.timingFromSlack(slack)
end

Shots.REACH_LABEL = { winner = "Can't reach", late = "Late", ontime = "On time", early = "Comfortable" }

-- stats: athlete stat levels; from/to: world positions; timing: "early"|"ontime"|"late".
function Shots.evaluate(stats, from, to, shotId, timing, isServe)
  local def = Data.types[shotId]
  local tm = Data.timing[timing or "ontime"]
  local lvl = stats[def.skill] or 5

  local sided = (not isServe) and math.abs(from.x) > 0.5
  local cross = sided and ((from.x > 0) ~= (to.x > 0)) or false

  local rows = {}
  local function row(label, value) rows[#rows + 1] = { label = label, value = value } end
  row("Base " .. def.name:lower(), def.base)
  row(string.format("%s skill Lv%d", Data.skillNames[def.skill], lvl), (lvl - 5) * Data.skillPerLevel)
  if cross then row("Cross-court", Data.cross.success) end
  if tm.success ~= 0 then row(tm.label .. " contact", tm.success) end

  local sum = 0
  for _, r in ipairs(rows) do sum = sum + r.value end

  local flight = def.flight
  if def.powerFlight then flight = flight - def.powerFlight * ((stats.power or 5) - 5) end
  flight = flight * tm.flightMul + tm.flightAdd
  if cross then flight = flight + Data.cross.flight end

  local name = def.name
  if sided then name = (cross and "Cross " or "Straight ") .. def.name:lower() end

  return {
    shotId = shotId, def = def, name = name, cross = cross,
    success = clamp(sum, 0.05, 0.99), breakdown = rows, flight = flight,
  }
end

return Shots
