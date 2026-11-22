-- Benchmark scenarios: near player (y > 0) hitting to the far half (y < 0).
-- Specs are placeholder shot definitions; edit freely, the bench reports what they produce.
local SPEC = {
  clear     = { kind = "apex", apex = 7.0 },
  lift      = { kind = "apex", apex = 5.5 },
  pushClear = { kind = "apex", apex = 3.5 },
  drop      = { kind = "net", clearance = 0.25 },
  netShot   = { kind = "net", clearance = 0.12 },
  push      = { kind = "net", clearance = 0.40 },
  smash     = { kind = "speed", speed = 45 },
  drive     = { kind = "speed", speed = 22 },
}

local BACK, MID, FRONT = 5.8, 3.6, 1.5
local X = 1.85

return {
  { name = "Straight clear",  from = { x = X, y = BACK },  h0 = 2.6, to = { x = X, y = -BACK },  spec = SPEC.clear },
  { name = "Cross clear",     from = { x = X, y = BACK },  h0 = 2.6, to = { x = -X, y = -BACK }, spec = SPEC.clear },
  { name = "Straight drop",   from = { x = X, y = BACK },  h0 = 2.6, to = { x = X, y = -FRONT }, spec = SPEC.drop },
  { name = "Cross drop",      from = { x = X, y = BACK },  h0 = 2.6, to = { x = -X, y = -FRONT }, spec = SPEC.drop },
  { name = "Straight smash",  from = { x = X, y = BACK },  h0 = 2.6, to = { x = X, y = -MID },   spec = SPEC.smash },
  { name = "Cross smash",     from = { x = X, y = BACK },  h0 = 2.6, to = { x = -X, y = -MID },  spec = SPEC.smash },
  { name = "Late smash",      from = { x = X, y = BACK },  h0 = 1.6, to = { x = X, y = -MID },   spec = SPEC.smash },
  { name = "Straight lift",   from = { x = X, y = FRONT }, h0 = 0.6, to = { x = X, y = -BACK },  spec = SPEC.lift },
  { name = "Cross lift",      from = { x = X, y = FRONT }, h0 = 0.6, to = { x = -X, y = -BACK }, spec = SPEC.lift },
  { name = "Straight net",    from = { x = X, y = FRONT }, h0 = 0.6, to = { x = X, y = -FRONT }, spec = SPEC.netShot },
  { name = "Cross net",       from = { x = X, y = FRONT }, h0 = 0.6, to = { x = -X, y = -FRONT }, spec = SPEC.netShot },
  { name = "Push",            from = { x = X, y = FRONT }, h0 = 0.6, to = { x = X, y = -MID },   spec = SPEC.push },
  { name = "Drive",           from = { x = X, y = MID },   h0 = 1.3, to = { x = X, y = -MID },   spec = SPEC.drive },
  { name = "Push clear",      from = { x = X, y = MID },   h0 = 1.3, to = { x = X, y = -BACK },  spec = SPEC.pushClear },
}
