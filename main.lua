package.path = package.path .. ";?.lua;lib/?.lua"
love.filesystem.setRequirePath(package.path)

require("strict")
local QueueableSource = require("QueueableSource")

local bit = require("bit")

fixed_point_enabled=false

local api = require("api")
local cart = require("cart")
local fix32=require("fix32")

local tas = require("tas")
local cctas = require("cctas")
local cc2tas = require("cc2tas")

local console = require("console")

cartname = nil -- used by api.reload
local initialcartname = nil -- used by esc
local love_args = nil -- luacheck: no unused
local tastool = nil

pico8 = {
	clip = nil,
	fps = 30,
	frametime = 1 / 30,
	frames = 0,
	resolution = __pico_resolution,
	screen = nil,
	palette = {
		[0] = { 0, 0, 0, 255 },
		{ 29, 43, 83, 255 },
		{ 126, 37, 83, 255 },
		{ 0, 135, 81, 255 },
		{ 171, 82, 54, 255 },
		{ 95, 87, 79, 255 },
		{ 194, 195, 199, 255 },
		{ 255, 241, 232, 255 },
		{ 255, 0, 77, 255 },
		{ 255, 163, 0, 255 },
		{ 255, 240, 36, 255 },
		{ 0, 231, 86, 255 },
		{ 41, 173, 255, 255 },
		{ 131, 118, 156, 255 },
		{ 255, 119, 168, 255 },
		{ 255, 204, 170, 255 },
	},
	color = nil,
	spriteflags = {},
	map = {},
	audio_channels = {},
	sfx = {},
	music = {},
	current_music = nil,
	usermemory = {},
	cartdata = {},
	cart = nil,
	clipboard = "",
	keypressed = {
		[0] = {},
		[1] = {},
	},
	kbdbuffer={},
	keymap = {
		[0] = {
			[0] = { "left" },
			[1] = { "right" },
			[2] = { "up" },
			[3] = { "down" },
			[4] = { "z", "c" },
			[5] = { "x" },
			[6] = {},
			[7] = {},
		},
		[1] = {
			[0] = { "s" },
			[1] = { "f" },
			[2] = { "e" },
			[3] = { "d" },
			[4] = { "tab", "lshift", "w" },
			[5] = { "q", "a" },
			[6] = {},
			[7] = {},
		},
	},
	mwheel = 0,
	cursor = { 0, 0 },
	camera_x = 0,
	camera_y = 0,
	can_pause = true,
	can_shutdown = false,
	draw_palette = {},
	display_palette = {},
	pal_transparent = {},
	draw_shader = nil,
	sprite_shader = nil,
	display_shader = nil,
	text_shader = nil,
	quads = {},
	spritesheet_data = nil,
	spritesheet = nil,
	spritesheet_changed = false,
	rng_low = 0,
	rng_high = 0,
}
pico8_glyphs = { [0] = "\0",
	"¹", "²", "³", "⁴", "⁵", "⁶", "⁷", "⁸", "\t", "\n", "ᵇ",
	"ᶜ", "\r", "ᵉ", "ᶠ", "▮", "■", "□", "⁙", "⁘", "‖", "◀",
	"▶", "「", "」", "¥", "•", "、", "。", "゛", "゜", " ", "!",
	"\"", "#", "$", "%", "&", "'", "(", ")", "*", "+", ",", "-", ".", "/", "0",
	"1", "2", "3", "4", "5", "6", "7", "8", "9", ":", ";", "<", "=", ">", "?",
	"@", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N",
	"O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "[", "\\", "]",
	"^", "_", "`", "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l",
	"m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z", "{",
	"|", "}", "~", "○", "█", "▒", "🐱", "⬇️", "░", "✽", "●",
	"♥", "☉", "웃", "⌂", "⬅️", "😐", "♪", "🅾️", "◆",
	"…", "➡️", "★", "⧗", "⬆️", "ˇ", "∧", "❎", "▤", "▥",
	"あ", "い", "う", "え", "お", "か", "き", "く", "け", "こ", "さ",
	"し", "す", "せ", "そ", "た", "ち", "つ", "て", "と", "な", "に",
	"ぬ", "ね", "の", "は", "ひ", "ふ", "へ", "ほ", "ま", "み", "む",
	"め", "も", "や", "ゆ", "よ", "ら", "り", "る", "れ", "ろ", "わ",
	"を", "ん", "っ", "ゃ", "ゅ", "ょ", "ア", "イ", "ウ", "エ", "オ",
	"カ", "キ", "ク", "ケ", "コ", "サ", "シ", "ス", "セ", "ソ", "タ",
	"チ", "ツ", "テ", "ト", "ナ", "ニ", "ヌ", "ネ", "ノ", "ハ", "ヒ",
	"フ", "ヘ", "ホ", "マ", "ミ", "ム", "メ", "モ", "ヤ", "ユ", "ヨ",
	"ラ", "リ", "ル", "レ", "ロ", "ワ", "ヲ", "ン", "ッ", "ャ", "ュ",
	"ョ", "◜", "◝"
}

