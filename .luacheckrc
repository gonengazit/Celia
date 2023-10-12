std = "luajit+love"

globals = {
  -- variables
  "pico8",
  "cartname",
  "__pico_resolution",
  "__picolove_version",
  "currentDirectory",
  "host_time",
  "scale",
  "xpadding",
  "ypadding",
  "loaded_code",
  "love.graphics.point",
  "love.handlers",
  "love.graphics.newScreenshot",
  "love.graphics.isActive",
  "ke",

  -- functions
  "warning",
  "log",
  "setColor",
  "restore_clip",
  "patch_lua",
  "shdr_unpack",
  "restore_camera",
  "flip_screen",
  "_load",
  "new_sandbox",
}

ignore = {
}

exclude_files = {
  "Love.js-Api-Player",
  "keybindings.lua",
  "lib",
  "spec",
  ".DS_Store",
}
