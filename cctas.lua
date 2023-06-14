local tas = require("tas")

local cctas = tas:extend("cctas")

local vanilla_seeds = require("vanilla_seeds")
local api = require("api")

local console = require("console")


--TODO: probably call load_level directly
--or at least make sure rng seeds are set etc
function cctas:init()
	self:perform_inject()
	--this seems hacky, but is actually how updation order behaves in vanilla
	pico8.cart.begin_game()
	pico8.cart._draw()

	if pico8.cart.__tas_load_level and pico8.cart.__tas_level_index then
		self.cart_type = "tas"
	elseif pico8.cart.lvl_id and pico8.cart.load_level then
		self.cart_type = "evercore"
	elseif pico8.cart.room and pico8.cart.load_room then
		self.cart_type = "vanilla"
	else
		error("couldn't find functions for level index and loading levels")
	end

	self.cart_settings = pico8.cart.__tas_settings or {}

	self.level_time=0
	self.inputs_active = false

	self.super.init(self)


	rawset(console.ENV,"find_player", self.find_player)

	self.prev_obj_count=0
	self.modify_loading_jank=false
	self.first_level=self:level_index()
	self.loading_jank_offset=#pico8.cart.objects+1

	self.max_djump_overload=-1

	self.modify_rng_seeds=false
	self.rng_seed_idx = -1
	self:init_seed_objs()

	self.full_game_playback = false

	self:state_changed()
end

function cctas:perform_inject()
	for type, seed in pairs(vanilla_seeds) do
		if pico8.cart[type] ~= nil then
			seed.inject(pico8)
		end
	end

	-- add tostring metamethod to objects, for use with the console
	local init_object = pico8.cart.init_object
	pico8.cart.init_object = function(...)
		local o = init_object(...)
		if type(o)~='table' then
			return o
		end

		local mt = getmetatable(o) or {}
		mt.__tostring = function(obj)
			local type = "object"
			for k,v in pairs(pico8.cart) do
				if obj.type == v then
					type = k
					break
				end
			end
			return ("[%s] x: %g, y: %g, rem: {%g, %g}, spd: {%g, %g}"):format(type, obj.x, obj.y, obj.rem.x, obj.rem.y, obj.spd.x, obj.spd.y)
		end
		setmetatable(o, mt)
		return o
	end

	--disable screenshake
	local _draw = pico8.cart._draw
	pico8.cart._draw = function()
		if pico8.cart.shake then
			pico8.cart.shake=0
		end
		_draw()
	end
end

function cctas:toggle_key(i ,frame)
	-- don't allow changing the inputs while the player is dead
	if not self.inputs_active then
		return
	end
	self.super.toggle_key(self, i, frame)
end

function cctas:toggle_hold(i)
	if not self.inputs_active then
		return
	end
	self.super.toggle_hold(self, i)
end

function cctas:keypressed(key, isrepeat)
	if self.full_game_playback then
		self.full_game_playback = false
		self.realtime_playback = false
	--TODO: abstract this
	elseif self.realtime_playback or self.seek or self.last_selected_frame ~= -1 then
		self.super.keypressed(self,key,isrepeat)
	elseif self.modify_loading_jank then
		self:loading_jank_keypress(key,isrepeat)
	elseif self.modify_rng_seeds then
		self:rng_seed_keypress(key,isrepeat)
	elseif key=='a' and not isrepeat then
		-- TODO: telegraph this better?
		if not self.cart_settings.disable_loading_jank then
			self:full_rewind()
			self:push_undo_state()
			self.modify_loading_jank = true
		end
	elseif key=='b' and not isrepeat then
		self.rng_seed_idx = -1
		-- don't enable rng mode if no seedable objects exist
		if self:advance_seeded_obj(1) then
			--TODO: telegraph undoing this better?
			--don't push to the state stack if no seeds were changed?
			self:push_undo_state()
			self.modify_rng_seeds = true
		end
	elseif key=='f' then
		self:push_undo_state()
		self:next_level()
	elseif key=='s' then
		self:push_undo_state()
		self:prev_level()
	elseif key=='d' and love.keyboard.isDown('lshift', 'rshift') then
		self:player_rewind()
	elseif key=='g' and love.keyboard.isDown('lshift', 'rshift') then
		self:start_gif_recording()
	elseif key == 'n' and love.keyboard.isDown('lshift', 'rshift') then
		self:push_undo_state()
		self:begin_full_game_playback()
	elseif key == 'u' then
		self:push_undo_state()
		self:begin_cleanup_save()
	elseif key == '=' then
		if love.keyboard.isDown('lshift', 'rshift') then
		-- +
			if self.max_djump_overload ==-1 then
				self.max_djump_overload = pico8.cart.max_djump + 1
			else
				self.max_djump_overload = self.max_djump_overload + 1
			end
			self:load_level(self:level_index(), false)
		else
			self.max_djump_overload = -1
			self:load_level(self:level_index(), false)
		end
	elseif key == '-' then
		if self.max_djump_overload ==-1 then
			self.max_djump_overload = pico8.cart.max_djump - 1
		else
			self.max_djump_overload = self.max_djump_overload - 1
		end
		self.max_djump_overload = math.max(self.max_djump_overload, 0)
		self:load_level(self:level_index(), false)
	elseif key=='y' then
		local p = self:find_player()
		if p then
			print(p)
		end
	elseif key=='c' and love.keyboard.isDown('lctrl','rctrl','lgui','rgui') then
		--copy player position to clipboard
		local p = self:find_player()
		if p then
			love.system.setClipboardText(tostring(p))
		end
	else
		self.super.keypressed(self,key,isrepeat)
	end