-- switch 2 utf-8 character glyphs with the respective 1 character alternative
glyph_edgecases = {
	["⬇️"] = "⬇",
	["🅾️"] = "🅾",
	["➡️"] = "➡",
	["⬆️"] = "⬆",
	["⬅️"] = "⬅"
}

local flr, abs = math.floor, math.abs

loaded_code = nil

local __audio_buffer_size = 1024

local gif = require("gif")
local gif_canvas = nil
local gif_recording = nil

local osc
local paused = false
local focus = true

local __audio_channels
local __sample_rate = 22050
local channels = 1
local bits = 16

currentDirectory = "carts/"
local glyphs=""
for i=32, 153 do
	glyphs=glyphs..(glyph_edgecases[pico8_glyphs[i]] or pico8_glyphs[i])
end

local function _allow_pause(value)
	if type(value) ~= "boolean" then
		value = true
	end
	pico8.can_pause = value
end

local function _allow_shutdown(value)
	if type(value) ~= "boolean" then
		value = true
	end
	pico8.can_shutdown = value
end

log = print

function shdr_unpack(thing)
	return unpack(thing, 0, 15)
end

function restore_clip()
	if pico8.clip then
		love.graphics.setScissor(unpack(pico8.clip))
	else
		love.graphics.setScissor()
	end
end

function setColor(c)
	love.graphics.setColor(c / 15, 0, 0, 1)
end

function _load(_cartname)
	if type(_cartname) ~= "string" then
		return false
	end

	local exts = { "", ".p8", ".p8.png", ".png" }
	local cart_no_ext = _cartname

	if _cartname:sub(-3) == ".p8" then
		exts = { ".p8", ".p8.png" }
		cart_no_ext = _cartname:sub(1, -4)
	elseif _cartname:sub(-7) == ".p8.png" then
		exts = { ".p8.png" }
		cart_no_ext = _cartname:sub(1, -8)
	elseif _cartname:sub(-4) == ".png" then
		exts = { ".png", ".p8.png" }
		cart_no_ext = _cartname:sub(1, -5)
	end

	local file_found = false
	for i = 1, #exts do
		if love.filesystem.getInfo(currentDirectory .. cart_no_ext .. exts[i],'file') ~= nil then
			file_found = true
			_cartname = cart_no_ext .. exts[i]
			break
		end
	end

	if not file_found then
		api.print("could not load", 6)
		return false
	end

	love.graphics.setShader(pico8.draw_shader)
	love.graphics.setCanvas(pico8.screen)
	love.graphics.origin()
	api.camera()
	restore_clip()
	cartname = _cartname
	if cart.load_p8(currentDirectory .. _cartname) then
		api.print("loaded " .. _cartname, 6)
	end

	pico8.rom={}
	for i=0,0x42ff do
		pico8.rom[i] = api.peek(i)
	end
	return true
end

function love.resize(w, h)
	-- adjust stuff to fit the screen
	local tas_w, tas_h = tastool.screen:getDimensions()
	scale = math.min(w/tas_w, h/tas_h)
end

local function note_to_hz(note)
	return 440 * 2 ^ ((note - 33) / 12)
end

