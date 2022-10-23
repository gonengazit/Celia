require "deepcopy"
local class = require("30log")

local tas = class("tas")
local console = require("console")
tas.hud_w = 48
tas.hud_h = 0
tas.scale = 6


--wrapper functions

-- recieves the index of the frame to check the key state of
-- index defaults to the current frame if nil
function tas:key_down(i, frame)
	frame = frame or self:frame_count() + 1
	return bit.band(self.keystates[frame],2^i)~=0
end

function tas:key_held(i)
	return bit.band(self.hold, 2^i)~=0
end

function tas:toggle_key(i, frame)
	frame = frame or self:frame_count() + 1
	self.keystates[frame]=bit.bxor(self.keystates[frame],2^i)

	--disabling a key on the current frame should also disable that hold
	if not self:key_down(i) and frame == self:frame_count() + 1 then
		self.hold=bit.band(self.hold,bit.bnot(2^i))
	end
end

function tas:toggle_hold(i)
	self.hold=bit.bxor(self.hold,2^i)

	-- holding a key should also set it
	if self:key_held(i) then
		self.keystates[self:frame_count()+1]=bit.bor(self.keystates[self:frame_count()+1],2^i)
	end
end

function tas:reset_keys()
	self.keystates[self:frame_count()+1]=0
end

function tas:insert_keystate()
	--TODO: respect hold?
	table.insert(self.keystates, self:frame_count() + 1, 0)
end

function tas:delete_keystate()
	table.remove(self.keystates, self:frame_count() + 1)
	if self:frame_count() + 1 > #self.keystates then
		table.insert(self.keystates, 0)
	end
end

function tas:delete_selection()
	for i=self:frame_count()+1, self.last_selected_frame do
		self:delete_keystate()
	end
	self.last_selected_frame = -1
end

function tas:reset_hold()
	self.hold=0
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


-- returns the keystate of the next frame
-- depending on its current state, whether the the user is holding down inputs, and the current hold
--
-- i.e, if the input is currently right, and up is held, up+right will be returned
function tas:advance_keystate(curr_keystate)
	curr_keystate = curr_keystate or 0
	curr_keystate= bit.bor(curr_keystate, self.hold)
	if not self.realtime_playback then
		for i=0, #pico8.keymap[0] do
			for _, testkey in pairs(pico8.keymap[0][i]) do
				if love.keyboard.isDown(testkey) then
					curr_keystate = bit.bor(curr_keystate, 2^i)
					break
				end
			end
		end
	end
	return curr_keystate
end

-- deepcopy the current state, and push it to the stack
-- if frame_count is overloaded, it must be updated/increased *before* calling pushstate
function tas:pushstate()
	-- don't copy any non-cart functions
	local newstate=deepcopy_no_api(pico8)

	table.insert(self.states,newstate)

	if self.keystates[self:frame_count()+1] == nil then
		self.keystates[self:frame_count()+1] = 0
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

function tas:state_iter()
	local i = 0
	local n = #self.states
	return function()
		i = i + 1
		if (i <= n) then
			return self.states[i]
		end
	end
end

-- advance the pico8 state ignoring buttons or backing up the state
local function rawstep()
	pico8.frames = pico8.frames + 1
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

	love.graphics.setCanvas(pico8.screen)
	self:update_buttons()
	rawstep()
	--store the state
	self:pushstate()

	--advance the state of pressed keys
	self.keystates[self:frame_count()+1] = self:advance_keystate(self.keystates[self:frame_count()+1])
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

function tas:full_reset()
	self:full_rewind()
	self.hold=0
	self.keystates={0}
end

function tas:init()
	scale = scale / self.scale -- scale for drawing to the screen
	self.states={}
	self.keystates={}
	self.realtime_playback=false
	self.hold = 0
	self:pushstate()
	tas.screen = love.graphics.newCanvas((pico8.resolution[1]+self.hud_w + 64)*self.scale, (pico8.resolution[2] + self.hud_h)*self.scale)

	self.last_selected_frame = -1

	console.ENV = setmetatable({print=print}, {
		__index = function(table,key) return pico8.cart[key] end,
		__newindex = function(table, key, val) pico8.cart[key] = val end
	})
end

function tas:update()
	if self.realtime_playback then
		self:step()
	end
end

