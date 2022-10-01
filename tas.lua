require "deepcopy"
local class = require("30log")

local tas = class("tas")

tas.states={}
tas.keystates={}

--wrapper functions

function tas:toggle_key(i)
	self.keystates[#self.states]=bit.bxor(self.keystates[#self.states],2^i)
end

function tas:key_pressed(i)
	return bit.band(self.keystates[#self.states],2^i)~=0
end

function tas:update_buttons()
	for i = 0, #pico8.keymap[0] do
			local v = pico8.keypressed[0][i]
			if self:key_pressed(i) then
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
end

function tas:popstate()
	return table.remove(self.states)
end

function tas:peekstate()
	return self.states[#self.states]
end

function tas:step()

	self:update_buttons()

	if pico8.cart._update60 then
		pico8.cart._update60()
	elseif pico8.cart._update then
		pico8.cart._update()
	end

	if pico8.cart._draw then
		pico8.cart._draw()
	end


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
	pico8=deepcopy_no_api(self:peekstate())
end

function tas:init()
	self:pushstate()
	tas.screen = love.graphics.newCanvas(pico8.resolution[1]+48, pico8.resolution[2])
end

function tas.update()
end

function tas:draw_button(x,y,i)
	if self:key_pressed(i) then
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

--returns the width of the counter
function tas:draw_frame_counter(x,y)
	love.graphics.setColor(0,0,0)
	local frame_count = tostring(#self.states)
	local width = 4*math.max(#frame_count,3)+1
	love.graphics.rectangle("fill", x, y, width, 7)
	love.graphics.setColor(255,255,255)
	love.graphics.print(frame_count, x+1,y+1)
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

function tas:keypressed(key)
	if key=='l' then
		self:step()
	elseif key=='k' then
		self:rewind()
	else
		for i = 0, #pico8.keymap[0] do
			for _, testkey in pairs(pico8.keymap[0][i]) do
				if key == testkey then
					self:toggle_key(i)
					break
				end
			end
		end
	end
end

return tas