function love.load(argv)
	love_args = argv
	if love.system.getOS() == "Android" or love.system.getOS() == "iOS" then
		love.resize(love.graphics.getDimensions())
	end

	osc = {}
	-- tri
	osc[0] = function(x)
		return (abs((x % 1) * 2 - 1) * 2 - 1) * 0.7
	end
	-- uneven tri
	osc[1] = function(x)
		local t = x % 1
		return (((t < 0.875) and (t * 16 / 7) or ((1 - t) * 16)) - 1) * 0.7
	end
	-- saw
	osc[2] = function(x)
		return (x % 1 - 0.5) * 0.9
	end
	-- sqr
	osc[3] = function(x)
		return (x % 1 < 0.5 and 1 or -1) * 1 / 3
	end
	-- pulse
	osc[4] = function(x)
		return (x % 1 < 0.3125 and 1 or -1) * 1 / 3
	end
	-- tri/2
	osc[5] = function(x)
		x = x * 4
		return (abs((x % 2) - 1) - 0.5 + (abs(((x * 0.5) % 2) - 1) - 0.5) / 2 - 0.1)
			* 0.7
	end
	-- noise
	osc[6] = function()
		local lastx = 0
		local sample = 0
		local lsample = 0
		local tscale = note_to_hz(63) / __sample_rate
		return function(x)
			local scale = (x - lastx) / tscale
			lsample = sample
			sample = (lsample + scale * (math.random() * 2 - 1)) / (1 + scale)
			lastx = x
			return math.min(
				math.max((lsample + sample) * 4 / 3 * (1.75 - scale), -1),
				1
			) * 0.7
		end
	end
	-- detuned tri
	osc[7] = function(x)
		x = x * 2
		return (abs((x % 2) - 1) - 0.5 + (abs(((x * 127 / 128) % 2) - 1) - 0.5) / 2)
			- 1 / 4
	end
	-- saw from 0 to 1, used for arppregiator
	osc["saw_lfo"] = function(x)
		return x % 1
	end

	__audio_channels = {
		[0] = QueueableSource:new(8),
		QueueableSource:new(8),
		QueueableSource:new(8),
		QueueableSource:new(8),
	}

	for i = 0, 3 do
		__audio_channels[i]:play()
	end

	for i = 0, 3 do
		pico8.audio_channels[i] = {
			oscpos = 0,
			noise = osc[6](),
		}
	end

	love.audio.setVolume(0)

	love.graphics.clear()
	love.graphics.setDefaultFilter("nearest", "nearest")
	pico8.screen =
		love.graphics.newCanvas(pico8.resolution[1], pico8.resolution[2])

	pico8.screen:setFilter("linear", "nearest")

	pico8.font = love.graphics.newImageFont("font.png", glyphs, 1)
	love.graphics.setFont(pico8.font)
	pico8.font:setFilter("nearest", "nearest")

	love.mouse.setVisible(false)
	love.keyboard.setKeyRepeat(true)
	love.graphics.setLineStyle("rough")
	love.graphics.setPointSize(1)
	love.graphics.setLineWidth(1)

	love.graphics.origin()
	love.graphics.setCanvas(pico8.screen)
	restore_clip()

	pico8.draw_palette = {}
	pico8.display_palette = {}
	pico8.pal_transparent = {}
	for i = 0, 15 do
		pico8.draw_palette[i] = i
		pico8.pal_transparent[i] = i == 0 and 0 or 1
		pico8.display_palette[i] = pico8.palette[i]
	end

	pico8.draw_shader = love.graphics.newShader([[
extern float palette[16];

vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
	int index = int(color.r*15.0+0.5);
	return vec4(palette[index]/15.0, 0.0, 0.0, 1.0);
}]])
	pico8.draw_shader:send("palette", shdr_unpack(pico8.draw_palette))

	pico8.sprite_shader = love.graphics.newShader([[
extern float palette[16];
extern float transparent[16];

vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
	int index = int(Texel(texture, texture_coords).r*15.0+0.5);
	float alpha = transparent[index];
	return vec4(palette[index]/15.0, 0.0, 0.0 ,alpha);
}]])
	pico8.sprite_shader:send("palette", shdr_unpack(pico8.draw_palette))
	pico8.sprite_shader:send("transparent", shdr_unpack(pico8.pal_transparent))

	pico8.text_shader = love.graphics.newShader([[
extern float palette[16];

vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
	vec4 texcolor = Texel(texture, texture_coords);
	if(texcolor.a == 0.0) {
		return vec4(0.0,0.0,0.0,0.0);
	}
	int index = int(color.r*15.0+0.5);
	// lookup the color in the palette by index
	return vec4(palette[index]/15.0, 0.0, 0.0, texcolor.a);
}]])
	pico8.text_shader:send("palette", shdr_unpack(pico8.draw_palette))

	pico8.display_shader = love.graphics.newShader([[
extern vec4 palette[16];

vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
	int index = int(Texel(texture, texture_coords).r*15.0+0.5);
	// lookup the color in the palette by index
	return palette[index]/255.0;
}]])
	pico8.display_shader:send("palette", shdr_unpack(pico8.display_palette))

	-- load the cart
	api.clip()
	api.camera()
	api.pal()
	api.color(6)

	local argc = #argv
	local argpos = 1
	local paramcount = 0

	local tas_tools = {
		cc2tas = cc2tas,
		cctas = cctas,
		tas = tas
	}

	local tas_tool_name = nil
	if argc >= 1 then
		-- TODO: implement commandline options
		while argpos <= argc do
			if argv[argpos] == "-width" then
				--local n = argv[argpos + 1]
				paramcount = 1
			elseif argv[argpos] == "-height" then
				--local n = argv[argpos + 1]
				paramcount = 1
			elseif argv[argpos] == "-windowed" then
				--local n = argv[argpos + 1]
				paramcount = 1
			elseif argv[argpos] == "-volume" then
				--local n = argv[argpos + 1]
				paramcount = 1
			elseif argv[argpos] == "-joystick" then
				--local n = argv[argpos + 1]
				paramcount = 1
			elseif argv[argpos] == "-pixel_perfect" then
				--local n = argv[argpos + 1]
				paramcount = 1
			elseif argv[argpos] == "-preblit_scale" then
				--local n = argv[argpos + 1]
				paramcount = 1
			elseif argv[argpos] == "-draw_rect" then
				--local x = argv[argpos + 1]
				--local y = argv[argpos + 2]
				--local w = argv[argpos + 3]
				--local h = argv[argpos + 4]
				paramcount = 4
			elseif argv[argpos] == "-run" then
				paramcount = 1
				local filename = argv[argpos + 1]
				initialcartname = filename
			elseif argv[argpos] == "-x" then
				paramcount = 1
				local filename = argv[argpos + 1]
				initialcartname = filename
			elseif argv[argpos] == "-export" then
				--local paramstr = argv[argpos + 1]
				paramcount = 1
			elseif argv[argpos] == "-p" then
				--local paramstr = argv[argpos + 1]
				paramcount = 1
			elseif argv[argpos] == "-splore" then
				paramcount = 0
			elseif argv[argpos] == "-home" then
				--local path = argv[argpos + 1]
				paramcount = 1
			elseif argv[argpos] == "-root_path" then
				--local path = argv[argpos + 1]
				paramcount = 1
			elseif argv[argpos] == "-desktop" then
				--local path = argv[argpos + 1]
				paramcount = 1
			elseif argv[argpos] == "-screenshot_scale" then
				--local n = argv[argpos + 1]
				paramcount = 1
			elseif argv[argpos] == "-gif_scale" then
				--local n = argv[argpos + 1]
				paramcount = 1
			elseif argv[argpos] == "-gif_len" then
				--local n = argv[argpos + 1]
				paramcount = 1
			elseif argv[argpos] == "-gui_theme" then
				--local n = argv[argpos + 1]
				paramcount = 1
			elseif argv[argpos] == "-timeout" then
				--local n = argv[argpos + 1]
				paramcount = 1
			elseif argv[argpos] == "-software_blit" then
				--local n = argv[argpos + 1]
				paramcount = 1
			elseif argv[argpos] == "-foreground_sleep_ms" then
				--local n = argv[argpos + 1]
				paramcount = 1
			elseif argv[argpos] == "-background_sleep_ms" then
				--local n = argv[argpos + 1]
				paramcount = 1
			elseif argv[argpos] == "-accept_future" then
				--local n = argv[argpos + 1]
				paramcount = 1
			elseif argv[argpos] == "-global_api" then
				--local n = argv[argpos + 1]
				paramcount = 1
			elseif argv[argpos] == "--test" then -- picolove commands
				paramcount = 0
				require("test")
			elseif argv[argpos] == "--fixp" then
				paramcount = 0
				fix32.init()
			elseif argv[argpos] == "--audio" then
				paramcount = 0
				love.audio.setVolume(1)
			elseif tas_tools[argv[argpos]] and tas_tool_name == nil then
				paramcount = 0
				tas_tool_name = argv[argpos]
			else
				if initialcartname == nil or initialcartname == "" then
					initialcartname = argv[argpos]
				end
			end

			argpos = argpos + paramcount + 1
		end
	end

	if initialcartname == nil or initialcartname == "" then
		initialcartname = "nocart.p8"
	end

	_load(initialcartname)
	api.run()

	if tas_tool_name == nil then
		print("no tas tool specified, defaulting to general pico-8 tas tool")
		tas_tool_name = "tas"
	end
	tastool=tas_tools[tas_tool_name]()
