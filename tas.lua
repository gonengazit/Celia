require "deepcopy"
local api = require("api")

local tas = {}

local states={}
local keystates={}

--wrapper functions

local function toggle_key(i)
	keystates[#states]=bit.bxor(keystates[#states],2^i)
end

local function key_pressed(i)
	return bit.band(keystates[#states],2^i)~=0
end

local function update_buttons()
	for i = 0, #pico8.keymap[0] do
			local v = pico8.keypressed[0][i]
			if key_pressed(i) then
				pico8.keypressed[0][i] = (v or -1) + 1
			else
				pico8.keypressed[0][i] = nil
			end
	end
end


-- deepcopy the current state, and push it to the stack
local function pushstate()
	-- don't copy any non-cart functions
	local newstate=deepcopy_no_api(pico8)

	table.insert(states,newstate)
	if keystates[#states] == nil then
		keystates[#states] = 0
	end
end

local function popstate()
	return table.remove(states)
end

local function peekstate()
	return states[#states]
end

function tas.step()

	update_buttons()

	if pico8.cart._update60 then
		pico8.cart._update60()
	elseif pico8.cart._update then
		pico8.cart._update()
	end

	if pico8.cart._draw then
		pico8.cart._draw()
	end


	--store the state
	pushstate()
end

function tas.rewind()
	-- takes 2 steps back, then 1 forward
	-- the alternative is to save the screen
	-- probably better, but i don't know how to do it.
	if #states <= 3 then
		return
	end

	--TODO:
	-- wrap this with a function so that pico8 is always a copy of the top of states without having to do it manually
	-- or to states[curr_frame] where curr_frame is some variable
	popstate()
	popstate()
	pico8=deepcopy_no_api(peekstate())
	tas.step()
end

function tas.load()
	pushstate()
	tas.screen = love.graphics.newCanvas(pico8.resolution[1]+48, pico8.resolution[2])
end

function tas.update()
end

local function draw_button(x,y,i)
	if key_pressed(i) then
		love.graphics.setColor(unpack(pico8.palette[7+1]))
	else
		love.graphics.setColor(unpack(pico8.palette[1+1]))
	end
	love.graphics.rectangle("fill", x, y, 3, 3)
end

local function draw_input_display(x,y)
	love.graphics.setColor(0,0,0)
	love.graphics.rectangle("fill", x, y, 25,11)
	draw_button(x + 12, y + 6, 0) -- l
	draw_button(x + 20, y + 6, 1) -- r
	draw_button(x + 16, y + 2, 2) -- u
	draw_button(x + 16, y + 6, 3) -- d
	draw_button(x + 2, y + 6, 4) -- z
	draw_button(x + 6, y + 6, 5) -- x
end

--returns the width of the counter
local function draw_frame_counter(x,y)
	love.graphics.setColor(0,0,0)
	local frame_count = tostring(#states)
	local width = 4*math.max(#frame_count,3)+1
	love.graphics.rectangle("fill", x, y, width, 7)
	love.graphics.setColor(255,255,255)
	love.graphics.print(frame_count, x+1,y+1)
	return width

end
function tas.draw()
	love.graphics.push()
	love.graphics.setColor(255,255,255)
	love.graphics.setCanvas(tas.screen)
	love.graphics.setShader(pico8.display_shader)
	pico8.display_shader:send("palette", shdr_unpack(pico8.display_palette))
	love.graphics.origin()
	love.graphics.setScissor()

	love.graphics.clear(30,30,30)

	local tas_w,tas_h = tas.screen:getDimensions()
	local pico8_w,pico8_h = pico8.screen:getDimensions()
	local hud_w = tas_w - pico8_w
	local hud_h = tas_h - pico8_h
	love.graphics.draw(pico8.screen, hud_w, hud_h, 0)
	love.graphics.setShader()


	-- tas tool ui drawing here
	--

	local frame_count_width = draw_frame_counter(1,1)
	draw_input_display(1+frame_count_width+1,1)

	love.graphics.setColor(255,255,255)

	love.graphics.pop()
end

function tas.keypressed(key)
	if key=='l' then
		tas.step()
	elseif key=='k' then
		tas.rewind()
	else
		for i = 0, #pico8.keymap[0] do
			for _, testkey in pairs(pico8.keymap[0][i]) do
				if key == testkey then
					toggle_key(i)
					break
				end
			end
		end
	end
end

return tas
