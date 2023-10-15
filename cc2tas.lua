local tas = require("tas")

local cc2tas = tas:extend("cc2tas")

local api = require("api")

local console = require("console")


--TODO: probably call load_level directly
--or at least make sure rng seeds are set etc
function cc2tas:init()
	self:perform_inject()
	--this seems hacky, but is actually how updation order behaves in vanilla
	pico8.cart.level_index=1
	pico8.cart._init()
	pico8.cart.infade=100
	pico8.cart.camera(pico8.cart.camera_x, pico8.cart.camera_y)
	pico8.cart._draw()

	if pico8.cart.__tas_load_level and pico8.cart.__tas_level_index then
		self.cart_type = "tas"
	elseif pico8.cart.goto_level and pico8.cart.level_index then
		self.cart_type = "vanilla"
	else
		error("couldn't find functions for level index and loading levels")
	end

	self.cart_settings = pico8.cart.__tas_settings or {}

	self.level_time=0

	self.super.init(self)


	rawset(console.ENV,"find_player", self.find_player)
	console.COMMANDS["set_player_env"]=function() print("switched to player environment") self.set_player_env(self) end
	console.COMMANDS["unset_player_env"]=function() print("switched to global environment") self.unset_player_env(self) end

	self.full_game_playback = false
end

function cc2tas:perform_inject()
	-- add tostring metamethod to objects, for use with the console
	local create = pico8.cart.create
	pico8.cart.create = function(...)
		local o = create(...)
		if type(o)~='table' then
			return o
		end

		local mt = getmetatable(o) or {}
		mt.__tostring = function(obj)
			local type = "object"
			for k,v in pairs(pico8.cart) do
				if obj.base == v then
					type = k
					break
				end
			end
			return ("[%s] x: %g, y: %g, rem: {%g, %g}, spd: {%g, %g}"):format(type, obj.x, obj.y, obj.remainder_x, obj.remainder_y, obj.speed_x, obj.speed_y)
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

function cc2tas:keypressed(key, isrepeat)
	if self.full_game_playback then
		self.full_game_playback = false
		self.realtime_playback = false
	--TODO: abstract this
	elseif self.realtime_playback or self.seek or self.last_selected_frame ~= -1 then
		self.super.keypressed(self,key,isrepeat)
	elseif key=='f' then
		self:push_undo_state()
		self:next_level()
	elseif key=='s' then
		self:push_undo_state()
		self:prev_level()
	elseif key=='g' and love.keyboard.isDown('lshift', 'rshift') then
		self:start_gif_recording()
	elseif key == 'n' and love.keyboard.isDown('lshift', 'rshift') then
		self:push_undo_state()
		self:begin_full_game_playback()
	elseif key == 'u' then
		self:push_undo_state()
		self:begin_cleanup_save()
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

function cc2tas:begin_full_game_playback()
	--TODO: fix reload speed
	api.reload_cart()
	api.run()
	self:perform_inject()
	pico8.cart.level_index=1
	pico8.cart._init()

	self:clearstates()
	self:load_input_file()

	self.realtime_playback = true
	self.full_game_playback = true

end

function cc2tas:reset_editor_state()
	self.hold=0
end

function cc2tas:load_room_wrap(idx)
	if self.cart_type == "tas" then
		pico8.cart.__tas_load_level(idx)
	else
		pico8.cart.goto_level(idx)
	end
end

--TODO: make the backups (in case of failure to load level) cleaner
function cc2tas:load_level(idx)
	-- load the room from the initial state of the level, to reset variables like berries
	self:full_rewind()

	--backup the current state, in case of a crash
	local state_backup=self:clonestate()

	local status, err = pcall(self.load_room_wrap, self, idx)
	if not status then
		print("could not load level")
		--restore from state backup
		pico8=state_backup
		love.graphics.setCanvas(pico8.screen)
		return
	end

	while pico8.cart.level_intro>0 do
		self:step()
	end
	pico8.cart.infade=100
	pico8.cart.camera(pico8.cart.camera_x, pico8.cart.camera_y)
	pico8.cart._draw()

	self:clearstates()
	self:reset_editor_state()

