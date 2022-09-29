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
end

function tas.update()
end

function tas.draw()
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
