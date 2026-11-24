-- Developer command-line flags (used for automated screenshots and tuning runs).
--   --profile rookie|trained   skip the title screen
--   --seed N                   fixed random seed
--   --auto N                   AI plays your first N shots, then you take over
--   --hover K                  force-hover target option K when deciding
--   --pick K                   force-select option K (shows the recovery step)
--   --mouse X,Y                fake mouse position in virtual pixels
--   --shot SECONDS             save screenshots/shot.png after SECONDS and quit
--   --skidshot SECONDS         save it SECONDS into the first landed shuttle's skid instead
local Dev = {}

function Dev.parse(args)
  local d = {}
  local i = 1
  while i <= #args do
    local a, v = args[i], args[i + 1]
    if a == "--profile" then d.profile = v; i = i + 1
    elseif a == "--seed" then d.seed = tonumber(v); i = i + 1
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
