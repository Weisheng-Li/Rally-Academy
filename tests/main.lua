-- Unit test runner. Run from the repo root:   lovec tests
-- Each tests/test_*.lua returns { ["test name"] = function(t) ... end }.
-- t:near(actual, expected, tol, msg)  t:ok(cond, msg)
package.path = "./?.lua;" .. package.path

local FILES = { "tests.test_body", "tests.test_figure", "tests.test_momentum" }

local T = {}
T.__index = T
function T:ok(cond, msg)
  if not cond then error(msg or "assertion failed", 2) end
end
function T:near(a, b, tol, msg)
  if math.abs(a - b) > tol then
    error(string.format("%s: got %.4f, expected %.4f (+-%.4f)", msg or "value", a, b, tol), 2)
  end
end

function love.load()
  local pass, fail = 0, 0
  for _, mod in ipairs(FILES) do
    local suite = require(mod)
    local names = {}
    for name in pairs(suite) do names[#names + 1] = name end
    table.sort(names)
    print(mod)
    for _, name in ipairs(names) do
      local ok, err = pcall(suite[name], setmetatable({}, T))
      if ok then
        pass = pass + 1
        print("  PASS  " .. name)
      else
        fail = fail + 1
        print("  FAIL  " .. name .. "\n        " .. tostring(err))
      end
    end
  end
  print(string.format("\n%d passed, %d failed", pass, fail))
  love.event.quit(fail > 0 and 1 or 0)
end
