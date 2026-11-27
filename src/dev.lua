-- Developer command-line flags (used for automated screenshots and tuning runs).
--   --profile N                skip the title screen: you play at level N (1-6)
--   --opp N                    opponent level (1-6, default 3)
--   --seed N                   fixed random seed
--   --server near|far          who serves first (default near)
--   --auto N                   AI plays your first N shots, then you take over
--   --hover K                  force-hover target option K when deciding
--   --pick K                   force-select option K (shows the recovery step)
--   --mouse X,Y                fake mouse position in virtual pixels
--   --shot SECONDS             save screenshots/shot.png after SECONDS and quit
--   --skidshot SECONDS         save it SECONDS into the first landed shuttle's skid instead
--   --demo NAME                open a prototype demo scene (src/scenes/demo_NAME.lua), e.g. balance
--   --clip N                   lunge demo: loop only clip N
--   --clock HH:MM              training demo: start at this time of day
--   --speed N                  training demo: time speed (1, 3, 10, 30)
--   --coach N                  training demo: click to coach every N seconds (at --mouse or the centre)
--   --anytime                  --shot fires at SECONDS even mid-rally (no decision needed)
local Dev = {}

function Dev.parse(args)
  local d = {}
  local i = 1
  while i <= #args do
    local a, v = args[i], args[i + 1]
    if a == "--profile" then d.profile = tonumber(v) or 3; i = i + 1
    elseif a == "--opp" then d.opp = tonumber(v); i = i + 1
    elseif a == "--seed" then d.seed = tonumber(v); i = i + 1
    elseif a == "--server" then d.server = v; i = i + 1
    elseif a == "--demo" then d.demo = v; i = i + 1
    elseif a == "--zoom" then d.zoom = true
    elseif a == "--anytime" then d.anytime = true
    elseif a == "--clip" then d.clip = tonumber(v); i = i + 1
    elseif a == "--clock" then d.clock = v; i = i + 1
    elseif a == "--speed" then d.speed = tonumber(v); i = i + 1
    elseif a == "--coach" then d.coach = tonumber(v); i = i + 1
    elseif a == "--auto" then d.autoDecisions = tonumber(v); i = i + 1
    elseif a == "--hover" then d.hover = tonumber(v); i = i + 1
    elseif a == "--pick" then d.pick = tonumber(v); i = i + 1
    elseif a == "--shot" then d.shotAt = tonumber(v); i = i + 1
    elseif a == "--skidshot" then d.skidShot = tonumber(v); d.shotAt = d.shotAt or 0; i = i + 1
    elseif a == "--mouse" then
      local x, y = v:match("([%d%.]+),([%d%.]+)")
      d.mouse = { x = tonumber(x), y = tonumber(y) }
      i = i + 1
    end
    i = i + 1
  end
  return d
end

return Dev
