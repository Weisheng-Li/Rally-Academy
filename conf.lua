function love.conf(t)
  t.identity = "rally_academy"
  t.version = "11.5"
  t.console = false

  t.window.title = "Rally Academy"
  t.window.width = 1280
  t.window.height = 720
  t.window.minwidth = 640
  t.window.minheight = 360
  t.window.resizable = true
  t.window.vsync = 1

  t.modules.joystick = false
  t.modules.physics = false
  t.modules.video = false
end