end

function new_sandbox()
	local cart_env = {}

	for k, v in pairs(api) do
		cart_env[k] = v
	end
	cart_env._ENV = cart_env -- experimental support for lua5.2 style _ENV

	-- extra functions provided by picolove
	local picolove_functions = {
		error = error,
		log = log,
		_keydown = nil,
		_keyup = nil,
		_touchdown = nil,
		_touchup = nil,
		_textinput = nil,
		-- used for repl
		_allow_pause = _allow_pause,
		_allow_shutdown = _allow_shutdown,
	}
	for k, v in pairs(picolove_functions) do
		cart_env[k] = v
	end

	return cart_env
end

local function inside(x, y, x0, y0, w, h) -- luacheck: no unused
	return (x >= x0 and x < x0 + w and y >= y0 and y < y0 + h)
end

function love.update(_)
	tastool:update()
end

function love.draw()

	love.graphics.setFont(pico8.font)
	love.graphics.setCanvas(pico8.screen)
	restore_clip()
	restore_camera()

	love.graphics.setShader(pico8.draw_shader)

	tastool:draw()

	-- draw the contents of pico screen to our screen
	flip_screen()
end

function restore_camera()
	love.graphics.origin()
	love.graphics.translate(-pico8.camera_x, -pico8.camera_y)
