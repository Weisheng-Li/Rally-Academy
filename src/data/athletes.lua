-- Athlete presets. Stats are levels 1-10 (5 = average club player).
return {
  rookie = {
    name = "You", title = "Rookie (no training)",
    stats = { speed = 3, reaction = 3, recovery = 3, power = 3,
              clear = 3, drop = 3, smash = 3, net = 3, drive = 3, lift = 4 },
  },
  trained = {
    name = "You", title = "Trained",
    stats = { speed = 7, reaction = 6, recovery = 6, power = 6,
              clear = 6, drop = 6, smash = 6, net = 6, drive = 6, lift = 6 },
  },
  kai = {
    name = "Kai", title = "Club champion",
    stats = { speed = 7, reaction = 6, recovery = 6, power = 7,
              clear = 6, drop = 6, smash = 7, net = 6, drive = 6, lift = 6 },
  },
}