end
function cc2tas:level_index()
	if self.cart_type == "tas" then
		return pico8.cart.__tas_level_index()
	else
		return pico8.cart.level_index
	end
end
function cc2tas:next_level()
	self:load_level(self:level_index()+1)
end
function cc2tas:prev_level()
	self:load_level(self:level_index()-1)
end

function cc2tas:find_player()
	for _,v in ipairs(pico8.cart.objects) do
		if v.base==pico8.cart.player then
			return v
		end
	end
end

function cc2tas:set_player_env()
	setmetatable(console.ENV, {
		__index = function(table,key)
			local p=self:find_player()
			if p and p[key]~=nil then
				return p[key]
			end
			return pico8.cart[key]
		end,
		__newindex = function(table, key, val)
			local p=self:find_player()
			if p and p[key]~=nil then
			  p[key]=val
			else
				pico8.cart[key] = val
			end
		end
	})
end

function cc2tas:unset_player_env()
	setmetatable(console.ENV, {
		__index = function(table,key) return pico8.cart[key] end,
		__newindex = function(table, key, val) pico8.cart[key] = val end
	})
end

function cc2tas:pushstate()
	if pico8.cart.level_intro == 0 then
		self.level_time = self.level_time + 1
	end
	self.super.pushstate(self)
end

function cc2tas:popstate()
	if self.level_time>0 then
		self.level_time = self.level_time-1
	end
	return self.super.popstate(self)
end

function cc2tas:step()
	local lvl_idx=self:level_index()
	self.super.step(self)

	if lvl_idx~=self:level_index() then
		if self.full_game_playback then

			--for carts which use different timing variables, just don't print the time
			if type(pico8.cart.minutes)=="number" and
			   type(pico8.cart.seconds)=="number" and
			   type(pico8.cart.frames) =="number" then
				print(("%02d:%02d.%03d (%d)"):format(pico8.cart.minutes, pico8.cart.seconds, pico8.cart.frames/30*1000, self.level_time))
			end
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

end

function cc2tas:start_gif_recording()
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

function cc2tas:clearstates()
	self.super.clearstates(self)
	self.level_time = 0
end

function cc2tas:frame_count()
	return self.level_time
end

function cc2tas:get_editor_state()
	local s = self.super.get_editor_state(self)
	s.level_time = self.level_time
	return s
end

function cc2tas:load_editor_state(state)
	self.super.load_editor_state(self,state)
	self.level_time = state.level_time
end

function cc2tas:get_input_file_obj()
	local stripped_cartname = cartname:match("[^.]+")
	local dirname = stripped_cartname
	if not love.filesystem.getInfo(dirname, "directory") then
		if not love.filesystem.createDirectory(dirname) then
			print("error creating save directory")
			return nil
		end
	end

	local file_id=self:level_index()

	local filename = ("%s/TAS%d.tas"):format(dirname, file_id)
	return love.filesystem.newFile(filename)
end

function cc2tas:save_cleaned_input_file(last_frame)
	local f = self:get_input_file_obj()
	if not f then
		return
	end
	if f:open("w") then
		-- +1 because the input array is 1 indexed
		f:write(self:get_input_str(1, last_frame+1, true))
		print(("saved %df cleaned file to %s"):format(last_frame, love.filesystem.getRealDirectory(f:getFilename()).."/"..f:getFilename()))
	else
		print("error saving cleaned input file")
	end
end

function cc2tas:begin_cleanup_save()
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

function cc2tas:hud()
	local p=self:find_player()
	if p == nil then
		return ""
	end
	--TODO: make this more comprehensive and/or general?
	return ("%6s%7s\npos:% -7g% g\nrem:% -7.3f% .3f\nspd:% -7.3f% .3f\n\ngrace: %s\ngrapple cdown:%s"):format("x","y",p.x,p.y,p.remainder_x,p.remainder_y, p.speed_x, p.speed_y, p.t_jump_grace, p.t_grapple_cooldown)
end

function cc2tas:draw()
	self.super.draw(self)

	love.graphics.print(self:hud(),1,13,0,2/3,2/3)
end

return cc2tas

