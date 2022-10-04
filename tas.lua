require "deepcopy"
local class = require("30log")

local tas = class("tas")


--wrapper functions

function tas:key_down(i)
	return bit.band(self.keystates[#self.states],2^i)~=0
end

function tas:key_held(i)
	return bit.band(self.hold, 2^i)~=0
end

function tas:toggle_key(i)
	self.keystates[#self.states]=bit.bxor(self.keystates[#self.states],2^i)
end

function tas:toggle_hold(i)
	self.hold=bit.bxor(self.hold,2^i)

	-- holding a key should also set it
	if self:key_held(i) then
		self.keystates[#self.states]=bit.bor(self.keystates[#self.states],2^i)
	end
end

function tas:update_buttons()
	for i = 0, #pico8.keymap[0] do
			local v = pico8.keypressed[0][i]
			if self:key_down(i) then
				pico8.keypressed[0][i] = (v or -1) + 1
			else
				pico8.keypressed[0][i] = nil
			end
	end
end


-- deepcopy the current state, and push it to the stack
function tas:pushstate()
	-- don't copy any non-cart functions
	local newstate=deepcopy_no_api(pico8)

	table.insert(self.states,newstate)
	if self.keystates[#self.states] == nil then
		self.keystates[#self.states] = 0
	end
	self.keystates[#self.states] = bit.bor(self.keystates[#self.states], self.hold)
	if not self.realtime_playback then
		for i=0, #pico8.keymap[0] do
			for _, testkey in pairs(pico8.keymap[0][i]) do
				if love.keyboard.isDown(testkey) then
					self.keystates[#self.states] = bit.bor(self.keystates[#self.states], 2^i)
					break
				end
			end
		end
	end
end

function tas:popstate()
	return table.remove(self.states)
end

--returns a deepcopy of the current state
function tas:peekstate()
	return deepcopy_no_api(self.states[#self.states])
end

function tas:clearstates()
	self.states={}
	self:pushstate()
end

-- advance the pico8 state ignoring buttons or backing up the state
local function rawstep()
	if pico8.cart._update60 then
		pico8.cart._update60()
	elseif pico8.cart._update then
		pico8.cart._update()
	end

	if pico8.cart._draw then
		pico8.cart._draw()
	end
end


function tas:step()

	self:update_buttons()
	rawstep()
	--store the state
	self:pushstate()
end

function tas:rewind()
	if #self.states <= 1 then
		return
	end

	--TODO:
	-- wrap this with a function so that pico8 is always a copy of the top of states without having to do it manually
	-- or to states[curr_frame] where curr_frame is some variable
	self:popstate()
	pico8=self:peekstate()
end

--rewind to the first frame
function tas:full_rewind()
	while #self.states>1 do
		self:popstate()
	end
	pico8=self:peekstate()
end

function tas:init()
	self.states={}
	self.keystates={}
	self.realtime_playback=false
	self.hold = 0
	self:pushstate()
	tas.screen = love.graphics.newCanvas(pico8.resolution[1]+48, pico8.resolution[2])
end

function tas:update()
	if self.realtime_playback then
		self:step()
	end
end

function tas:draw_button(x,y,i)
	if self:key_held(i) then
		love.graphics.setColor(unpack(pico8.palette[8+1]))
	elseif self:key_down(i) then
		love.graphics.setColor(unpack(pico8.palette[7+1]))
	else
		love.graphics.setColor(unpack(pico8.palette[1+1]))
	end
	love.graphics.rectangle("fill", x, y, 3, 3)
end

function tas:draw_input_display(x,y)
	love.graphics.setColor(0,0,0)
	love.graphics.rectangle("fill", x, y, 25,11)
	self:draw_button(x + 12, y + 6, 0) -- l
	self:draw_button(x + 20, y + 6, 1) -- r
	self:draw_button(x + 16, y + 2, 2) -- u
	self:draw_button(x + 16, y + 6, 3) -- d
	self:draw_button(x + 2, y + 6, 4) -- z
	self:draw_button(x + 6, y + 6, 5) -- x
end

-- can be overloaded to define different timing methods
function tas:frame_count()
	return #self.states-1
end
--returns the width of the counter
function tas:draw_frame_counter(x,y)
	love.graphics.setColor(0,0,0)
	local frame_count_str = tostring(self:frame_count())
	local width = 4*math.max(#frame_count_str,3)+1
	love.graphics.rectangle("fill", x, y, width, 7)
	love.graphics.setColor(255,255,255)
	love.graphics.print(frame_count_str, x+1,y+1)
	return width

end
function tas:draw()
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

	local frame_count_width = self:draw_frame_counter(1,1)
	self:draw_input_display(1+frame_count_width+1,1)

	love.graphics.setColor(255,255,255)

	love.graphics.pop()
end

function tas:keypressed(key, isrepeat)
	if key=='p' then
		self.realtime_playback = not self.realtime_playback
	elseif self.realtime_playback then
		-- pressing any key during realtime playback stops it during realtime playback stops it
		self.realtime_playback = false
	elseif key=='l' then
		self:step()
	elseif key=='k' then
		self:rewind()
	elseif key=='d' then
		self:full_rewind()
	else
		for i = 0, #pico8.keymap[0] do
			for _, testkey in pairs(pico8.keymap[0][i]) do
				if key == testkey  and not isrepeat then
					if love.keyboard.isDown("lshift", "rshift") then
						self:toggle_hold(i)
					else
						self:toggle_key(i)
					end
					break
				end
			end
		end
	end
end

-- b is a bitmask of the inputs
local function set_btn_state(b)
	for i = 0, #pico8.keymap[0] do
			local v = pico8.keypressed[0][i]
			if bit.band(b, 2^i)~=0 then
				pico8.keypressed[0][i] = (v or -1) + 1
			else
				pico8.keypressed[0][i] = nil
			end
	end
end
-- check whether the predicate returns truthy within num frames
-- if respect_inputs is true the current inputs are used
-- inputs has 3 options
--  a table, in which case those inputs are used
--  true, in which case the inputs currently inputted are used
--  nil, in which case no inputs will be used (all neutral)
function tas:predict(pred, num, inputs)
	if pred() then
		return true
	end

	--Backup gfx state
	--TODO: handle this better/clean this up
	love.graphics.push()
	local canvas=love.graphics.getCanvas()
	local shader=love.graphics.getShader()
	love.graphics.setCanvas(pico8.screen)

	local ret=false
	local input_tbl
	if type(inputs)=="table" then
		input_tbl=inputs
	elseif inputs then
		input_tbl={table.unpack(self.keystates,#self.states)}
	else
		input_tbl={}
	end

	for i=1,num do
		set_btn_state(input_tbl[i] or 0)
		rawstep()
		if pred() then
			ret=true
			break
		end
	end
	pico8=self:peekstate()
	love.graphics.setCanvas(canvas)
	love.graphics.setShader(shader)
	love.graphics.pop()
	return ret
end

return tas
