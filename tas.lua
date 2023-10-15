require "deepcopy"
local class = require("30log")
local conf = require("conf")

local tas = class("tas")
local console = require("console")
tas.hud_w = 48
tas.hud_h = 0
tas.scale = 6
tas.pianoroll_w=65
tas.hide_all_input_display = false

local keymap_names = {
	[0] = {
		[0] = "l",
		[1] = "r",
		[2] = "u",
		[3] = "d",
		[4] = "z",
		[5] = "x",
		[6] = "\\" ,
		[7] = "?",
	},
	[1] = {
		[0] = "s",
		[1] = "f",
		[2] = "e",
		[3] = "d",
		[4] = "t",
		[5] = "1",
		[6] = "?",
		[7] = "?",
	},
}

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
	table.insert(self.keystates, self:frame_count() + 1, self.hold)
end

function tas:duplicate_keystate()
	table.insert(self.keystates, self:frame_count() + 1, self.keystates[self:frame_count()+1])
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

local function update_buttons(self, input_idx)
	for p = 0, 1 do
		for i = 0, #pico8.keymap[p] do
				local v = pico8.keypressed[p][i]
				if self:key_down(i + p * 8, input_idx) then
					pico8.keypressed[p][i] = (v or -1) + 1
				else
					pico8.keypressed[p][i] = nil
				end
		end
	end -- foreach player
end


-- returns the keystate of the next frame
-- depending on its current state, whether the the user is holding down inputs, and the current hold
--
-- i.e, if the input is currently right, and up is held, up+right will be returned
function tas:advance_keystate(curr_keystate)
	curr_keystate = curr_keystate or 0
	curr_keystate= bit.bor(curr_keystate, self.hold)
	if not self.realtime_playback then
		for p = 0, 1 do
			for i=0, #pico8.keymap[p] do
				for _, testkey in pairs(pico8.keymap[p][i]) do
					if love.keyboard.isDown(testkey) then
						curr_keystate = bit.bor(curr_keystate, 2^(i + p * 8))
						break
					end
				end
			end
		end -- foreach player
	end
	return curr_keystate
end

-- deepcopy the current state, and push it to the stack
-- if frame_count is overloaded, it must be updated/increased *before* calling pushstate
function tas:pushstate()
	-- don't copy any non-cart functions
	local clone=deepcopy_no_api(pico8)

	--push the actual pico8 instance (and not the clone) to support undoing
	table.insert(self.states,pico8)
	pico8 = clone

	if self.keystates[self:frame_count()+1] == nil then
		self.keystates[self:frame_count()+1] = 0
	end
end

function tas:popstate()
	return table.remove(self.states)
end