end

function flip_screen()
	love.graphics.setShader()
	love.graphics.setCanvas()
	love.graphics.origin()
	love.graphics.setScissor()

	love.graphics.setBackgroundColor(3/255, 5/255, 10/255)
	love.graphics.clear()

	--TODO: fix centering and scale

	local screen_w, screen_h = love.graphics.getDimensions()
	local tas_w, tas_h = tastool.screen:getDimensions()
	if screen_w/tas_w > screen_h/tas_h then
		love.graphics.draw(
			tastool.screen,
			screen_w / 2 - (tas_w / 2 * scale),
			0,
			0,
			scale,
			scale
		)
	else
		love.graphics.draw(
			tastool.screen,
			0,
			screen_h / 2 - (tas_h / 2 * scale),
			0,
			scale,
			scale
		)
	end

	if console.isEnabled() then
		console.draw()
	end

	love.graphics.present()

	if gif_canvas then
		love.graphics.setShader(pico8.display_shader)
		love.graphics.setCanvas(gif_canvas)
		love.graphics.draw(pico8.screen, 0, 0, 0, 2, 2)

		love.graphics.setShader()
		love.graphics.push()
		love.graphics.scale(2,2)
		tastool:draw_gif_overlay()
		love.graphics.pop()

		love.graphics.setCanvas()
		gif_recording:frame(gif_canvas:newImageData())
	end
	-- get ready for next time
	love.graphics.setShader(pico8.draw_shader)
	love.graphics.setCanvas(pico8.screen)
	restore_clip()
	restore_camera()
end

function love.focus(f)
	focus = f
end

function love.filedropped(file)
	tastool:load_input_file(file)
end

local function lowpass(y0, y1, cutoff) -- luacheck: no unused
	local RC = 1.0 / (cutoff * 2 * 3.14)
	local dt = 1.0 / __sample_rate
	local alpha = dt / (RC + dt)
	return y0 + (alpha * (y1 - y0))
end

