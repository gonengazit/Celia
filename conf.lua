__picolove_version = "0.1.0"

scale = 4
xpadding = 8.5
ypadding = 3.5
__pico_resolution = { 128, 128 }

function love.conf(t)
	t.console = true

	t.identity = "picolove"

	t.version = "11.3"

	t.window.title = "PICOLÖVE"
	t.window.icon = "icon.png"
	t.window.width = __pico_resolution[1] * scale + xpadding * scale * 2
	t.window.height = __pico_resolution[2] * scale + ypadding * scale * 2
	t.window.resizable = true
end