--clone the current state of the pico8 (for backup's sake)
function tas:clonestate()
	return deepcopy_no_api(pico8)
end

function tas:clearstates()
	self.states={}
end

function tas:state_iter()
	local i = 0
	local n = #self.states
	return function()
		i = i + 1
		if (i <= n) then
			return self.states[i]
		elseif i == n+1 then
			return pico8
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
	local input_idx = self:frame_count() + 1
	--store the state
	self:pushstate()

	--update based on the buttons of the 'previous' frame
	--TODO: make this cleaner
	update_buttons(self,input_idx)

	love.graphics.setCanvas(pico8.screen)
	rawstep()

	--advance the state of pressed keys
	self.keystates[self:frame_count()+1] = self:advance_keystate(self.keystates[self:frame_count()+1])
end

function tas:rewind()
	if #self.states <= 0 then
		return
	end

	pico8 = self:popstate()

	love.graphics.setCanvas(pico8.screen)
	pico8.draw_shader:send("palette", shdr_unpack(pico8.draw_palette))
	pico8.sprite_shader:send("palette", shdr_unpack(pico8.draw_palette))
	pico8.text_shader:send("palette", shdr_unpack(pico8.draw_palette))
	pico8.display_shader:send("palette", shdr_unpack(pico8.display_palette))

	restore_clip()
	restore_camera()

	self.keystates[self:frame_count()+1] = self:advance_keystate(self.keystates[self:frame_count()+1])
end

--rewind to the first frame
function tas:full_rewind()
	while #self.states>1 do
		pico8 = self:popstate()
	end
	-- for the last frame, call rewind to update the canvas, and allow overloaded funcs to update variables
	self:rewind()
end

function tas:full_reset()
	self:full_rewind()
	self.hold=0
	self.keystates={0}
end

function tas:init()
	self.states={}
	self.keystates={0}
	self.realtime_playback=false
	self.hold = 0
	tas.screen = love.graphics.newCanvas((pico8.resolution[1]+self.hud_w + self.pianoroll_w)*self.scale, (pico8.resolution[2] + self.hud_h)*self.scale)

	-- duplicated code is kinda eh but i am lazy
	local tas_w, tas_h = tas.screen:getDimensions()
	local screen_w, screen_h = love.graphics.getDimensions()
	scale = math.min(screen_w/tas_w, screen_h/tas_h) -- scale for drawing to the screen

	self.last_selected_frame = -1

	self.undo_states = {}
	self.undo_idx = 0
	self:push_undo_state()

	console.ENV = setmetatable({print=print}, {
		__index = function(table,key) return pico8.cart[key] end,
		__newindex = function(table, key, val) pico8.cart[key] = val end
	})

	--(func)on_finish, (func)finish_condition, (bool)fast_forward, (bool)finish_on_interrupt
	self.seek=nil

	self.pianoroll_inputs = {
		[0] = "l", [1] = "r", [2] = "u", [3] = "d", [4] = "z", [5] = "x",
		--[12] = "t",
	}
end

function tas:update()
	if self.realtime_playback then
		self:step()
	elseif self.seek then
		if self.seek.fast_forward then
			local t=love.timer.getTime()
			repeat
				self:step()
			until self.seek.finish_condition() or love.timer.getTime()-t>pico8.frametime*0.75
		else
			self:step()
		end

		if self.seek.finish_condition() then
			self.seek.on_finish()
			self.seek=nil
		end
	end
end


local function shallow_copy(t)
	local r={}
	for k,v in pairs(t) do
		r[k]=v
	end
	return r
end
-- states are shallow copyied (for perf reasons), meaning mutating them directly will cause undo to desync
function tas:get_editor_state()
	return {states = shallow_copy(self.states), keystates = deepcopy(self.keystates), pico8 = pico8}
end

function tas:load_editor_state(state)
	self.states = shallow_copy(state.states)
	self.keystates = deepcopy(state.keystates)
	pico8 = state.pico8
end

--undo_idx points the state to be loaded if undo is preformed
--places past it are stored to support redo
function tas:push_undo_state()
	self.undo_idx = self.undo_idx + 1
	while #self.undo_states >= self.undo_idx do
		table.remove(self.undo_states)
	end
	table.insert(self.undo_states, self:get_editor_state())

	-- limit undo history to depth 30, to avoid overusing memory
	if #self.undo_states>30 then
		table.remove(self.undo_states,1)
		self.undo_idx = self.undo_idx - 1
	end

end

function tas:preform_undo()
	if self.undo_idx == 0 then
		return
	end
	local new_state = self.undo_states[self.undo_idx]
	local curr_state = self:get_editor_state()
	self:load_editor_state(new_state)
	self.undo_states[self.undo_idx] = curr_state
	self.undo_idx = self.undo_idx - 1
	self.hold = 0
	self.last_selected_frame = -1
end

function tas:perform_redo()
	if self.undo_idx == #self.undo_states then
		return
	end
	self.undo_idx = self.undo_idx + 1
	local new_state = self.undo_states[self.undo_idx]
	local curr_state = self:get_editor_state()
	self:load_editor_state(new_state)
	self.undo_states[self.undo_idx] = curr_state
	self.hold = 0
	self.last_selected_frame = -1
end

function setPicoColor(c)
	local r,g,b,a = unpack(pico8.palette[c])
	love.graphics.setColor(r/255, g/255, b/255, a/255)
end

function tas:draw_button(x,y,i)
	if self:key_held(i) then
		if not self:key_down(i) then
			-- this is a weird state that's a bit hard (but possible) to get into
			setPicoColor(9)
		else
			setPicoColor(8)
		end
	elseif self:key_down(i) then
		setPicoColor(7)
	else
		setPicoColor(1)
	end
	love.graphics.rectangle("fill", x, y, 3, 3)
end

function tas:show_input_display(player)
	if self.hide_all_input_display then
		return false
	end
	for i = 0 + player * 8, 8 + player * 8 do
		if self.pianoroll_inputs[i] or self:key_down(i) then
			return true
		end
	end
	return false
end
function tas:draw_input_display(x,y,player)
	if not player then
		if self:show_input_display(0) then
			self:draw_input_display(x, y, 0)
		end
		if self:show_input_display(1) then
			self:draw_input_display(x, y + 12, 1)
		end
		return
	end
	setPicoColor(0)
	love.graphics.rectangle("fill", x, y, 25,11)
	self:draw_button(x + 12, y + 6, 0 + player * 8) -- l
	self:draw_button(x + 20, y + 6, 1 + player * 8) -- r
	self:draw_button(x + 16, y + 2, 2 + player * 8) -- u
	self:draw_button(x + 16, y + 6, 3 + player * 8) -- d
	self:draw_button(x + 2, y + 6, 4 + player * 8) -- z
	self:draw_button(x + 6, y + 6, 5 + player * 8) -- x
end

-- can be overloaded to define different timing methods
function tas:frame_count()
	return #self.states
end
--returns the width of the counter
function tas:draw_frame_counter(x,y)
	setPicoColor(0)
	local frame_count_str = tostring(self:frame_count())
	local width = 4*math.max(#frame_count_str,3)+1
	love.graphics.rectangle("fill", x, y, width, 7)
	setPicoColor(7)
	love.graphics.print(frame_count_str, x+1,y+1)
	return width

end

--tbl is a table of coloredTexts, of the entries of the table
local function draw_inputs_row(tbl, x, y, c, frame_num)
	local input_count = 0
	for _, _ in pairs(tbl) do
		input_count = input_count + 1
	end

	local x_scale = 1 -- to make the text less wide if needed
	if input_count > 8 then
		x_scale = 1 - (input_count - 8) / 10
	end
	local idx_w = math.ceil(17 * x_scale)
	local box_w = (48 + 17 - idx_w)/input_count

	-- draw the frame number
	setPicoColor(c)
	love.graphics.rectangle("fill", x, y, idx_w, 7)
	setPicoColor(0)
	love.graphics.rectangle("line", x, y, idx_w, 7)
	love.graphics.printf(tostring(frame_num), x, y+1, 17, "right", 0, x_scale, 1)

	local i = 1
	for input, _ in pairs(tbl) do
		setPicoColor(c)
		love.graphics.rectangle("fill", x+(i-1)*box_w+idx_w, y, box_w, 7)
		setPicoColor(0)
		love.graphics.rectangle("line", x+(i-1)*box_w+idx_w, y, box_w, 7)
		love.graphics.setColor(1,1,1,1)
		love.graphics.printf(tbl[input], x+(i-1)*box_w+idx_w, y+1, box_w / x_scale, "center", 0, x_scale, 1)
		i = i + 1
	end
end

function tas:draw_piano_roll()
	local x=pico8.resolution[1] + self.hud_w
	local y=0

	-- local inputs={"l","r","u","d","z","x"}

	local header={}
	for i,v in pairs(self.pianoroll_inputs) do
		header[i + 1]={{0,0,0},v}
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
		for j, name in pairs(self.pianoroll_inputs) do
			if self:key_down(j, i) then
				if current_frame and self:key_held(j) then
					local r,g,b,a=unpack(pico8.palette[8])
					s[j + 1]={{r/255,g/255, b/255,a/255},name}
				else
					s[j + 1]={{0,0,0},name}
				end

			else
				s[j + 1]=" "
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

function tas:draw_gif_overlay()
	local frame_count_width = self:draw_frame_counter(1,1)
	self:draw_input_display(1+frame_count_width+1,1)
end

function tas:keypressed(key, isrepeat)
	local ctrl = love.keyboard.isDown('lctrl', 'rctrl', 'lgui', 'rgui')
	if key=='p' then
		self.realtime_playback = not self.realtime_playback
	elseif self.realtime_playback then
		-- pressing any key during realtime playback stops it
		self.realtime_playback = false
	elseif self.seek then
		if self.seek.finish_on_interrupt then
			self.seek.on_finish()
		end
		self.seek=nil
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
		self:push_undo_state()
		self:full_reset()
	elseif key=='m' then
		self:save_input_file()
	elseif key=='w' and love.keyboard.isDown('lshift', 'rshift') then
		self:push_undo_state()
		self:load_input_file()
	elseif key=='insert' then
		self:push_undo_state()
		if ctrl then
			self:duplicate_keystate()
		else
			self:insert_keystate()
		end
	elseif key=='delete' then
		self:push_undo_state()
		self:delete_keystate()
	elseif key == 'v' and ctrl then
		self:push_undo_state()
		self:paste_inputs()
	elseif key == 'z' and ctrl then
		if love.keyboard.isDown('lshift', 'rshift') then
			self:perform_redo()
		else
			self:preform_undo()
		end
	elseif key == 'f11' then
		self.hide_all_input_display = not self.hide_all_input_display
	elseif not love.keyboard.isDown('lalt', 'ralt') then
		-- TODO: improve check for modifier absence
		for p = 0, 1 do
			for i = 0, #pico8.keymap[p] do
				for _, testkey in pairs(pico8.keymap[p][i]) do
					if key == testkey  and not isrepeat then
						if ctrl and love.keyboard.isDown("lshift", "rshift") then
							-- toggle piano roll display
							if self.pianoroll_inputs[i + p * 8] then
								self.pianoroll_inputs[i + p * 8] = nil
							else
								self.pianoroll_inputs[i + p * 8] = keymap_names[p][i]
							end
						elseif love.keyboard.isDown("lshift", "rshift") then
							self:push_undo_state()
							self:toggle_hold(i + p * 8)
						else
							self:push_undo_state()
							self:toggle_key(i + p * 8)
						end
						break
					end
				end
			end
		end -- foreach player
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
		self:push_undo_state()
		self:delete_selection()
	elseif key == 'c' and ctrl then
		love.system.setClipboardText(self:get_input_str(self:frame_count() + 1, self.last_selected_frame))
	elseif key == 'x' and ctrl then
		love.system.setClipboardText(self:get_input_str(self:frame_count() + 1, self.last_selected_frame))
		self:push_undo_state()
		self:delete_selection()
	elseif key == 'v' and ctrl then
		self:push_undo_state()
		self:delete_selection()
		self:paste_inputs()
	elseif key == 'z' and ctrl then
		if love.keyboard.isDown('lshift', 'rshift') then
			self:perform_redo()
		else
			self:preform_undo()
		end
	elseif key == 'home' then
		self.last_selected_frame = self:frame_count() + 2
	elseif key=='end' then
		self.last_selected_frame = #self.keystates
	elseif not isrepeat then
		-- change the state of the key in all selected frames
		-- if alt is held, toggle the state in all the frames
		-- otherwise, toggle it in the first frame, and set all other selected frames to match it
		for p = 0, 1 do
			for i = 0, #pico8.keymap[p] do
				for _, testkey in pairs(pico8.keymap[p][i]) do
					if key == testkey then
						self:push_undo_state()
						self:toggle_key(i + p * 8)
						for frame = self:frame_count() + 2, self.last_selected_frame do
							if love.keyboard.isDown("lalt", "ralt") or self:key_down((i + p * 8),frame) ~= self:key_down((i + p * 8)) then
								self:toggle_key(i + p * 8, frame)
							end
						end
						break
					end
				end
			end
		end -- foreach players
	end
end

-- b is a bitmask of the inputs
local function set_btn_state(b)
	for p = 0, 1 do
		for i = 0, #pico8.keymap[p] do
				local v = pico8.keypressed[p][i]
				if bit.band(b, 2^(i + p * 8))~=0 then
					pico8.keypressed[p][i] = (v or -1) + 1
				else
					pico8.keypressed[p][i] = nil
				end
		end
	end -- foreach player
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
	local p8state = pico8

	--set gfx stuff?
	pico8 = deepcopy_no_api(pico8)
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
	pico8 = p8state
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
			input = tonumber(input)
			table.insert(new_inputs, tonumber(input))
			if conf.auto_display_inputs then -- ensure each key of the input is displayed
				local input_n = 0
				while input > 0 do
					if bit.band(input, 1) == 1 and self.pianoroll_inputs[input_n] == nil then
						self.pianoroll_inputs[input_n] = keymap_names[math.floor(input_n / 8)][input_n % 8]
					end
					input_n = input_n + 1
					input = math.floor(input / 2)
				end
			end
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

--returns number of loaded frames on success, nil if loading failed
function tas:load_input_file(f)
	f = f or self:get_input_file_obj()
	if not f then
		return
	end
	if f:open("r") then
		local data = f:read()
		return self:load_input_str(data)
	else
		print("error opening input file")
	end
end

function tas:paste_inputs()
	local cnt = self:load_input_str(love.system.getClipboardText(), self:frame_count() + 1)
	if cnt then
		self.last_selected_frame = self:frame_count() + cnt
	end
end

--called on tas tool crash
--save a backup of the current inputs, and return the path
function tas:save_backup()
	local stripped_cartname = cartname:match("[^.]+")
	local filename = cartname .. "-" .. os.time() .. ".tas"
	if not love.filesystem.getInfo("backups", "directory") then
		if not love.filesystem.createDirectory("backups") then
			print("error creating backup directory")
			return nil
		end
	end
	local f = love.filesystem.newFile('backups/'..filename)
	if not f then
		return
	end
	if f:open("w") then
		f:write(self:get_input_str())
		local path = love.filesystem.getRealDirectory(f:getFilename()).."/"..f:getFilename()
		print("saved backup file to ".. path)
		return path
	else
		print("error saving backup of file")
	end

end

return tas
