-- Opponent decision policy. Pure Lua (no love.*).
local Court = require("src.core.court")

local AI = {}

-- How much the AI values putting the receiver in each state.
local function pressure(a)
  if a.state == "winner" then return 1.0 end
  if a.state == "stretched" then return 0.3 + 0.5 * a.stretch end
  if a.state == "ontime" then return 0.2 end
  return 0.0
end

-- Returns option index (or nil if nothing is playable) and recovery spot.
function AI.choose(rally, decision, rng, profile)
  profile = profile or {}
  local riskAversion = profile.riskAversion or 0.9
  local noise = profile.noise or 0.25

  local bestIndex, bestScore
  for i, o in ipairs(decision.options) do
    if not o.disabled then
      local p = o.eval.success
      local score
      if decision.kind == "serve" then
        score = p + rng() * 0.1
      else
        score = p * pressure(o.receiver) - (1 - p) * riskAversion + rng() * noise
      end
      if not bestScore or score > bestScore then bestIndex, bestScore = i, score end
    end
  end

  local hitter = rally.players[decision.hitterKey]
  return bestIndex, Court.basePos(hitter.side)
end

return AI
