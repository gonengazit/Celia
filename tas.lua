require "deepcopy"
local class = require("30log")

local tas = class("tas")
local console = require("console")
tas.hud_w = 48
tas.hud_h = 0
tas.scale = 6
tas.pianoroll_w=65


--wrapper functions

-- recieves the index of the frame to check the key state of
-- index defaults to the current frame if nil
function tas:key_down(i, frame)
	frame = frame or self:frame_count() + 1
	return bit.band(self.inputstates[frame].keys,2^i)~=0
end

function tas:key_held(i)
	return bit.band(self.hold, 2^i)~=0
end

function tas:toggle_key(i, frame)
	frame = frame or self:frame_count() + 1
	self.inputstates[frame].keys=bit.bxor(self.inputstates[frame].keys,2^i)

	--disabling a key on the current frame should also disable that hold
	if not self:key_down(i) and frame == self:frame_count() + 1 then
		self.hold=bit.band(self.hold,bit.bnot(2^i))
	end
end

function tas:toggle_hold(i)
	self.hold=bit.bxor(self.hold,2^i)

	-- holding a key should also set it
	if self:key_held(i) then
		self.inputstates[self:frame_count()+1].keys=bit.bor(self.inputstates[self:frame_count()+1].keys,2^i)
	end
end

function tas:get_mouse(frame)
	frame = frame or self:frame_count() + 1
	return self.inputstates[frame].mouse_x, self.inputstates[frame].mouse_y, self.inputstates[frame].mouse_mask
end
function tas:set_mouse(x, y, mask, frame)
	frame = frame or self:frame_count() + 1
	self.inputstates[frame].mouse_x = x
	self.inputstates[frame].mouse_y = y
	self.inputstates[frame].mouse_mask = mask
end

local function only_space_pressed()
	return love.keyboard.isDown("space") and not love.keyboard.isDown('lctrl', 'rctrl', 'lshift', 'rshift', 'lalt', 'ralt')
end
-- frame is the current frame, for which the position is wanted
-- use the mouse position if space is hold, otherwise copy the previous frame
function tas:get_wanted_mouse_pos(frame)
	-- look at the previous frame
	if frame then
		frame = frame - 1
	else
		frame = self:frame_count()
	end
	if only_space_pressed() then
		return self.user_mouse_x, self.user_mouse_y
	else
		if frame <= 0 then
			return 1, 1
		end
		local x, y = self:get_mouse(frame)
		return x, y
	end
end

-- button is 0, 1 or 2
function tas:toggle_mouse_button(button, frame)
	frame = frame or self:frame_count() + 1
	self.inputstates[frame].mouse_mask=bit.bxor(self.inputstates[frame].mouse_mask,2^button)
end
function tas:mouse_button_down(button, frame)
	frame = frame or self:frame_count() + 1
	return bit.band(self.inputstates[frame].mouse_mask,2^button)~=0
end

function tas:reset_inputs()
	self.inputstates[self:frame_count()+1]={keys = 0, mouse_x = 1, mouse_y = 1, mouse_mask = 0}
end

function tas:insert_inputstate()
	local mouse_x, mouse_y = self:get_wanted_mouse_pos()
	table.insert(self.inputstates, self:frame_count() + 1, {keys = self.hold, mouse_x = mouse_x, mouse_y = mouse_y, mouse_mask = 0})
end

function tas:duplicate_inputstate()
	table.insert(self.inputstates, self:frame_count() + 1, deepcopy_no_api(self.inputstates[self:frame_count()+1]))
end

function tas:delete_inputstate()
	table.remove(self.inputstates, self:frame_count() + 1)
	if self:frame_count() + 1 > #self.inputstates then
		local mouse_x, mouse_y = self:get_wanted_mouse_pos()
		table.insert(self.inputstates, {keys = 0, mouse_x = mouse_x, mouse_y = mouse_y, mouse_mask = 0})
	end
end

function tas:delete_selection()
	for i=self:frame_count()+1, self.last_selected_frame do
		self:delete_inputstate()
	end
	self.last_selected_frame = -1
end

function tas:reset_hold()
	self.hold=0
end

local function update_pico8_from_frame(self, input_idx)
	-- controller buttons
	for i = 0, #pico8.keymap[0] do
			local v = pico8.keypressed[0][i]
			if self:key_down(i, input_idx) then
				pico8.keypressed[0][i] = (v or -1) + 1
			else
				pico8.keypressed[0][i] = nil
			end
	end
	-- mouse
	pico8.mouse_x , pico8.mouse_y, pico8.mouse_mask = self:get_mouse(input_idx)
