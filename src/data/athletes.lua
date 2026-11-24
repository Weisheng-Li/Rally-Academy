-- Athlete presets. Stats are levels 1-10:
--   1-2 beginner, 4-6 intermediate (club player), 8-10 advanced.
--   Technique: clear, lift, drop, net, drive, smash   -> hand shake (wobble) per shot family
--   Physical:  power -> max launch speed;  speed -> running speed;
--              legs  -> how much momentum you keep from a run, and how fast it fades
--   Movement:  reach -> lunge distance
local A = {
  rookie = {
    name = "You", title = "Rookie", tag = "Beginner at everything",
    stats = { clear = 2, lift = 2, drop = 1, net = 1, drive = 2, smash = 1,
              power = 2, speed = 2, legs = 2,
              reach = 2 },
  },
  trained = {
    name = "You", title = "Trained", tag = "Even intermediate",
    stats = { clear = 5, lift = 5, drop = 5, net = 5, drive = 5, smash = 5,
              power = 5, speed = 5, legs = 5,
              reach = 5 },
  },
  touch = {
    name = "You", title = "Touch Artist", tag = "Deadly drops and net play, no smash",
    stats = { clear = 3, lift = 4, drop = 7, net = 7, drive = 3, smash = 1,
              power = 2, speed = 4, legs = 4,
              reach = 6 },
  },
  hitter = {
    name = "You", title = "Big Hitter", tag = "Huge smash, clumsy touch, slow feet",
    stats = { clear = 6, lift = 4, drop = 3, net = 3, drive = 5, smash = 9,
              power = 9, speed = 5, legs = 7,
              reach = 4 },
  },
  technician = {
    name = "You", title = "Technician", tag = "Clean strokes, weak body",
    stats = { clear = 7, lift = 7, drop = 7, net = 7, drive = 7, smash = 6,
              power = 3, speed = 3, legs = 3,
              reach = 4 },
  },
  athlete = {
    name = "You", title = "Athlete", tag = "Reaches everything, sprays shots",
    stats = { clear = 5, lift = 5, drop = 4, net = 4, drive = 5, smash = 5,
              power = 7, speed = 9, legs = 8,
              reach = 8 },
  },
  kai = {
    name = "Kai", title = "Intermediate", tag = "Your opponent",
    stats = { clear = 6, lift = 6, drop = 5, net = 5, drive = 6, smash = 6,
              power = 6, speed = 6, legs = 6,
              reach = 5 },
  },
}

-- Order shown on the title screen (keys 1-6).
A.playable = { "rookie", "trained", "touch", "hitter", "technician", "athlete" }

return A
