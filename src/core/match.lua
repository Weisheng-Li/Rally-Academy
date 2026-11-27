-- A single game: rally scoring, serve rotation, win condition. Pure Lua (no love.*).
local Athlete = require("src.core.athlete")
local Rally = require("src.core.rally")

local Match = {}
Match.__index = Match

-- o: { near = athleteDef, far = athleteDef, pointsToWin = 5, cap = 7, server = "near",
--      human = {near=true}, rng = fn, aiProfile = {} }
function Match.new(o)
  local self = setmetatable({}, Match)
  self.players = { near = Athlete.new(o.near, 1), far = Athlete.new(o.far, -1) }   -- fresh: no carried fatigue
  self.score = { near = 0, far = 0 }
  self.server = o.server or "near"
  self.pointsToWin = o.pointsToWin or 5   -- first to 5, win by 2, capped at 7 (short games while testing)
  self.cap = o.cap or 7
  self.human = o.human or { near = true }
  self.rng = o.rng or math.random
  self.aiProfile = o.aiProfile
  self.events = {}
  self.over = false
  self:_newRally()
  return self
end

function Match:_newRally()
  self.rally = Rally.new({
    players = self.players, server = self.server, serverScore = self.score[self.server],
    human = self.human, rng = self.rng, events = self.events, aiProfile = self.aiProfile,
  })
end

function Match:_isOver(w)
  local s, o = self.score[w], self.score[Rally.other(w)]
  return s >= self.cap or (s >= self.pointsToWin and s - o >= 2)
end

-- Returns and clears events produced since the last call (for the view layer).
function Match:drainEvents()
  local evs = self.events
  self.events = {}
  self.rally.events = self.events
  return evs
end

function Match:update(dt)
  if self.over then return end
  self.rally:update(dt)
  if self.rally.phase == "done" then
    local w = self.rally.result.winner
    self.score[w] = self.score[w] + 1
    self.server = w
    if self:_isOver(w) then
      self.over = true
      self.winner = w
    else
      self:_newRally()
    end
  end
end

return Match