end

function cctas:loading_jank_keypress(key,isrepeat)
	if key=='up' then
		self.loading_jank_offset = math.min(self.loading_jank_offset +1, math.max(#pico8.cart.objects-self.prev_obj_count + 1,0))
	elseif key == 'down' then
		self.loading_jank_offset = math.max(self.loading_jank_offset - 1, math.min(-self.prev_obj_count+1,0))
	elseif key == 'a' and not isrepeat then
		self.modify_loading_jank = false
		self:load_level(self:level_index(),false)
	end

end

function cctas:rng_seed_keypress(key,isrepeat)
	-- TODO: make seed visually update in the current frame, and make rewinding not visually broken
	if key=='up' or key == 'down' then
		local obj = pico8.cart.objects[self.rng_seed_idx]
		local seed = self:get_seed_handler(obj)
		if seed ~= nil then
			if key=='up' then
				seed.increase_seed(obj)
			else
				seed.decrease_seed(obj)
			end
			for state in self:state_iter() do
				for _, pobj in ipairs(state.cart.objects) do
					if pobj.__tas_id == obj.__tas_id then
						seed.set_seed(pobj, obj.__tas_seed)
					end
				end
			end
			-- self:rewind()
			-- self:step()
		end
	elseif key == 'right' then
		self:advance_seeded_obj(1)
	elseif key == 'left' then
		self:advance_seeded_obj(-1)
	elseif key == 'b' and not isrepeat then
		self.modify_rng_seeds = false
	end
end

-- cycle the rng seed index forward if dir is 1 and backward if it is -1
-- returns true if a seedable object exists
function cctas:advance_seeded_obj(dir)
	local i = self.rng_seed_idx == -1 and #pico8.cart.objects or self.rng_seed_idx
	local start = i
	repeat
		-- advance i by 1 cyclically (darn 1-indexed lua...)
		i = (i + dir - 1) % #pico8.cart.objects + 1
		local obj = pico8.cart.objects[i]
		local seed = self:get_seed_handler(obj)
		if seed ~= nil then
			self.rng_seed_idx = i
			return true
		end
	until i == start
	return false
end

function cctas:begin_full_game_playback()
	--TODO: fix reload speed
	api.reload_cart()
	api.run()
	self:perform_inject()
	pico8.cart.begin_game()
	pico8.cart._draw()

	self:init_seed_objs()
	self:clearstates()
	self:load_input_file()

	self.realtime_playback = true
	self.full_game_playback = true

end

function cctas:reset_editor_state()
	self.hold=0
end

function cctas:load_room_wrap(idx)
	if self.cart_type == "tas" then
		pico8.cart.__tas_load_level(idx)
	elseif self.cart_type == "evercore" then
		pico8.cart.load_level(idx)
	else
		pico8.cart.load_room(idx%8, math.floor(idx/8))
	end
end

--TODO: make the backups (in case of failure to load level) cleaner
-- if reset changes is false, loading jank and rng seeds will not be touched
-- otherwise, they will be reset
function cctas:load_level(idx, reset_changes)
	-- load the room from the initial state of the level, to reset variables like berries
	self:full_rewind()

	--backup the current state, in case of a crash
	local state_backup=self:clonestate()

	if self.max_djump_overload ~= -1 then
		pico8.cart.max_djump = self.max_djump_overload
	elseif self.cart_type == "vanilla" then
		if idx>=22 then
			pico8.cart.new_bg = true
			pico8.cart.max_djump = 2
		else
			pico8.cart.new_bg = nil
			pico8.cart.max_djump = 1
		end
	end

	local seeds = self:get_rng_seeds()
	--apply loading jank
	self.prev_obj_count=0
	local status, err = pcall(self.load_room_wrap,self,idx-1)
	if status then
		for _,obj in ipairs(pico8.cart.objects) do
			-- assume room title is destroyed before you exit the level
			-- assume no other objects will be destroyed before you exit the level
			-- (this is easy to tweak with the offset variable)
			if obj.type ~= pico8.cart.room_title or pico8.cart.room_title==nil then
				self.prev_obj_count = self.prev_obj_count + 1
			end
		end
	else
		if not self.first_level then
			print("could not load previous level for loading jank")
		end
		--restore from state backup, and recreate the backup
		pico8=state_backup
		state_backup=self:clonestate()
		love.graphics.setCanvas(pico8.screen)
	end

	status, err = pcall(self.load_room_wrap, self, idx)
	if not status then
		print("could not load level")
		--restore from state backup
		pico8=state_backup
		love.graphics.setCanvas(pico8.screen)
		return
	end

	if reset_changes then
		-- for the first level, assume no objects get loading janked by default
		-- also do not apply loading jank if it is disable
		self.loading_jank_offset =
		    (self.cart_settings.disable_loading_jank or self:level_index() == self.first_level) and #pico8.cart.objects + 1 or 0
	end

	for i = self.prev_obj_count+ self.loading_jank_offset, #pico8.cart.objects do
		local obj = pico8.cart.objects[i]
		if obj ~= nil then
			obj.move(obj.spd.x,obj.spd.y)
			if obj.type.update~=nil then
				obj.type.update(obj)
			end
		end
	end

	pico8.cart._draw()

	self:init_seed_objs()
	self:clearstates()
	self:reset_editor_state()

	if reset_changes then
		self:full_reset()
	else
		self:load_rng_seeds(seeds)
	end

end
function cctas:level_index()
	if self.cart_type == "tas" then
		return pico8.cart.__tas_level_index()
	elseif self.cart_type == "evercore" then
		return pico8.cart.lvl_id
	else
		--reimplement instead of using level_index() to support smalleste
		return pico8.cart.room.x + 8*pico8.cart.room.y
	end
end
function cctas:next_level()
	self:load_level(self:level_index()+1,true)
end
function cctas:prev_level()
	self:load_level(self:level_index()-1,true)
end

function cctas:find_player()
	for _,v in ipairs(pico8.cart.objects) do
		if v.type==pico8.cart.player then
			return v
		end
	end
end

function cctas:pushstate()
	if self.level_time>0 or self.inputs_active then
		self.level_time = self.level_time + 1
	end
	self.super.pushstate(self)
end

function cctas:popstate()
	if self.level_time>0 then
		self.level_time = self.level_time-1
	end
	return self.super.popstate(self)
end

function cctas:step()
	local lvl_idx=self:level_index()
	self.super.step(self)

	if lvl_idx~=self:level_index() then
		if self.full_game_playback then

			--for carts which use different timing variables, just don't print the time
			if type(pico8.cart.minutes)=="number" and
			   type(pico8.cart.seconds)=="number" and
			   type(pico8.cart.frames) =="number" then
				print(("%02d:%02d.%03d (%d)"):format(pico8.cart.minutes, pico8.cart.seconds, pico8.cart.frames/30*1000, self.level_time-1))
			end
			self:init_seed_objs()
			self:clearstates()
			if self:load_input_file() == nil then
				self:full_reset()
			end
		-- seeking to a frame doesn't loop the level, so seeks can handle level end manually
		--TODO: figure out if this is the right way to handle things
		elseif not self.seek then
			-- TODO: make it so clouds don't jump??
			self:full_rewind()
		end
		return
	end

	self:state_changed()
end

function cctas:rewind()
	self.super.rewind(self)
	self:state_changed()
end

function cctas:full_rewind()
	self.super.full_rewind(self)

	self:state_changed()
	self:reset_editor_state()
end

function cctas:full_reset()
	self.super.full_reset(self)

	self:reset_editor_state()
	self:init_seed_objs()
	self:state_changed()
end

function cctas:player_rewind()
	self:reset_editor_state()
	if self.level_time>0 or self.inputs_active then
		-- only call rewind() on the last step to improve performance
		for _ = 1, self.level_time-1 do
			self:popstate()
		end
		if self.level_time>0 then
			self:rewind()
		end
	else
		self.seek = {
			finish_condition = function()
				return  self.inputs_active
			end,
			on_finish = function() end,
			fast_forward=true
		}

	end
end

function cctas:start_gif_recording()
	if start_gif_recording() then
		start_gif_recording()
		self:full_rewind()
		local lvl_id = self:level_index()
		self.seek = {
			finish_condition = function() return self:level_index() ~= lvl_id end,
			on_finish = function()
				stop_gif_recording()
				self:rewind()
			end,
			finish_on_interrupt = true
		}
	end
end

function cctas:clearstates()
	self.super.clearstates(self)
	self.level_time = 0

	self:state_changed()
end

function cctas:frame_count()
	return self.level_time
end

function cctas:state_changed()
	self.inputs_active=self:predict(self.find_player,1)
end

function cctas:get_editor_state()
	local s = self.super.get_editor_state(self)
	s.prev_obj_count = self.prev_obj_count
	s.loading_jank_offset=self.loading_jank_offset
	s.level_time = self.level_time
	s.inputs_active = self.inputs_active
	s.rng_seeds = self:get_rng_seeds()
	return s
end

function cctas:load_editor_state(state)
	self.super.load_editor_state(self,state)
	self.prev_obj_count = state.prev_obj_count
	self.loading_jank_offset=state.loading_jank_offset
	self.level_time = state.level_time
	self.inputs_active = state.inputs_active
	self:load_rng_seeds(state.rng_seeds)
end


function cctas:get_seed_handler(obj, state)
	state = state or pico8
	for type, seed in pairs(vanilla_seeds) do
		if state.cart[type] ~= nil and
			state.cart[type] == obj.type then
			return seed
		end
	end
end

--loads rng seeds for the current state
--must be called on the first frame
function cctas:init_seed_objs()
	for _, obj in ipairs(pico8.cart.objects) do
		obj.__tas_id = {}
		local seed = self:get_seed_handler(obj)
		if seed ~= nil then
			seed.init(obj)
		end
	end
end

function cctas:get_rng_seeds()

	local seeds = {}
	local initial_state = self:state_iter()()
	for _, obj in ipairs(initial_state.cart.objects) do
		if obj.__tas_seed then
			table.insert(seeds, obj.__tas_seed)
		end
	end
	return seeds
end

-- loads the seed for all saved states
-- seeds not given will be left at the default value
--
function cctas:load_rng_seeds(t)
	local i=1
	local state_iter = self:state_iter()
	local initial_state = state_iter()

	--mapping of object id to seed
	local seed_mapping = {}
	for _, obj in ipairs(initial_state.cart.objects) do
		if i > #t then
			break
		end
		local seed = self:get_seed_handler(obj, initial_state)
		if seed ~= nil then
			seed.set_seed(obj,t[i])
			seed_mapping[obj.__tas_id] = t[i]
			i = i+1
		end
	end
	for state in state_iter do
		for _, obj in ipairs(state.cart.objects) do
			local seed = self:get_seed_handler(obj, state)
			if seed ~= nil and seed_mapping[obj.__tas_id] ~= nil then
				seed.set_seed(obj, seed_mapping[obj.__tas_id])
			end
		end
	end
end

function cctas:get_input_file_obj()
	local stripped_cartname = cartname:match("[^.]+")
	local dirname = stripped_cartname
	if not love.filesystem.getInfo(dirname, "directory") then
		if not love.filesystem.createDirectory(dirname) then
			print("error creating save directory")
			return nil
		end
	end

	--evercore is 1 indexed and vanilla is 0 indexed
	local file_id
	if self.cart_type == "vanilla" then
		file_id=self:level_index()+1
	else
		file_id=self:level_index()
	end

	local filename = ("%s/TAS%d.tas"):format(dirname, file_id)
	return love.filesystem.newFile(filename)
end

function cctas:get_input_str(i,j, include_seeds)
	--only include the seeds in the string for a full level input
	if i ~= nil and not include_seeds then
		return self.super.get_input_str(self,i,j)
	end
	return ("[%s]%s"):format(table.concat(self:get_rng_seeds(),","),self.super.get_input_str(self))
end

function cctas:load_input_str(str, i)
	local seeds,inputs = str:match("%[([^%]]*)%](.*)")
	if not seeds then -- try loading without rng seeds
		return self.super.load_input_str(self, str, i)
	elseif not inputs then
		print("invalid input file")
		return false
	end

	local seeds_tbl={}

	for seed in seeds:gmatch("[^,]+") do
		if tonumber(seed) == nil then
			print("invalid input file")
			return false
		else
			table.insert(seeds_tbl, tonumber(seed))
		end
	end

	if not self.super.load_input_str(self, inputs, i) then
		return false
	end
	self:load_rng_seeds(seeds_tbl)
	return true
end

function cctas:save_cleaned_input_file(last_frame)
	local f = self:get_input_file_obj()
	if not f then
		return
	end
	if f:open("w") then
		f:write(self:get_input_str(1, last_frame, true))
		print(("saved %df cleaned file to %s"):format(last_frame, love.filesystem.getRealDirectory(f:getFilename()).."/"..f:getFilename()))
	else
		print("error saving cleaned input file")
	end
end

function cctas:begin_cleanup_save()
	local lvl_id=self:level_index()
	self:save_input_file()
	self.seek={
		finish_condition = function() return self:level_index() ~= lvl_id end,
		on_finish = function()
			self:rewind()
			self:save_cleaned_input_file(self:frame_count())
		end
	}
end

function cctas:draw_button(...)

	if not self.inputs_active then
		return
	end
	self.super.draw_button(self,...)
end

function cctas:hud()
	local p=self:find_player()
	if p == nil then
		return ""
	end
	--TODO: make this more comprehensive and/or general?
	return ("%6s%7s\npos:% -7g% g\nrem:% -7.3f% .3f\nspd:% -7.3f% .3f\n\ngrace: %s"):format("x","y",p.x,p.y,p.rem.x,p.rem.y, p.spd.x, p.spd.y, p.grace)
end

function cctas:offset_camera()
	local offx, offy = pico8.cart.draw_x  or 0, pico8.cart.draw_y or 0
	love.graphics.translate(self.hud_w-offx,self.hud_h-offy)
	love.graphics.setScissor(self.hud_w*self.scale,self.hud_h*self.scale,pico8.resolution[1]*self.scale, pico8.resolution[2]*self.scale)
end

function cctas:draw()
	self.super.draw(self)
	local offset = 13
	if self.super.show_input_display(self, 1) then
		offset = 12 + 13
	end

	love.graphics.print(self:hud(),1,offset,0,2/3,2/3)

	if self.modify_loading_jank then
		love.graphics.push()
		self:offset_camera()

		for i = self.prev_obj_count + self.loading_jank_offset, #pico8.cart.objects do
			local obj = pico8.cart.objects[i]
			if obj~=nil then
				setPicoColor(6)
				love.graphics.rectangle('line', obj.x-1, obj.y-1, 10,10)
			end
		end
		love.graphics.pop()
		love.graphics.setScissor()

		love.graphics.setColor(1,1,1)
		love.graphics.printf(('loading jank offset: %+d'):format(self.loading_jank_offset),1,100,48,"left",0,2/3,2/3)
	elseif self.modify_rng_seeds then
		love.graphics.push()
		self:offset_camera()

		local obj = pico8.cart.objects[self.rng_seed_idx]
		local seed = self:get_seed_handler(obj)
		if seed ~= nil then
			seed.draw(obj)
		end
		love.graphics.pop()

		love.graphics.setColor(1,1,1)
		love.graphics.setScissor()
		love.graphics.print("rng manip mode",1,100,0,2/3,2/3)
	end

end

return cctas