end


-- returns the inputstate of the next frame
-- depending on its current state, whether the the user is holding down inputs, and the current hold
--
-- i.e, if the input is currently right, and up is held, up+right will be returned
function tas:advance_inputstate(curr_inputstate)
	local mouse_x, mouse_y = self:get_wanted_mouse_pos()
	curr_inputstate = curr_inputstate or {keys = 0, mouse_x = mouse_x, mouse_y = mouse_y, mouse_mask = 0}
	-- controller buttons
	curr_inputstate.keys = bit.bor(curr_inputstate.keys, self.hold)
	if not self.realtime_playback then
		for i=0, #pico8.keymap[0] do
			for _, testkey in pairs(pico8.keymap[0][i]) do
				if love.keyboard.isDown(testkey) then
					curr_inputstate.keys = bit.bor(curr_inputstate.keys, 2^i)
					break
				end
			end
		end
	end
	-- mouse
	for b = 0, 2 do
		if love.mouse.isDown(b + 1) then
			curr_inputstate.mouse_mask = bit.bor(curr_inputstate.mouse_mask, 2^b)
		end
	end
	return curr_inputstate
end

-- deepcopy the current state, and push it to the stack
-- if frame_count is overloaded, it must be updated/increased *before* calling pushstate
function tas:pushstate()
	-- don't copy any non-cart functions
	local clone=deepcopy_no_api(pico8)

	--push the actual pico8 instance (and not the clone) to support undoing
	table.insert(self.states,pico8)
	pico8 = clone

	if self.inputstates[self:frame_count()+1] == nil then
		local mouse_x, mouse_y = self:get_wanted_mouse_pos()
		self.inputstates[self:frame_count()+1] = {keys = 0, mouse_x = mouse_x, mouse_y = mouse_y, mouse_mask = 0}
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
	update_pico8_from_frame(self,input_idx)

	love.graphics.setCanvas(pico8.screen)
	rawstep()

	--advance the state of pressed keys, the mouse position and buttons
	self.inputstates[self:frame_count()+1] = self:advance_inputstate(self.inputstates[self:frame_count()+1])
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

	self.inputstates[self:frame_count()+1] = self:advance_inputstate(self.inputstates[self:frame_count()+1])
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
	self.inputstates={ {keys = 0, mouse_x = 1, mouse_y = 1, mouse_mask = 0} }
end

function tas:init()
	self.states={}
	self.inputstates={ {keys = 0, mouse_x = 1, mouse_y = 1, mouse_mask = 0} }
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

	-- mouse
	self:set_mouse_enabled(pico8.mouse_enabled)
	self.user_mouse_x = 1
	self.user_mouse_y = 1
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
	return {states = shallow_copy(self.states), inputstates = deepcopy(self.inputstates), pico8 = pico8}
end

function tas:load_editor_state(state)
	self.states = shallow_copy(state.states)
	self.inputstates = deepcopy(state.inputstates)
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

function tas:draw_input_display(x,y)
	setPicoColor(0)
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
	local box_w = 48/#tbl

	-- draw the frame number
	setPicoColor(c)
	love.graphics.rectangle("fill", x, y, 17, 7)
	setPicoColor(0)
	love.graphics.rectangle("line", x, y, 17, 7)
	love.graphics.printf(tostring(frame_num), x, y+1, 17, "right")

	for i=1, #tbl do
		setPicoColor(c)
		love.graphics.rectangle("fill", x+(i-1)*box_w+17, y, box_w, 7)
		setPicoColor(0)
		love.graphics.rectangle("line", x+(i-1)*box_w+17, y, box_w, 7)
		love.graphics.setColor(1,1,1,1)
		love.graphics.printf(tbl[i], x+(i-1)*box_w+17, y+1, box_w, "center")
	end
end