local note_map = {
	[0] = "C-",
	"C#",
	"D-",
	"D#",
	"E-",
	"F-",
	"F#",
	"G-",
	"G#",
	"A-",
	"A#",
	"B-",
}

local function note_to_string(note) -- luacheck: no unused
	local octave = flr(note / 12)
	note = flr(note % 12)
	return string.format("%s%d", note_map[note], octave)
end

local function oldosc(oscfn)
	local x = 0
	return function(freq)
		x = x + freq / __sample_rate
		return oscfn(x)
	end
end

local function lerp(a, b, t)
	return (b - a) * t + a
end

local function update_audio(time)
	-- check what sfx should be playing
	local samples = flr(time * __sample_rate)

	for _ = 0, samples - 1 do
		if pico8.current_music then
			pico8.current_music.offset = pico8.current_music.offset
				+ 7350 / (61 * pico8.current_music.speed * __sample_rate)
			if pico8.current_music.offset >= 32 then
				local next_track = pico8.current_music.music
				if pico8.music[next_track].loop == 2 then
					-- go back until we find the loop start
					while true do
						if pico8.music[next_track].loop == 1 or next_track == 0 then
							break
						end
						next_track = next_track - 1
					end
				elseif pico8.music[pico8.current_music.music].loop == 4 then
					next_track = nil
				elseif pico8.music[pico8.current_music.music].loop <= 1 then
					next_track = next_track + 1
				end
				if next_track then
					api.music(next_track)
				end
			end
		end
		-- TODO: figure out what this was used for
		--local music = pico8.current_music and pico8.music[pico8.current_music.music] or nil

		for channel = 0, 3 do
			local ch = pico8.audio_channels[channel]

			if ch.bufferpos == 0 or ch.bufferpos == nil then
				ch.buffer = love.sound.newSoundData(
					__audio_buffer_size,
					__sample_rate,
					bits,
					channels
				)
				ch.bufferpos = 0
			end
			if ch.sfx and pico8.sfx[ch.sfx] then
				local sfx = pico8.sfx[ch.sfx]
				ch.offset = ch.offset + 7350 / (61 * sfx.speed * __sample_rate)
				if sfx.loop_end ~= 0 and ch.offset >= sfx.loop_end then
					if ch.loop then
						ch.last_step = -1
						ch.offset = sfx.loop_start
					else
						pico8.audio_channels[channel].sfx = nil
					end
				elseif ch.offset >= 32 then
					pico8.audio_channels[channel].sfx = nil
				end
			end
			if ch.sfx and pico8.sfx[ch.sfx] then
				local sfx = pico8.sfx[ch.sfx]
				-- when we pass a new step
				if flr(ch.offset) > ch.last_step then
					ch.lastnote = ch.note
					ch.note, ch.instr, ch.vol, ch.fx = unpack(sfx[flr(ch.offset)])
					if ch.instr ~= 6 then
						ch.osc = osc[ch.instr]
					else
						ch.osc = ch.noise
					end
					if ch.fx == 2 then
						ch.lfo = oldosc(osc[0])
					elseif ch.fx >= 6 then
						ch.lfo = oldosc(osc["saw_lfo"])
					end
					if ch.vol > 0 then
						ch.freq = note_to_hz(ch.note)
					end
					ch.last_step = flr(ch.offset)
				end
				if ch.vol and ch.vol > 0 then
					local vol = ch.vol
					if ch.fx == 1 then
						-- slide from previous note over the length of a step
						ch.freq = lerp(
							note_to_hz(ch.lastnote or 0),
							note_to_hz(ch.note),
							ch.offset % 1
						)
					elseif ch.fx == 2 then
						-- vibrato one semitone?
						ch.freq =
							lerp(note_to_hz(ch.note), note_to_hz(ch.note + 0.5), ch.lfo(4))
					elseif ch.fx == 3 then
						-- drop/bomb slide from note to c-0
						local off = ch.offset % 1
						--local freq = lerp(note_to_hz(ch.note), note_to_hz(0), off)
						local freq = lerp(note_to_hz(ch.note), 0, off)
						ch.freq = freq
					elseif ch.fx == 4 then
						-- fade in
						vol = lerp(0, ch.vol, ch.offset % 1)
					elseif ch.fx == 5 then
						-- fade out
						vol = lerp(ch.vol, 0, ch.offset % 1)
					elseif ch.fx == 6 then
						-- fast appreggio over 4 steps
						local off = bit.band(flr(ch.offset), 0xfc)
						local lfo = flr(ch.lfo(8) * 4)
						off = off + lfo
						local note = sfx[flr(off)][1]
						ch.freq = note_to_hz(note)
					elseif ch.fx == 7 then
						-- slow appreggio over 4 steps
						local off = bit.band(flr(ch.offset), 0xfc)
						local lfo = flr(ch.lfo(4) * 4)
						off = off + lfo
						local note = sfx[flr(off)][1]
						ch.freq = note_to_hz(note)
					end
					if ch.osc then
						ch.sample = ch.osc(ch.oscpos) * vol / 7
						ch.oscpos = ch.oscpos + ch.freq / __sample_rate
						ch.buffer:setSample(ch.bufferpos, ch.sample)
					else
						--TODO: custom instruments 8-f
					end
				else
					ch.buffer:setSample(ch.bufferpos, lerp(ch.sample or 0, 0, 0.1))
					ch.sample = 0
				end
			else
				ch.buffer:setSample(ch.bufferpos, lerp(ch.sample or 0, 0, 0.1))
				ch.sample = 0
			end
			ch.bufferpos = ch.bufferpos + 1
			if ch.bufferpos == __audio_buffer_size then
				-- queue buffer and reset
				__audio_channels[channel]:queue(ch.buffer)
				__audio_channels[channel]:play()
				ch.bufferpos = 0
			end
		end
	end