local function setColor(c)
	local r,g,b,a = unpack(pico8.palette[c])
	love.graphics.setColor(r/255, g/255, b/255, a/255)
end

function tas:draw_button(x,y,i)
	if self:key_held(i) then
		setColor(8)
	elseif self:key_down(i) then
		setColor(7)
	else
		setColor(1)
	end
	love.graphics.rectangle("fill", x, y, 3, 3)
end

function tas:draw_input_display(x,y)
	setColor(0)
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
	setColor(0)
	local frame_count_str = tostring(self:frame_count())
	local width = 4*math.max(#frame_count_str,3)+1
	love.graphics.rectangle("fill", x, y, width, 7)
	setColor(7)
	love.graphics.print(frame_count_str, x+1,y+1)
	return width

end

--tbl is a table of coloredTexts, of the entries of the table
local function draw_inputs_row(tbl, x, y, c, frame_num)
	local box_w = 48/#tbl

	-- draw the frame number
	setColor(c)
	love.graphics.rectangle("fill", x, y, 16, 7)
	setColor(0)
	love.graphics.rectangle("line", x, y, 16, 7)
	love.graphics.printf(frame_num, x, y+1, 16, "right")

	for i=1, #tbl do
		setColor(c)
		love.graphics.rectangle("fill", x+(i-1)*box_w+16, y, box_w, 7)
		setColor(0)
		love.graphics.rectangle("line", x+(i-1)*box_w+16, y, box_w, 7)
		love.graphics.setColor(1,1,1,1)
		love.graphics.printf(tbl[i], x+(i-1)*box_w+16, y+1, box_w, "center")
	end
end

function tas:draw_piano_roll()
	local x=pico8.resolution[1] + self.hud_w+0.5
	local y=0

	local inputs={"l","r","u","d","z","x"}


	local header={}
	for i,v in ipairs(inputs) do
		header[i]={{0,0,0},v}
	end
	draw_inputs_row(header,x,y,10,"idx")

	local num_rows= math.floor(pico8.resolution[2]/7)-1
	local frame_count = self:frame_count() + 1

	--use 1/3rd of the rows for frames before, and 2/3rds for the frames after the curr frame
	--use make sure to use all the rows on the edges
	local start_row = math.max(frame_count - math.floor(num_rows/3), self.last_selected_frame - num_rows + 2,1)
	if start_row + num_rows - 1 > #self.keystates then
		start_row = math.max(#self.keystates - num_rows + 1, 1)
	end

	for i=start_row, math.min(start_row + num_rows - 1, #self.keystates) do
		local current_frame = i == frame_count
		local s={}
		for j=1, #inputs do
			if self:key_down(j-1, i) then
				if current_frame and self:key_held(j-1) then
					local r,g,b,a=unpack(pico8.palette[8])
					s[j]={{r/255,g/255, b/255,a/255},inputs[j]}
				else
					s[j]={{0,0,0},inputs[j]}
				end

			else
				s[j]=" "
			end
		end
		draw_inputs_row(s,x,y+7*(i - start_row + 1), current_frame and 12 or (i > frame_count and i <= self.last_selected_frame) and 13 or 7, i-1)
	end

end
function tas:draw()
	love.graphics.setColor(1,1,1,1)
	love.graphics.setCanvas(tas.screen)
	love.graphics.setShader(pico8.display_shader)
	love.graphics.origin()
	love.graphics.setScissor()

	love.graphics.clear(0.1, 0.1, 0.1)

	love.graphics.scale(tas.scale,tas.scale)
	love.graphics.draw(pico8.screen, self.hud_w, self.hud_h, 0)
	love.graphics.setShader()


	-- tas tool ui drawing here

	local frame_count_width = self:draw_frame_counter(1,1)
	self:draw_input_display(1+frame_count_width+1,1)

	self:draw_piano_roll()

	love.graphics.setColor(1,1,1,1)

end

function tas:keypressed(key, isrepeat)
	if key=='p' then
		self.realtime_playback = not self.realtime_playback
	elseif self.realtime_playback then
		-- pressing any key during realtime playback stops it during realtime playback stops it
		self.realtime_playback = false
	--TODO: block keypresses even when overloading this func
	elseif self.last_selected_frame ~= -1 then
		self:selection_keypress(key, isrepeat)
	elseif key=='l' then
		if love.keyboard.isDown('lshift', 'rshift') then
			if self:frame_count() + 1 < #self.keystates then
				self.last_selected_frame = self:frame_count() + 2
			end
		else
			self:step()
		end
	elseif key=='k' then
		self:rewind()
	elseif key=='d' then
		self:full_rewind()
	elseif key=='r' and love.keyboard.isDown('lshift','rshift') then
		self:full_reset()
	elseif key=='m' then
		self:save_input_file()
	elseif key=='w' and love.keyboard.isDown('lshift', 'rshift') then
		self:load_input_file()
	elseif key=='insert' then
		self:insert_keystate()
	elseif key=='delete' then
		self:delete_keystate()
	elseif key == 'v' and love.keyboard.isDown('lctrl', 'rctrl', 'lgui', 'rgui') then
		self:paste_inputs()
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

function tas:selection_keypress(key, isrepeat)
	local ctrl = love.keyboard.isDown("lctrl", "rctrl", "lgui", "rgui")
	if key == 'l' then
		self.last_selected_frame = math.min(self.last_selected_frame + 1, #self.keystates)
	elseif key == 'k' then
		self.last_selected_frame = self.last_selected_frame - 1
		if self.last_selected_frame <= self:frame_count() + 1 then
			self.last_selected_frame = -1
		end
	elseif key == 'escape' then
		self.last_selected_frame = -1

	elseif key=='delete' then
		self:delete_selection()
	elseif key == 'c' and ctrl then
		love.system.setClipboardText(self:get_input_str(self:frame_count() + 1, self.last_selected_frame))
	elseif key == 'x' and ctrl then
		love.system.setClipboardText(self:get_input_str(self:frame_count() + 1, self.last_selected_frame))
		self:delete_selection()
	elseif key == 'v' and ctrl then
		self:delete_selection()
	elseif not isrepeat then
		-- change the state of the key in all selected frames
		-- if alt is held, toggle the state in all the frames
		-- otherwise, toggle it in the first frame, and set all other selected frames to match it
		for i = 0, #pico8.keymap[0] do
			for _, testkey in pairs(pico8.keymap[0][i]) do
				if key == testkey then
					self:toggle_key(i)
					for frame = self:frame_count() + 2, self.last_selected_frame do
						if love.keyboard.isDown("lalt", "ralt") or self:key_down(i,frame) ~= self:key_down(i) then
							self:toggle_key(i, frame)
						end
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
		input_tbl={table.unpack(self.keystates,self:frame_count()+1)}
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

--returns number of loaded frames on success, nil if the input_str is invalid
--i is the index to insert the inputs at
--if i is nil, the current inputs will be replaced by the new ones
function tas:load_input_str(input_str, i)
	local new_inputs={}
	for input in input_str:gmatch("[^,]+") do
		if tonumber(input) == nil then
			print("invalid input file")
			return
		else
			table.insert(new_inputs, tonumber(input))
		end
	end
	if i == nil then
		self:full_reset()
		self.keystates = new_inputs
	else
		--insert the new inputs before index i
		for j,v in ipairs(new_inputs) do
			table.insert(self.keystates, i+j-1, v)
		end
	end
	return #new_inputs
end

-- i,j optional indices for start and end
function tas:get_input_str(i,j)
	return table.concat(self.keystates, ",", i, j)
end

-- get the file object of the input file
-- overloads should returns nil if the file cannot be created
function tas:get_input_file_obj()
	local stripped_cartname = cartname:match("[^.]+")
	local filename = stripped_cartname .. ".tas"
	return love.filesystem.newFile(filename)
end

function tas:save_input_file()
	local f = self:get_input_file_obj()
	if not f then
		return
	end
	if f:open("w") then
		f:write(self:get_input_str())
		print("saved file to ".. love.filesystem.getRealDirectory(f:getFilename()).."/"..f:getFilename())
	else
		print("error saving input file")
	end
end

function tas:load_input_file(f)
	f = f or self:get_input_file_obj()
	if not f then
		return
	end
	if f:open("r") then
		local data = f:read()
		self:load_input_str(data)
	else
		print("error opening input file")
	end
end

function tas:paste_inputs()
	local cnt = self:load_input_str(love.system.getClipboardText(), self:frame_count() + 1)
	self.last_selected_frame = self:frame_count() + 1 + cnt
end

return tas