function tas:draw_piano_roll()
	local x=pico8.resolution[1] + self.hud_w
	local y=0

	local inputs={"l","r","u","d","z","x"}
	if self.mouse_enabled then
		table.insert(inputs, "M")
	end


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
	if start_row + num_rows - 1 > #self.inputstates then
		start_row = math.max(#self.inputstates - num_rows + 1, 1)
	end

	for i=start_row, math.min(start_row + num_rows - 1, #self.inputstates) do
		local current_frame = i == frame_count
		local s={}
		for j=1, #inputs do
			if inputs[j] ~= "M" then
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
			else -- mouse buttons column
				local _, _, mask = self:get_mouse(i)
				if mask ~= 0 then
					s[j] = {{0, 0, 0}, string.format("%u", mask)}
				else
					s[j]=" "
				end
			end
		end
		draw_inputs_row(s,x,y+7*(i - start_row + 1), current_frame and 12 or (i > frame_count and i <= self.last_selected_frame) and 13 or 7, i-1)
	end

end

-- set for_recording if you don't want the current user mouse position
-- also set for_recording if you only want colors from the Pico 8 palette (mandatory for the GIF encoder)
function tas:draw_mouse_hud(x, y, for_recording)
	if not self.mouse_enabled then
		return
	end
	setPicoColor(7)
	local pos_color = {1, 1, 1}
	if only_space_pressed() and not for_recording then
		pos_color = {1, 0, 0} -- indicates that the mouse position is being set
	end
	local m_x, m_y, m_mask = self:get_mouse()
	local pos_string = ("x: %d, y: %d"):format(m_x, m_y)
	local user_pos_string = ("(%d, %d)"):format(self.user_mouse_x, self.user_mouse_y)
	local btns_string = ("btns: %u"):format(m_mask)
	love.graphics.print({pos_color, pos_string}, x + 1, y + 1, 0, 2/3, 2/3)
	if not for_recording then
		love.graphics.print(user_pos_string, x + 1, y + 6, 0, 2/3, 2/3)
		love.graphics.print(btns_string, x + 1, y + 11, 0, 2/3, 2/3)
	else
		love.graphics.print(btns_string, x + 1, y + 6, 0, 2/3, 2/3)
	end

	-- independant of the parametres x and y: draws on the Pico 8 screen:
	-- mark user mouse position, current frame mouse position
	local screen_offset = {x = self.hud_w - 1, y = self.hud_h - 1} -- '-1' because the Pico 8 screen starts at 1,1
	if for_recording then
		screen_offset = {x = -1, y = -1}
	end
	if not for_recording then
		love.graphics.setColor(1, 0, 0, 0.5)
		love.graphics.point(self.user_mouse_x + screen_offset.x, self.user_mouse_y + screen_offset.y)
	else
		setPicoColor(8)
	end
	local mouse_x, mouse_y, mask = self:get_mouse()
	for _, offset in ipairs{ {-1, 0}, {0, -1}, {0, 0}, {1, 0}, {0, 1} } do
		love.graphics.point(mouse_x + offset[1] + screen_offset.x, mouse_y + offset[2] + screen_offset.y)
	end
	-- draw button states
	for b = 0, 2 do
		local color
		if self:mouse_button_down(b) then
			local x_offset, y_offset, width
			if b == 0 then 
				x_offset = -2
				y_offset = -2
				width = 2
			elseif b == 1 then
				x_offset = 1
				y_offset = -2
				width = 2
			else
				x_offset = 0
				y_offset = -3
				width = 1
			end
			if not for_recording then
				love.graphics.setColor(1, 0.47, 0.66, 0.5) -- setPicoColor(14) with transparency
				love.graphics.rectangle("fill", self.user_mouse_x + x_offset + screen_offset.x, self.user_mouse_y + y_offset + screen_offset.y, width, 2)
			else
				setPicoColor(14)
			end
			love.graphics.rectangle("fill", mouse_x + x_offset + screen_offset.x, mouse_y + y_offset + screen_offset.y, width, 2)
		end
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

	self:draw_mouse_hud(1, 80)

	self:draw_piano_roll()

	love.graphics.setColor(1,1,1,1)

end

function tas:draw_gif_overlay()
	local frame_count_width = self:draw_frame_counter(1,1)
	self:draw_input_display(1+frame_count_width+1,1)
	self:draw_mouse_hud(1, 128 - 11, true)
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
			if self:frame_count() + 1 < #self.inputstates then
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
			self:duplicate_inputstate()
		else
			self:insert_inputstate()
		end
	elseif key=='delete' then
		self:push_undo_state()
		self:delete_inputstate()
	elseif key == 'v' and ctrl then
		self:push_undo_state()
		self:paste_inputs()
	elseif key == 'z' and ctrl then
		if love.keyboard.isDown('lshift', 'rshift') then
			self:perform_redo()
		else
			self:preform_undo()
		end
	elseif key == 'space' then
		if ctrl and love.keyboard.isDown('lshift', 'rshift') then
			self:set_mouse_enabled(not self.mouse_enabled)
		elseif self.mouse_enabled then
			local _, _, mask = self:get_mouse()
			local mouse_x, mouse_y = self:get_wanted_mouse_pos()
			self:push_undo_state() -- TODO: may not be desired
			self:set_mouse(mouse_x, mouse_y, mask)
		end
	else
		for i = 0, #pico8.keymap[0] do
			for _, testkey in pairs(pico8.keymap[0][i]) do
				if key == testkey  and not isrepeat then
					if love.keyboard.isDown("lshift", "rshift") then
						self:push_undo_state()
						self:toggle_hold(i)
					else
						self:push_undo_state()
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
		self.last_selected_frame = math.min(self.last_selected_frame + 1, #self.inputstates)
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
		self.last_selected_frame = #self.inputstates
	elseif not isrepeat then
		-- change the state of the key in all selected frames
		-- if alt is held, toggle the state in all the frames
		-- otherwise, toggle it in the first frame, and set all other selected frames to match it
		for i = 0, #pico8.keymap[0] do
			for _, testkey in pairs(pico8.keymap[0][i]) do
				if key == testkey then
					self:push_undo_state()
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

function tas:mousemoved(x, y)
	if not self.mouse_enabled then
		return
	end
	self.user_mouse_x = x
	self.user_mouse_y = y
	if only_space_pressed() then -- set mouse pos for the current frame
		local _, _, mask = self:get_mouse()
		self:set_mouse(x, y, mask)
	end
end

function tas:mousepressed(button)
	if not self.mouse_enabled then
		return
	end
	if self.last_selected_frame ~= -1 then
		self:mousepressed_selection(button)
	else
		self:push_undo_state()
		self:toggle_mouse_button(button)
	end
end
function tas:mousepressed_selection(button)
	self:push_undo_state()
	self:toggle_mouse_button(button)
	for frame =  self:frame_count() + 2, self.last_selected_frame do
		if love.keyboard.isDown("lalt", "ralt") or self:mouse_button_down(button,frame) ~= self:mouse_button_down(button) then
			self:toggle_mouse_button(button, frame)
		end
	end
end

function tas:set_mouse_enabled(v)
	self.mouse_enabled = v
	love.mouse.setVisible(v)
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
	local p8state = pico8

	--set gfx stuff?
	pico8 = deepcopy_no_api(pico8)
	love.graphics.setCanvas(pico8.screen)

	local ret=false
	local input_tbl
	if type(inputs)=="table" then
		input_tbl=inputs
	elseif inputs then
		input_tbl = {}
		all_input_tbl={table.unpack(self.inputstates,self:frame_count()+1)}
		for i, v in pairs(all_input_tbl) do
			input_tbl[i] = v.keys
		end
	else
		input_tbl={}
	end

	for i=1,num do
		set_btn_state(input_tbl[i] or 0)
		-- TODO: also set mouse state!
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
		local keys, mouse_x, mouse_y, mouse_mask = input:match("(%d*):(%d*):(%d*):(%d*)")
		if keys == nil then
			keys = input:match("%d*") -- try the old input format
			mouse_x = 1
			mouse_y = 1
			mouse_mask = 0
			if keys == nil then
				print("invalid input file: invalid frame: ", input)
				return
			end
		end
		table.insert(new_inputs, {keys = tonumber(keys), mouse_x = tonumber(mouse_x), mouse_y = tonumber(mouse_y), mouse_mask = tonumber(mouse_mask)})
	end
	-- TODO: also read mouse
	if i == nil then
		self:full_reset()
		self.inputstates = {}
		for i, v in ipairs(new_inputs) do
			self.inputstates[i] = {keys = v.keys, mouse_x = v.mouse_x, mouse_y = v.mouse_y, mouse_mask = v.mouse_mask}
		end
	else
		--insert the new inputs before index i
		for j,v in ipairs(new_inputs) do
			table.insert(self.inputstates, i+j-1, {keys = v.keys, mouse_x = v.mouse_x, mouse_y = v.mouse_y, mouse_mask = v.mouse_mask})
		end
	end
	return #new_inputs
end

-- i,j optional indices for start and end
function tas:get_input_str(i,j)
	-- TODO: also write mouse
	local flat_inputs = {}
	for i, v in ipairs(self.inputstates) do
		local frame_str = string.format("%d:%d:%d:%d", v.keys, v.mouse_x, v.mouse_y, v.mouse_mask)
		table.insert(flat_inputs, frame_str)
	end
	return table.concat(flat_inputs, ",", i, j)
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