end

local function isCtrlOrGuiDown()
	return love.keyboard.isDown("lctrl")
		or love.keyboard.isDown("lgui")
		or love.keyboard.isDown("rctrl")
		or love.keyboard.isDown("rgui")
end

local function isAltDown()
	return love.keyboard.isDown("lalt") or love.keyboard.isDown("ralt")
end

function start_gif_recording()
	-- start recording
	if not love.filesystem.getInfo("gifs", "directory") and not love.filesystem.createDirectory("gifs") then
		log('failed to create gif directory')
	elseif gif_recording==nil then
		local err
		gif_recording, err=gif.new("gifs/"..cartname..'-'..os.time()..'.gif')
		if not gif_recording then
			log('failed to start recording: '..err)
		else
			gif_canvas=love.graphics.newCanvas(pico8.resolution[1]*2, pico8.resolution[2]*2)
			log('starting record ...')
			return true
		end
	else
		log('recording already in progress')
	end
end

function stop_gif_recording()
	-- stop recording and save
	if gif_recording~=nil then
		gif_recording:close()
		log('saved recording to '..gif_recording.filename)
		gif_recording=nil
		gif_canvas=nil
	else
		log('no active recording')
	end
end

function love.keypressed(key, scancode, isrepeat)
	console.keypressed(key, scancode, isrepeat)
	if console.isEnabled() then
		return
	end

	if key == "r" and isCtrlOrGuiDown() and not isAltDown() then
		api.reload_cart()
		api.run()
		tastool = tastool.class()
	-- elseif
	-- 	key == "escape"
	-- 	and cartname ~= nil
	-- 	and cartname ~= initialcartname
	-- 	and cartname ~= "nocart.p8"
	-- 	and cartname ~= "editor.p8"
	-- then
	-- 	api.load(initialcartname)
	-- 	api.run()
	-- 	return
	elseif key == "q" and isCtrlOrGuiDown() and love.keyboard.isDown('lshift', 'rshift') and not isAltDown() then
		love.event.quit()
	-- elseif key == "v" and isCtrlOrGuiDown() and not isAltDown() then
	-- 	pico8.clipboard = love.system.getClipboardText()
	-- elseif pico8.can_pause and (key == "pause" or key == "p") then
	-- 	paused = not paused
	elseif key == "f1" or key == "f6" then
		-- screenshot
		local filename = cartname .. "-" .. os.time() .. ".png"
		local screenshot = love.graphics.captureScreenshot(filename)
		log("saved screenshot to", filename)
	elseif key == "f3" or key == "f8" or (key=="8" and isCtrlOrGuiDown()) then
		start_gif_recording()
	elseif key == "f4" or key == "f9" or (key=="9" and isCtrlOrGuiDown()) then
		stop_gif_recording()
	elseif key == "return" and isAltDown() then
		local canvas=love.graphics.getCanvas()
		love.graphics.setCanvas()
		love.window.setFullscreen(not love.window.getFullscreen(), "desktop")
		--for some reason this isn't called when fullscreen is unset
		love.resize(love.graphics.getWidth(), love.graphics.getHeight())
		love.graphics.setCanvas(canvas)
		return
	else
		tastool:keypressed(key, isrepeat)
	end
	if pico8.cart and pico8.cart._keydown then
		return pico8.cart._keydown(key)
	end
end

-- function love.keyreleased(key)
-- 	for p = 0, 1 do
-- 		for i = 0, #pico8.keymap[p] do
-- 			for _, testkey in pairs(pico8.keymap[p][i]) do
-- 				if key == testkey then
-- 					pico8.keypressed[p][i] = nil
-- 					break
-- 				end
-- 			end
-- 		end
-- 	end
-- 	if pico8.cart and pico8.cart._keyup then
-- 		return pico8.cart._keyup(key)
-- 	end
-- end

function love.textinput(text)
	console.textinput(text)
	if console.isEnabled() then
		return
	end

	text = text:lower()
	local validchar = false
	for i = 1, #glyphs do
		if glyphs:sub(i, i) == text then
			validchar = true
			break
		end
	end
	if validchar and pico8.cart and pico8.cart._textinput then
		return pico8.cart._textinput(text)
	end
end

function love.touchpressed(id, x, y, dx, dy, pressure)
	if pico8.cart and pico8.cart._touchdown then
		return pico8.cart._touchdown(id, x, y, dx, dy, pressure)
	end
end

function love.touchreleased(id, x, y, dx, dy, pressure)
	if pico8.cart and pico8.cart._touchup then
		return pico8.cart._touchup(id, x, y, dx, dy, pressure)
	end
end

function love.wheelmoved(_, y)
	pico8.mwheel = pico8.mwheel + y
end

function love.graphics.point(x, y)
	love.graphics.rectangle("fill", x, y, 1, 1)
end

function love.run()
	if love.load then
		love.load(love.arg.parseGameArguments(arg), arg)
	end

	-- We don't want the first frame's dt to include time taken by love.load.
	if love.timer then
		love.timer.step()
	end

	local dt = 0

	-- Main loop time.
	return function()
		-- Process events.
		if love.event then
			love.graphics.setCanvas() -- TODO: Rework this
			love.event.pump()
			love.graphics.setCanvas(pico8.screen) -- TODO: Rework this
			for name, a, b, c, d, e, f in love.event.poll() do
				if name == "quit" then
					if not love.quit or not love.quit() then
						return a or 0
					end
				end
				love.handlers[name](a, b, c, d, e, f)
			end
		end

		-- Update dt, as we'll be passing it to update
		if love.timer then
			dt = dt + love.timer.step()
		end

		-- Call update and draw
		local render = false
		if dt > pico8.frametime then
			if paused or not focus then -- luacheck: ignore 542
				-- nop
			else
				-- will pass 0 if love.timer is disabled
				if love.update then
					love.update(pico8.frametime)
				end
				update_audio(pico8.frametime)
			end
			dt = dt - pico8.frametime
			render = true
		end

		if render and love.graphics and love.graphics.isActive() then
			love.graphics.origin()
			if not paused and focus then
				if love.draw then
					love.draw()
				end
				--else
				-- TODO: fix issue with leftover paused menu
				--api.rectfill(64 - 4 * 4, 60, 64 + 4 * 4 - 2, 64 + 4 + 4, 1)
				--api.print("paused", 64 - 3 * 4, 64, (host_time * 20) % 8 < 4 and 7 or 13)
			end
			-- reset mouse wheel
			pico8.mwheel = 0
		end

		if love.timer then
			love.timer.sleep(0.001)
		end
	end
end

local _default_errhand=love.errorhandler or love.errhand

function love.errorhandler(msg)
	if tastool then
		local backup_path = tastool:save_backup()
		if backup_path then
			msg = msg.."\n\nsaved backup to"..backup_path
		else
			msg = msg.."\n\n failed to create backup"
		end
	end
	return _default_errhand(msg)

end

